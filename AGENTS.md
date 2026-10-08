# AGENTS.md

Notes for agents working on Clicker, a native SwiftUI menu bar remote for
Apple TV. Read this before changing anything; it records what the code does
on purpose and the dead ends already explored.

## What the app is

- macOS 15+ menu bar app (no Dock icon, no main window). Speaks Apple's
  Companion protocol directly to Apple TVs: Bonjour discovery, HomeKit-style
  pair-setup/pair-verify, encrypted session, HID buttons, app launch, power,
  volume, and remote text input. No bridge process, no Python.
- Only dependency: `attaswift/BigInt` for the SRP modular math. Everything
  else is CryptoKit, Network, AppKit, SwiftUI.
- Protocol details were checked against pyatv's Companion implementation
  (`pyatv/protocols/companion`, `pyatv/auth/hap_srp.py`, `support/opack.py`).
  When in doubt about a wire format, read pyatv rather than guessing.

## Layout

```
Sources/Clicker
├── App/        ClickerApp (@main + AppDelegate), StatusItemController,
│               MenuBarPanel + PanelMetrics/PanelGeometry/PanelBackdropView,
│               PanelOutsideClickMonitor, AboutPanel
├── Views/      MenuBarView (screen switch), DevicePickerMenu, RemotePadView,
│               TVTextFieldView, RemoteOverlayCards (pairing, offline,
│               searching cards), PINCodeField, SettingsScreen, ActionMenus
├── Stores/     RemoteController (all UI-facing state), CredentialStore,
│               IdentityStore, UpdateController (Sparkle)
├── Services/   DeviceBrowser (NWBrowser) and Companion/* (OPACK, TLV8,
│               SRPClient, HAPCrypto, CompanionConnection, CompanionPairing,
│               CompanionClient, TextInputArchive)
├── Support/    Log, Surface (glass/material helpers), key wrappers
└── Models/     AppleTVDevice, PairingCredentials, RemoteCommand (HID enum,
                PowerState, ClientIdentity), DemoScenario (--demo)
Tests/ClickerTests   codec, crypto, SRP, text-input archive, panel and clickpad geometry
script/              build_and_run.sh, package_app.sh (bundle assembly + signing),
                     release.sh (notarize, DMG/zip, appcast), make_icon.sh/.swift,
                     make_status_icons.swift, screenshots.sh (VMPal VM captures)
Resources/           Info.plist, Clicker.entitlements + Clicker.provisionprofile (keychain,
                     real identities only), AppIcon.icns (generated; regenerate with script/make_icon.sh),
                     StatusIcon/ menu bar glyph SVGs + generated PDFs
                     (regenerate with swift script/make_status_icons.swift)
.github/workflows/   ci.yml (test + package), release.yml (on v* tags)
site/                Vercel project for clicker.jarv.is; vercel.json rewrites
                     /appcast.xml to the gh-pages branch
```

## Build, run, test

```bash
./script/build_and_run.sh              # kill, build, stage dist/Clicker.app, launch
./script/build_and_run.sh --install    # same, but copies to /Applications and launches there
./script/build_and_run.sh --release    # optimized (SRP pairing math is much faster)
./script/build_and_run.sh --telemetry  # launch + stream com.jakejarvis.Clicker logs
swift test
swift format --in-place --recursive --parallel Sources Tests Package.swift
swift format lint --strict --recursive --parallel Sources Tests Package.swift  # CI runs this
```

- Formatting is the toolchain's `swift-format`, configured in `.swift-format`
  (4 spaces, 120 columns). `AlwaysUseLowerCamelCase` is off so SRP code can
  keep RFC 5054 names (`N`, `A`, `B`, `M1`). When its wrapping reads badly,
  restructure the code (a local `let`) rather than fighting the formatter.
- Sandboxed shells: `swift build` fails on the module cache and on git
  cloning the dependency. Run SwiftPM and the run script outside the sandbox.
