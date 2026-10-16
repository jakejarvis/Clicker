# How Clicker works

Clicker speaks Apple's Companion protocol directly (the same one the iPhone Remote uses), so there is no Python, no bridge process and no third-party service involved. The protocol details were checked against [pyatv](https://github.com/postlund/pyatv), whose Companion implementation is the reference for this format. The dependencies are [BigInt](https://github.com/attaswift/BigInt) for the SRP modular arithmetic and [Sparkle](https://sparkle-project.org) for updates and [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) for the global shortcut that opens the panel (Carbon `RegisterEventHotKey` plus the recorder field in Settings); everything else is CryptoKit, Network and SwiftUI.

## Layout

```
Sources/Clicker
├── App/            @main app, status item, the custom glass NSPanel and its geometry
├── Views/          MenuBarView, DevicePickerMenu, RemotePadView, TVTextFieldView, RemoteOverlayCards, PINCodeField, SettingsScreen, AppPickerView, TrackpadSwipeMonitor
├── Stores/         RemoteController (app state), CredentialStore, IdentityStore, UpdateController
├── Services/       DeviceBrowser (NWBrowser for _companion-link._tcp), PortKnocker
└── Support/        glass/material surfaces

Sources/ClickerCompanion        the protocol, a separate module the app imports
├── OPACK.swift                Apple's OPACK serialization
├── TLV8.swift                 HomeKit TLV8
├── SRPClient.swift            SRP-6a (3072-bit, SHA-512) for pair-setup
├── HAPCrypto.swift            HKDF + ChaCha20-Poly1305, session cipher
├── CompanionConnection.swift  framed TCP connection, encryption, request matching
├── CompanionPairing.swift     pair-setup and pair-verify procedures
├── TextInputArchive.swift     keyed-archive payloads for the TV's text fields
├── CompanionClient.swift      session setup, HID buttons, volume, apps, power, text
└── …                          credentials, command enums, logging, small helpers
```

The app module is main-actor by default; the protocol module is nonisolated, so nothing in it is tied to the main actor. Its actors (the connection, the client, the pairing session) run their work on their own executors; its synchronous codecs run wherever they are called, which is the main actor when the app decodes an event there.

## Discovery

Discovery filters `_companion-link._tcp` results by the `rpMd` TXT record so only Apple TVs appear (Macs, iPhones and HomePods advertise the same service). The `rpFl` flags tell us whether PIN pairing is allowed, and `rpMRtID` is the stable identifier pairings are keyed by (the `rpBA` address rotates).

## Pairing and sessions

Pairing follows the HomeKit pattern over Companion frames: pair-setup (SRP with the PIN, then an Ed25519 key exchange encrypted with ChaCha20-Poly1305) produces long-term keys; every later connection runs pair-verify (X25519 + Ed25519 signatures) and derives per-direction session keys. After that, frames are encrypted with a counter nonce and the frame header as additional data, and the app registers a `com.apple.tvremoteservices` session before sending `_hidC` button events. The session stays open while the panel is closed, with an empty NoOp frame every 30 seconds so the link carries some traffic between button presses.

Buttons and keyboard keys send real press and release events, so holds work: Siri, and a held arrow key that keeps moving focus. The HID set has no mute, so Mute remembers the volume and sets it to zero.

A two-finger scroll over the clickpad becomes a finger on the TV's touch surface: `_touchStart` opens a 1000×1000 virtual pad and `_hidT` events carry press, hold and release with coordinates and a timestamp. The finger presses at the center when the gesture begins, follows the trackpad deltas, and lifts when the fingers do; the Mac's momentum events are dropped so tvOS applies its own flick physics from the release velocity, as it does for the real remote.

## Text entry

Text entry uses the TV's remote text input service: `_tiStart` reports whether a field is focused, `_tiStarted` / `_tiStopped` events track focus changes, and `_tiC` events carry `RTITextOperations` keyed archives that insert, clear or replace text (a replace asserts an empty field and inserts the new text in the same operation).

## The panel

The panel is a plain `NSStatusItem` plus a borderless, non-activating `NSPanel` that can become key (so keystrokes work without activating the app), backed by `NSGlassEffectView` on macOS 26 and behind-window vibrancy on macOS 15. SwiftUI drives the panel's height frame by frame through an animatable `GeometryEffect` (`PanelHeightBridge.swift`), so a screen switch resizes the window on the same curve as the content; one corner radius is shared by the panel, the device control and the settings cards.
