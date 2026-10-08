# How Clicker works

Clicker speaks Apple's Companion protocol directly (the same one the iPhone Remote uses), so there is no Python, no bridge process and no third-party service involved. The protocol details were checked against [pyatv](https://github.com/postlund/pyatv), whose Companion implementation is the reference for this format. The dependencies are [BigInt](https://github.com/attaswift/BigInt) for the SRP modular arithmetic and [Sparkle](https://sparkle-project.org) for updates; everything else is CryptoKit, Network and SwiftUI.

## Layout

```
Sources/Clicker
├── App/            @main app, status item, the custom glass NSPanel and its geometry
├── Views/          MenuBarView, DevicePickerMenu, RemotePadView, TVTextFieldView, RemoteOverlayCards, PINCodeField, SettingsScreen, AppPickerView
├── Stores/         RemoteController (app state), CredentialStore, IdentityStore, UpdateController
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

## Discovery

Discovery filters `_companion-link._tcp` results by the `rpMd` TXT record so only Apple TVs appear (Macs, iPhones and HomePods advertise the same service). The `rpFl` flags tell us whether PIN pairing is allowed, and `rpMRtID` is the stable identifier pairings are keyed by (the `rpBA` address rotates).

## Pairing and sessions

Pairing follows the HomeKit pattern over Companion frames: pair-setup (SRP with the PIN, then an Ed25519 key exchange encrypted with ChaCha20-Poly1305) produces long-term keys; every later connection runs pair-verify (X25519 + Ed25519 signatures) and derives per-direction session keys. After that, frames are encrypted with a counter nonce and the frame header as additional data, and the app registers a `com.apple.tvremoteservices` session before sending `_hidC` button events. The session stays open while the panel is closed, with an empty NoOp frame every 30 seconds so the link carries some traffic between button presses.

Buttons send real press and release events, so holds (Siri) work. The HID set has no mute, so Mute remembers the volume and sets it to zero.

## Text entry

Text entry uses the TV's remote text input service: `_tiStart` reports whether a field is focused, `_tiStarted` / `_tiStopped` events track focus changes, and `_tiC` events carry `RTITextOperations` keyed archives that insert or clear text.

## The panel

The panel is a plain `NSStatusItem` plus a borderless, non-activating `NSPanel` that can become key (so keystrokes work without activating the app), backed by `NSGlassEffectView` on macOS 26 and behind-window vibrancy on macOS 15. SwiftUI reports its preferred height and the panel follows it; one corner radius is shared by the panel, the device control and the settings cards.