- Logs: `/usr/bin/log show --last 5m --info --predicate 'subsystem == "com.jakejarvis.Clicker"'`
  (full path: zsh has a `log` builtin that swallows the arguments). Categories:
  connection, pairing, discovery, remote (every HID down/up at info), storage,
  updates. Debug-level messages are not persisted, so use info for anything
  you want to read back with `log show`.
  Sparkle logs under `org.sparkle-project.Sparkle`.
- Credentials: `CredentialStore` picks a backend at launch. Signed release
  builds use the data protection keychain (one generic-password item per TV,
  service `com.jakejarvis.Clicker.pairing`, account = device UUID, value =
  JSON `PairingCredentials`). Ad-hoc builds and CI get
  no validated entitlements and fall back to
  `~/Library/Application Support/Clicker/pairings.json` (0600). There is no
  migration between the two; a dev build after a release build looks unpaired.
  The storage log category says which backend was chosen.

## Reviewing the UI on screen

The computer-use tools cannot see or grant a menu-bar-only app. Workflow that
works:

1. `./script/build_and_run.sh --install`, then
   `open -n /Applications/Clicker.app --args --regular` (shows a Dock icon).
2. Grant "Clicker" and "Finder"; bring Finder forward so the frontmost app is
   allowed; zoom on the menu bar to find the remote-glyph status item (its x
   shifts with other status items; it has been at 838 and 883 on a 1372x891
   frame), click it, and `zoom` on the panel below it.
   Zooms taken while a mouse button is held after a `wait` come back black;
   that is a capture artifact, not the panel closing. Verify presses from the
   remote log category instead.
3. Hover works with synthetic pointer moves; `.onHover` is fine in the panel.
4. Relaunch without `--regular` when done (`--install` again).

`--demo [scenario]` (see `DemoScenario`) shows any state without a TV: fake
Living Room / Bedroom / Office devices, in-memory pairings, an instant
"connection", commands that go nowhere, and pairing that accepts any code. It
opens the panel half a second after launch and overrides the Settings name
through the volatile argument domain, so nothing is persisted. The `pin`
scenario's code field needs a click before it takes typing. Combine with
`--regular` for the computer-use workflow above.

Marketing screenshots come from `script/screenshots.sh` in a VMPal macOS VM
(stock menu bar and wallpaper). What it works around, as of VMPal 0.51:
VMPal's own screenshots are JPEG even with `--png` and capped at 2576 px, so
the script runs `screencapture` in the guest (Screen Recording for VMPal
Tools); `send_files` left the bundle without its Info.plist and with an empty
Sparkle.framework, so the app goes in as a zip through `vmpal cp`; `vmpal cp` refuses to run when invoked by bare name from PATH; a
window capture (`screencapture -l`) of the panel loses its glass, and macOS
shows its recording dot in the menu bar from the second capture in a row, so
the corner and panel shots are cropped from one full capture. Admin exec sets the clock with `date` after turning
network time off, and turns it back on at the end.

ImageRenderer and offscreen `cacheDisplay` snapshots are useless here (they
drop AppKit-backed controls and Liquid Glass); `screencapture -l` needs Screen
Recording permission. Don't retry those.

## Panel architecture (why not MenuBarExtra)

`MenuBarExtra`'s window is SwiftUI-internal chrome: no control over corner
radius, size animation, or key status. The app uses an `NSStatusItem` plus a
borderless, non-activating `NSPanel` that overrides `canBecomeKey`, modeled on
robinebers/openusage:

- Backdrop: `NSGlassEffectView` on macOS 26, behind-window `NSVisualEffectView`
  with a rounded mask on 15. The SwiftUI host layer is clipped to
  `PanelMetrics.cornerRadius`.
- Height: `NSHostingController.sizingOptions = [.preferredContentSize]`; the
  root view controller forwards `preferredContentSizeDidChange` and the panel
  animates its frame, anchored top-left, clamped to the screen.
  `MenuBarView` pins its container to the natural height of the screen being
  shown (remote or settings) so a screen switch resizes once.
