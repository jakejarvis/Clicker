# Clicker

A native SwiftUI menu bar app for macOS that works as a remote control for
Apple TVs on your network. It speaks Apple's Companion protocol directly (the
same one the iPhone Remote uses), so there is no Python, no bridge process and
no third-party service involved.

- Finds Apple TVs over Bonjour; the device control at the top shows the current
  TV's model and state and drops down a list to switch.
- Pairs once with the four-digit PIN the TV shows; credentials are kept so later
  connections are instant.
- Clickpad with a large Select, Back, TV/Home, Play/Pause, Mute, a volume
  rocker, and press-and-hold Siri. Buttons send real press/release events, so
  holds work. Mute remembers the level and sets the TV's volume to zero.
- When the Apple TV shows its on-screen keyboard, a text field slides into the
  panel and types straight into the TV.
- Keyboard control while the panel is open: arrows, Return, Delete for Back,
  Space, H, M, + and −. Esc closes the panel.
- Launch any installed app from the Apps menu; Wake, Sleep, Screen Saver and
  Control Center from the Power menu; model and power state under the title.
- Liquid Glass surfaces on macOS 26, system materials on macOS 15.
- Optional launch at login.
- Updates itself with [Sparkle](https://sparkle-project.org).

Requires macOS 15 or later.

## Install

Download `Clicker-X.Y.Z.dmg` from the
[latest release](https://github.com/jakejarvis/Clicker/releases/latest), open it
and drag Clicker to Applications. Builds are signed with a Developer ID and
notarized by Apple. Clicker checks for updates once a day; Settings › Updates
turns that off, and right-clicking the menu bar icon has **Check for Updates…**.

## Build and run

```bash
./script/build_and_run.sh
```

The script kills a running copy and calls `script/package_app.sh`, which builds
with SwiftPM, stages `dist/Clicker.app` from `Resources/Info.plist` with
Sparkle.framework embedded, and ad-hoc signs it; then it launches the app.
Ad-hoc builds leave out the feed URL, so they never update themselves. Other
modes:

```bash
./script/build_and_run.sh --logs        # launch and stream process logs
./script/build_and_run.sh --telemetry   # launch and stream com.jakejarvis.Clicker logs
./script/build_and_run.sh --verify      # launch and confirm the process exists
./script/build_and_run.sh --release     # optimized build (pairing math is much faster)
./script/build_and_run.sh --install     # copy to /Applications and launch from there
./script/make_icon.sh                   # regenerate Resources/AppIcon.icns
swift script/make_status_icons.swift   # regenerate menu bar PDFs from Resources/StatusIcon/*.svg
swift test                              # codec, crypto, SRP and text-input tests
```

Launching the binary with `--regular` shows a Dock icon, which some tooling
needs in order to see the process.

Clicker is intentionally menu-bar-only: it has no Dock icon and no main window.
Click the Apple TV icon in the menu bar to open the remote. The gear menu in
the footer (and a right-click on the menu bar icon) offers Settings, Check for
Updates, About and Quit. Settings (name shown on the TV, launch at login,
forgetting pairings) slide in over the remote; ⌘, opens them too. Esc or the
back button returns, and Esc on the remote closes the panel.

## Pairing

1. Open Clicker from the menu bar and pick an Apple TV.
2. Click **Pair…**. The Apple TV shows a four-digit PIN.
3. Type the PIN. Clicker connects as soon as the fourth digit is entered.

If the Apple TV refuses to pair, check Settings › Remotes and Devices › Remote
App and Devices on the TV. Pairing credentials are stored with owner-only
permissions in `~/Library/Application Support/Clicker/pairings.json`. Use
**Forget** in Settings to remove one.

## How it works

```
Sources/Clicker
├── App/            @main app, status item, the custom glass NSPanel and its geometry
├── Views/          MenuBarView, DevicePickerMenu, RemotePadView, TVTextFieldView, PairingView, SettingsScreen
├── Stores/         RemoteController (app state), CredentialStore, IdentityStore
├── Services/
│   ├── DeviceBrowser.swift            NWBrowser for _companion-link._tcp
│   └── Companion/
│       ├── OPACK.swift                Apple's OPACK serialization
│       ├── TLV8.swift                 HomeKit TLV8
│       ├── SRPClient.swift            SRP-6a (3072-bit, SHA-512) for pair-setup
│       ├── HAPCrypto.swift            HKDF + ChaCha20-Poly1305, session cipher
│       ├── CompanionConnection.swift  framed TCP connection, encryption, request matching
│       ├── CompanionPairing.swift     pair-setup and pair-verify procedures
│       ├── TextInputArchive.swift     keyed-archive payloads for the TV's text fields
│       └── CompanionClient.swift      session setup, HID buttons, volume, apps, power, text
└── Support/        logging, glass/material surfaces, small helpers
```

Discovery filters `_companion-link._tcp` results by the `rpMd` TXT record so only
Apple TVs appear (Macs, iPhones and HomePods advertise the same service). The
`rpFl` flags tell us whether PIN pairing is allowed, and `rpMRtID` is the stable
identifier pairings are keyed by (the `rpBA` address rotates).

Text entry uses the TV's remote text input service: `_tiStart` reports whether a
field is focused, `_tiStarted` / `_tiStopped` events track focus changes, and
`_tiC` events carry `RTITextOperations` keyed archives that insert or clear text.

Pairing follows the HomeKit pattern over Companion frames: pair-setup (SRP with
the PIN, then an Ed25519 key exchange encrypted with ChaCha20-Poly1305) produces
long-term keys; every later connection runs pair-verify (X25519 + Ed25519
signatures) and derives per-direction session keys. After that, frames are
encrypted with a counter nonce and the frame header as additional data, and the
app registers a `com.apple.tvremoteservices` session before sending `_hidC`
button events.

The panel is a plain `NSStatusItem` plus a borderless, non-activating `NSPanel`
that can become key (so keystrokes work without activating the app), backed by
`NSGlassEffectView` on macOS 26 and behind-window vibrancy on macOS 15. SwiftUI
reports its preferred height and the panel follows it; one corner radius is
shared by the panel, the device control and the settings cards.

The protocol details were checked against [pyatv](https://github.com/postlund/pyatv),
whose Companion implementation is the reference for this format. The
dependencies are [BigInt](https://github.com/attaswift/BigInt) for the SRP
modular arithmetic and [Sparkle](https://sparkle-project.org) for updates;
everything else is CryptoKit, Network and SwiftUI.

## Releasing

Pushing a `vX.Y.Z` tag runs `.github/workflows/release.yml` on a macOS runner.
It calls `script/release.sh`, which builds a universal app, signs it with the
Developer ID certificate and the hardened runtime, notarizes and staples it,
and produces `Clicker-X.Y.Z.dmg`, `Clicker-X.Y.Z.zip` and a Sparkle
`appcast.xml`. The workflow publishes the DMG and zip as a GitHub release, then
commits the appcast to the `gh-pages` branch. `https://clicker.jarv.is/appcast.xml`
(the app's `SUFeedURL`) is a Vercel rewrite to that file (`site/vercel.json`).

```bash
git tag -a v1.2.3 -m "Release notes in Markdown"
git push origin v1.2.3
```

The tag message becomes the release notes on GitHub and in Sparkle's update
window. `CFBundleVersion` is derived from the version (`1.2.3` → `10203`), so
minor and patch numbers stay below 100.

The workflow reads these from the `release` environment (restricted to `v*`
tags):

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | Developer ID Application certificate and key, `base64 -i cert.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | Password of that `.p12` |
| `ASC_API_KEY_P8` | App Store Connect team API key (Developer role), contents of the `.p8` |
| `ASC_KEY_ID`, `ASC_ISSUER_ID` | That key's ID and issuer |
| `SPARKLE_ED_PRIVATE_KEY` | Sparkle EdDSA key, from `generate_keys -x` |

To dry-run a release locally with the keychain's certificate and a notarytool
profile (`xcrun notarytool store-credentials clicker-notary`):

```bash
NOTARY_PROFILE=clicker-notary NOTES_FILE=notes.md \
  script/release.sh --version 1.2.3 --identity <certificate SHA-1>
```

Sparkle's tools (`generate_keys`, `sign_update`, `generate_appcast`) are in
`.build/artifacts/sparkle/Sparkle/bin` after `swift package resolve`. To test an
update end to end, build two versions with `DOWNLOAD_URL_PREFIX=http://localhost:8000/`,
serve the newer one's `dist/release` with `python3 -m http.server 8000`, install
the older one and launch it with `--args -SUFeedURL http://localhost:8000/appcast.xml`.

## License

[MIT](LICENSE)
