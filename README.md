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

Requires macOS 15 or later.

## Build and run

```bash
./script/build_and_run.sh
```

The script kills a running copy, builds with SwiftPM, stages `dist/Clicker.app`
with an `Info.plist` (`LSUIElement`, local network and Bonjour usage keys),
ad-hoc signs it and launches it. Other modes:

```bash
./script/build_and_run.sh --logs        # launch and stream process logs
./script/build_and_run.sh --telemetry   # launch and stream com.jakejarvis.Clicker logs
./script/build_and_run.sh --verify      # launch and confirm the process exists
./script/build_and_run.sh --release     # optimized build (pairing math is much faster)
./script/build_and_run.sh --install     # copy to /Applications and launch from there
./script/make_icon.sh                   # regenerate Resources/AppIcon.icns
swift test                              # codec, crypto, SRP and text-input tests
```

Launching the binary with `--regular` shows a Dock icon, which some tooling
needs in order to see the process.

Clicker is intentionally menu-bar-only: it has no Dock icon and no main window.
Click the Apple TV icon in the menu bar to open the remote; right-click it for
Settings and Quit. Settings (name shown on the TV, launch at login, forgetting
pairings) slide in over the remote behind the gear button or ⌘,;
Esc or the back button returns, and Esc on the remote closes the panel.

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
whose Companion implementation is the reference for this format. The only
dependency is [BigInt](https://github.com/attaswift/BigInt) for the SRP modular
arithmetic; everything else is CryptoKit, Network and SwiftUI.

## License

[MIT](LICENSE)