- Keys: a local `keyDown` monitor handles Esc (back out of Settings, then
  an in-progress pairing, then close), ⌘, (Settings) and ⌘Q. Only when the event's window is the
  panel and no `NSText` is first responder. SwiftUI `.keyboardShortcut` is
  unreliable in this panel; don't rely on it.
- Dismissal: local + global mouse-down monitors close the panel on outside
  clicks, except clicks on the status button, inside the panel, in menu or
  popover windows, or while `panel.attachedSheet != nil`.
- Right-click on the status item: Settings…, Check for Updates…, About
  Clicker and Quit. The footer gear is a SwiftUI `Menu` (`AppMenu`) with the
  same items; About opens the standard About panel (`AboutPanel`), which
  hides the panel first via `RemoteController.dismissPanel`.
- Footer holds the update button and the gear menu (its future is open).
  Apps and Power are round menus at the clickpad's top corners. Quit is only
  in menus, never a button in Settings.
- SwiftUI `.popover` and `.alert` both work inside the panel (device picker
  and the Forget confirmation use them).

## Design rules (keep these consistent)

- `PanelMetrics`: width 264, corner radius 14 (panel, device control, cards,
  Quit action), inner radius 10 (rows, text field, notices), padding 14.
- Interactive surfaces use `.surface(shape)` (Liquid Glass on 26, materials on
  15). Static containers use `.card()` (flat quaternary fill + hairline).
  Never put glass on glass for non-interactive content.
- Buttons use `SurfaceButtonStyle(shape:)` (Surface.swift), never `.surface`
  on the outside of a `Button`: the style owns the glass, so hover and press
  wash the whole shape with `.primary` (`SurfaceHighlight`, 10%/18%: brighter
  in dark mode, darker in light), the whole control shrinks while held
  (`pressScale`, 0.96 default, 0.97 sectors, 0.98 wide controls), and a
  disabled control keeps its shape but fades its label to 40%. `glass: false`
  draws only the highlight, for the volume rocker halves inside one capsule
  and the flat footer controls. `Glass.interactive()` alone never showed any
  hover or press change in this panel, which is why the highlight is explicit.
- In dark mode untinted glass is nearly the panel's own shade, so `.surface`
  tints it `white.opacity(0.12)` there (`SurfaceModifier.glassTint`). Light
  mode gets no tint. A hairline stroke was not needed.
- Every remote glyph uses `RemoteMetrics.glyphFont` (16pt medium) and an
  outline symbol (`playpause`, `speaker.slash`, `tv`, `siri`, `power`,
  `square.grid.2x2`, chevrons, plus, minus). Filled symbols next to stroked
  ones look several times heavier whatever the weight, and a per-glyph table
  of sizes and weights (tried, with custom-drawn TV and plus/minus paths)
  looked worse than one font. Don't do either again.
- Settings: section headers `.subheadline.semibold` secondary; row titles
  `.body`; secondary text `.caption`; every action a small `.bordered` button;
  every toggle a small `.switch`; explanations go in section footers, not in
  rows. Rows are 40pt min, 12/8 padding, hairline `SettingsDivider` between.
- Full-width actions at the end of Settings use `PanelActionButton` (30pt,
  callout, primary text). Check for Updates lives there.
- Remote buttons send HID down on press and up on release (`HoldButton`), so
  Siri hold works. Commands are serialized in `RemoteController.perform`.
- Clickpad: four glass annular sectors plus a glass Select, all from
  `ClickpadGeometry` (192pt pad, 84pt Select, 6pt channels, 6pt corners).
  The straight edges are offset from the diagonals so channels have constant
  width; corners are rounded by insetting the sector and unioning a
  round-joined stroke. Each `DirectionButton` is framed to its sector's
  bounding box with the sector as content shape, so tooltips and hit testing
  match the drawing. The pad has its own `SurfaceContainer(spacing: 3)` so
  the 6pt channels do not blend; the capsule grid keeps the 10pt one. Earlier
  attempts (flat ring with secondary arrows, a hover disc behind each arrow)
  looked disabled or ugly; do not go back to them.
