# Clicker

A native SwiftUI menu bar app for macOS that works as a remote control for
Apple TVs on your network. It speaks Apple's Companion protocol directly (the
same one the iPhone Remote uses), so there is no Python, no bridge process and
no third-party service involved.

- Finds Apple TVs over Bonjour and lets you switch between them.
- Pairs once with the four-digit PIN the TV shows; credentials are kept so later
  connections are instant.
- Directional pad, Select, Back, TV/Home, Play/Pause, volume, and press-and-hold
  Siri. Buttons send real press/release events, so holds work.
- Keyboard control while the panel is open: arrows, Return, Esc/Delete, Space,
  H, + and −.
- Launch any installed app from the Apps menu; Wake, Sleep, Screen Saver and
  Control Center from the Power menu; live power state in the header.
- Optional launch at login.

Requires macOS 14 or later.

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
swift test                              # codec, crypto and SRP tests
```

Clicker is intentionally menu-bar-only: it has no Dock icon and no main window.
Click the Apple TV icon in the menu bar to open the remote. Settings (name shown
on the TV, launch at login, forgetting pairings) are behind the gear button.

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
├── App/            @main app, menu bar extra and settings scenes
├── Views/          MenuBarView, RemotePadView, PairingView, DevicePickerView, SettingsView
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
│       └── CompanionClient.swift      session setup, HID buttons, apps, power
└── Support/        logging and small helpers
```

Discovery filters `_companion-link._tcp` results by the `rpMd` TXT record so only
Apple TVs appear (Macs, iPhones and HomePods advertise the same service). The
`rpFl` flags tell us whether PIN pairing is allowed.

Pairing follows the HomeKit pattern over Companion frames: pair-setup (SRP with
the PIN, then an Ed25519 key exchange encrypted with ChaCha20-Poly1305) produces
long-term keys; every later connection runs pair-verify (X25519 + Ed25519
signatures) and derives per-direction session keys. After that, frames are
encrypted with a counter nonce and the frame header as additional data, and the
app registers a `com.apple.tvremoteservices` session before sending `_hidC`
button events.

The protocol details were checked against [pyatv](https://github.com/postlund/pyatv),
whose Companion implementation is the reference for this format. The only
dependency is [BigInt](https://github.com/attaswift/BigInt) for the SRP modular
arithmetic; everything else is CryptoKit, Network and SwiftUI.
