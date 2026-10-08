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
│               PanelOutsideClickMonitor
├── Views/      MenuBarView (screen switch), DevicePickerMenu, RemotePadView,
│               TVTextFieldView, PairingView, SettingsScreen, ActionMenus
├── Stores/     RemoteController (all UI-facing state), CredentialStore,
│               IdentityStore, UpdateController (Sparkle)
├── Services/   DeviceBrowser (NWBrowser) and Companion/* (OPACK, TLV8,
│               SRPClient, HAPCrypto, CompanionConnection, CompanionPairing,
│               CompanionClient, TextInputArchive)
├── Support/    Log, Surface (glass/material helpers), key wrappers
└── Models/     AppleTVDevice, PairingCredentials, RemoteCommand (HID enum,
                PowerState, ClientIdentity)
Tests/ClickerTests   codec, crypto, SRP, text-input archive, panel geometry
script/              build_and_run.sh, package_app.sh (bundle assembly + signing),
                     release.sh (notarize, DMG/zip, appcast), make_icon.sh/.swift,
                     make_status_icons.swift
Resources/           Info.plist, AppIcon.icns (generated; regenerate with script/make_icon.sh),
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
- Logs: `log show --last 5m --info --predicate 'subsystem == "com.jakejarvis.Clicker"'`.
  Categories: connection, pairing, discovery, remote, storage, updates.
  Sparkle logs under `org.sparkle-project.Sparkle`.
- Credentials live in `~/Library/Application Support/Clicker/pairings.json`
  (0600). Not Keychain, deliberately: ad-hoc signed dev builds would prompt on
  every rebuild.

## Reviewing the UI on screen

The computer-use tools cannot see or grant a menu-bar-only app. Workflow that
works:

1. `./script/build_and_run.sh --install`, then
   `open -n /Applications/Clicker.app --args --regular` (shows a Dock icon).
2. Grant "Clicker" and "Finder"; bring Finder forward so the frontmost app is
   allowed; click the appletv status item (around x=883, y=14 on a 1372x891
   frame) and `zoom` on the panel (roughly `[740, 24, 1030, 560]`).
3. Hover works with synthetic pointer moves; `.onHover` is fine in the panel.
4. Relaunch without `--regular` when done (`--install` again).

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
- Keys: a local `keyDown` monitor handles Esc (back out of Settings first,
  then close), ⌘, (Settings) and ⌘Q. Only when the event's window is the
  panel and no `NSText` is first responder. SwiftUI `.keyboardShortcut` is
  unreliable in this panel; don't rely on it.
- Dismissal: local + global mouse-down monitors close the panel on outside
  clicks, except clicks on the status button, inside the panel, in menu or
  popover windows, or while `panel.attachedSheet != nil`.
- Right-click on the status item: Settings…, Check for Updates… and Quit.
- Footer holds Apps, the update button, and Settings; power moved up beside
  the clickpad.
- SwiftUI `.popover` and `.alert` both work inside the panel (device picker
  and the Forget confirmation use them).

## Design rules (keep these consistent)

- `PanelMetrics`: width 264, corner radius 14 (panel, device control, cards,
  Quit action), inner radius 10 (rows, text field, notices), padding 14.
- Interactive surfaces use `.surface(shape)` (Liquid Glass on 26, materials on
  15). Static containers use `.card()` (flat quaternary fill + hairline).
  Never put glass on glass for non-interactive content.
- Settings: section headers `.subheadline.semibold` secondary; row titles
  `.body`; secondary text `.caption`; every action a small `.bordered` button;
  every toggle a small `.switch`; explanations go in section footers, not in
  rows. Rows are 40pt min, 12/8 padding, hairline `SettingsDivider` between.
- Full-width actions at the end of Settings use `PanelActionButton` (30pt,
  callout, primary text). Quit lives there; Check for Updates belongs there too.
- Remote buttons send HID down on press and up on release (`HoldButton`), so
  Siri hold works. Commands are serialized in `RemoteController.perform`.
- Clickpad arrows are primary-colored glyphs drawn directly on the flat ring.
  Feedback is on the glyph only: grow on hover, shrink and dim while held
  (`RemotePressStyle.Feedback.glyph`). A hover disc behind the arrow was tried
  and rejected as ugly. Only the center Select is glass.
- Power is a 32pt round glass `Menu` floating at the top right of the clickpad
  (Siri Remote placement). It needs `.menuStyle(.button)` plus a plain button
  style and `.fixedSize()`; `.borderlessButton` ignores the label frame.
- Device picker is a full-width control with a popover list; system `Menu`
  cannot show subtitles, which is why it is custom.
- State wording: connected + TV on = "Ready"; connected + off = "Asleep".
- Keyboard: arrows, Return=Select, Delete=Back, Space=Play/Pause, H=TV,
  M=Mute, +/−=Volume, Esc=close. These are in tooltips, not listed in Settings.

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