- Apps (top left) and Power (top right) are 32pt round glass `Menu`s
  overlaid on the clickpad (`cornerMenuStyle`). They need `.menuStyle(.button)`
  plus a plain button style and `.fixedSize()`; `.borderlessButton` ignores
  the label frame.
- Device picker is a full-width control with a popover list; system `Menu`
  cannot show subtitles, which is why it is custom.
- The remote is always drawn. When it cannot be used (unpaired, offline, no
  TVs found, none chosen) `MenuBarView` dims it to 35%, blurs it 2pt, makes
  it inert (`RemotePadView(isInteractive: false)`, no hit testing, no
  keyboard focus) and centers an `OverlayCard` over the clickpad
  (`RemoteOverlayCards.swift`). Cards are `.regularMaterial` with a hairline
  and a shadow, 212pt wide, headline + one caption + at most one row of
  buttons. Pairing morphs in place: Pair → spinner → `PINCodeField` → green
  check (`PairingState.succeeded`, 1.2s) → the remote un-ghosts. Esc backs
  out of pairing via `RemoteController.handleEscape`.
- `PINCodeField` is a focusable view collecting digits with `onKeyPress`,
  not a hidden `TextField`: a hidden field never became first responder in
  the non-activating panel, so typing went nowhere.
- State wording: connected + TV on = "Ready"; connected + off = "Asleep".
- Keyboard: arrows, Return=Select, Delete=Back, Space=Play/Pause, H=TV,
  M=Mute, +/−=Volume, Esc=close. These are in tooltips, not listed in Settings.
- Siri button: the `siri` SF Symbol (2025 catalog, macOS 26 only), painted
  with `RemoteMetrics.siriTint` (a pink → purple → blue gradient; no SF Symbol
  has a colored Siri). macOS 15 falls back to `mic` with the same gradient. `apple.intelligence` was considered and rejected
  for the fallback.

## Keychain (measured on macOS 27, 2026-10)

