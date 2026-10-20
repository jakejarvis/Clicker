# Architecture

Clicker is a macOS 15+ menu bar app (no Dock icon, no main window) that speaks Apple's Companion protocol directly to Apple TVs, the same protocol the iPhone's Remote uses: Bonjour discovery, HomeKit-style pair-setup and pair-verify, an encrypted session, HID buttons, touch, app launch, power, volume and remote text input. There is no bridge process and no Python. The wire formats were checked against [pyatv](https://github.com/postlund/pyatv)'s Companion implementation (`pyatv/protocols/companion`, `pyatv/auth/hap_srp.py`, `support/opack.py`); when in doubt about a format, read pyatv rather than guessing.

Dependencies: [BigInt](https://github.com/attaswift/BigInt) for the SRP modular arithmetic, [Sparkle](https://sparkle-project.org) 2 for updates (a default package trait, left out of the Mac App Store build: see [app-store.md](app-store.md)), and [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) for the global shortcut's storage and Carbon registration. Everything else is CryptoKit, Network, AppKit and SwiftUI.

The rest of the docs are listed in the [index](README.md).

## Layout

```
Sources/Clicker                  the app
├── App/        ClickerApp (@main, AppDelegate), StatusItemController, MenuBarPanel,
│               PanelMetrics / PanelGeometry / PanelBackdropView, PanelHeightBridge,
│               PanelOutsideClickMonitor, AboutPanel, PanelHotKey
├── Views/      MenuBarView (screen switch, notices), RemotePadView, ClickpadGeometry,
│               DevicePickerMenu, AppPickerView, TVTextFieldView, PINCodeField,
│               RemoteOverlayCards, InlineNoticeView, SettingsScreen, ShortcutRow,
│               ActionMenus, Spinner, TrackpadSwipeMonitor
├── Stores/     RemoteController (all UI-facing state), CredentialStore, IdentityStore,
│               UpdateController (Sparkle)
├── Services/   DeviceBrowser (NWBrowser), PortKnocker (Rescan's wake knock)
├── Support/    Surface (glass and material helpers, SurfaceButtonStyle)
└── Models/     AppleTVDevice, RemoteCommand+Display, TrackpadSwipe, DemoScenario

Sources/ClickerCompanion         the protocol, a separate module the app imports
├── OPACK, TLV8                  Apple's OPACK serialization, HomeKit TLV8
├── SRPClient, HAPCrypto         SRP-6a for pair-setup; HKDF, ChaCha20-Poly1305, session cipher
├── CompanionFrame, CompanionConnection   framing, encryption, request matching, keep-alive
├── CompanionPairing             pair-setup and pair-verify
├── CompanionClient              session setup, HID, touch, media control, apps, power, text
├── TextInputArchive             keyed-archive payloads for the TV's text fields
└── PairingCredentials, RemoteCommand, Log, ContinuationGate, SymmetricKey+Data

Tests/ClickerTests, Tests/ClickerCompanionTests   see testing.md
Resources/      Info.plist, Clicker.entitlements, Clicker.provisionprofile,
                Clicker-AppStore.provisionprofile, PrivacyInfo.xcprivacy,
                container-migration.plist, AppIcon.icon, StatusIcon/
script/         build_and_run.sh, package_app.sh, release.sh, render_icon.sh,
                make_status_icons.swift, screenshots.sh
.github/        ci.yml (lint, test, package both builds), release.yml (on v* tags), dependabot.yml
site/           the Astro website (see development.md)
```

Files are named after their primary type. AppKit bridging stays narrow and lives in `App/`; SwiftUI is the source of truth for content. `RemoteCommand+Display.swift` holds the app-only presentation of protocol types (button titles, SF Symbols, power tooltips).

## Modules and isolation

`Package.swift` (tools 6.2) has one trait, `Sparkle`, on by default and off in the [Mac App Store build](app-store.md), and two targets with different defaults:

- `Clicker`, the app, builds with `.defaultIsolation(MainActor.self)`: everything is on the main actor unless it says otherwise, so `@MainActor` is not written on stores or views. Pure value types that SwiftUI or the tests use off the main actor (`ClickpadGeometry`, `PanelGeometry`, `TrackpadSwipe`, `AppleTVDevice`, `ConnectionInfo`, `DemoScenario`, `IdentityStore`, `PanelHeightEffect`) are marked `nonisolated`.
- `ClickerCompanion` keeps Swift's nonisolated default, so nothing in it is main-actor isolated. Its actors (the connection, the client, the pairing session) run on their own executors; a synchronous codec such as `TextInputArchive.session(from:)` runs on whatever actor calls it, which is the main actor when `RemoteController.listenForEvents` decodes an event. It exposes its API with `package` access: anything the app or the tests need must say `package`, inits of structs included, since memberwise inits are internal.

Both targets enable the `NonisolatedNonsendingByDefault` and `InferIsolatedConformances` upcoming features: a nonisolated `async` function runs on its caller's actor unless it is `@concurrent`.

## Where state lives

`RemoteController` owns everything the UI shows: the device list (fed by `DeviceBrowser`), the selected TV, pairing state, the live `CompanionClient`, connection and power state, media-control flags, the text-input session, notices, and the transient UI flags other parts of the app consult (the Apps picker and device popover being open, shortcut recording, held keys). Commands go through `RemoteController.perform`, which serializes them. `CredentialStore` keeps pairings, `IdentityStore` the client's own identity, and `UpdateController` wraps Sparkle (compiled out of the App Store build, where `UpdateController.isIncluded` is false).