- The data protection keychain (`kSecUseDataProtectionKeychain`) never prompts,
  but macOS only honors `keychain-access-groups` /
  `com.apple.application-identifier` when a provisioning profile validates
  them. Without one secd answers -34018 even though the entitlements are in
  the signature; an ad-hoc binary carrying them is killed by AMFI ("restricted
  entitlements"), and a Developer ID binary without a profile is killed with
  "No matching profile found". The app-groups entitlement alone does not help.
- Probing: a plain `SecItemCopyMatching` returns "not found" even without
  validated entitlements, so it cannot detect the fallback case. The store reads
  its own `keychain-access-groups` entitlement via `SecTaskCreateFromSelf` and
  queries with that `kSecAttrAccessGroup`; -34018 there means "use the file".
- So `script/package_app.sh` embeds `Resources/Clicker.provisionprofile`
  (a Developer ID profile for com.jakejarvis.Clicker) and signs the app with
  `Resources/Clicker.entitlements` only for real identities, and refuses a real
  identity without the profile. Ad-hoc builds get neither.
- The legacy login keychain needs no profile but ties item ACLs to the
  signature, so ad-hoc rebuilds would prompt on every launch. Don't go back.
- Test the keychain path locally with `script/package_app.sh --sign <Developer
  ID>`; notarization is not needed to run a local build.

## Protocol gotchas already hit

- `Data` slices: CryptoKit ciphertext has a non-zero `startIndex`. Index by
  the value's own indices or copy (`Data(slice)`). This crashed pairing once.
- Device identity: key pairings by the TXT `rpMRtID` UUID, not `rpBA` (the
  Bluetooth address rotates). `RemoteController` migrates old keys by name +
  model when a TV reappears unpaired.
- Session nonce: 12-byte little-endian counter for encrypted frames; pairing
  nonces are 8-byte labels ("PS-Msg05") left-padded with zeros.
- SRP: RFC 5054 3072-bit group, SHA-512, `k = H(N | PAD(g))`,
  `u = H(PAD(A) | PAD(B))`, full-width `H(N) xor H(g)` in M1.
- Mute: the HID set has no mute. Mute uses `_mcc` GetVolume/SetVolume (set
  to 0, restore on unmute). Verified working on a real Apple TV.
- `FetchAttentionState` is unimplemented on newer tvOS; power state comes
  from `TVSystemStatus`/`SystemStatus` events. `TVRCSessionStart` may fail
  on older tvOS; both are best-effort.
- Text input: `_tiStart` reports a focused field; `_tiStarted`/`_tiStopped`
  events track focus; `_tiC` events carry `RTITextOperations` keyed archives
  (built with NSKeyedArchiver, `$archiver` rewritten to `RTIKeyedArchiver`).
  Reading `_tiD` walks UIDs by hand because class-name lookup can resolve to
  real private classes when AppKit is loaded. The end-to-end flow against a
  TV keyboard is still unverified by an agent; the user has not tested it yet.
- A connection attempt right after another session drops often times out
  once; `connectIfNeeded` retries once quietly.

## Unverified / open

- Text entry against a real TV keyboard.
- The macOS 15 vibrancy fallback (dev machine runs macOS 27).
- Launch at login via `SMAppService` from `/Applications`.
- Keychain storage against a real Apple TV pairing in a Developer ID build (the
  probe and item round trip were verified with a development profile only).
- The update UI (status-item dot, footer button, Settings › Updates) has not
  been looked at on screen, and no update has been installed end to end yet.
- The first notarized release. `syspolicy_check notary-submission` rejects the
  signed but un-notarized app with a generic "Gatekeeper rejected this file"
  on macOS 27, while `spctl` accepts it; trust notarytool's verdict instead.

## Updates and releases

- Sparkle 2 via SwiftPM. `script/package_app.sh` copies Sparkle.framework from
  `.build/artifacts/sparkle/...` with `ditto`, drops its XPC services (only for
  sandboxed apps), replaces SwiftPM's `.build`/toolchain rpaths with
  `@executable_path/../Frameworks`, and signs inside out without `--deep`.
- Ad-hoc builds remove `SUFeedURL`, so `UpdateController.isEnabled` is false
  and the updater never starts; Settings says updates are off. Test updates
  with Developer ID builds from `script/release.sh` (see README › Releasing).
- Gentle reminders are required for an accessory app: background finds set
  `pendingUpdateVersion` (dot on the status item, footer button) unless Sparkle
  can show the alert in immediate focus. While a Sparkle window is up the app
  switches to `.regular` and hides the panel (it floats at pop-up menu level),
  then restores the launch activation policy, so `--regular` keeps working.
- Updates are alert-only: `SUAllowsAutomaticUpdates` is false in Info.plist,
  which hides Sparkle's "automatically download and install" checkbox and
  overrides any stored preference. Settings only offers Check Automatically.
- `CFBundleVersion` is derived from the version (1.2.3 → 10203) because Sparkle
  compares it; the release tag is the only version source.
- Swift 6.4's default build system (Swift Build) records `sdk 15.0` in the
  binary's `LC_BUILD_VERSION`, while the native build system and CI's Swift 6.3
  record the real SDK. Linked-SDK checks in AppKit may differ between local
  and released builds; compare against a CI artifact if a control looks off.
- Moving from ad-hoc to Developer ID signing changes the code identity, so the
  Local Network prompt appears once more and Launch at Login may need turning
  on again.

## Conventions

- Commit messages: imperative summary, body explains why, end with the
  Co-Authored-By line in the session's attribution reminder.
- Keep files named after their primary type; keep AppKit bridging narrow
  (`App/`), SwiftUI as the source of truth for content.
- Build, run, and look at the real panel before claiming a UI change works.
