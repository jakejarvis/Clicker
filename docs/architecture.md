# Architecture

Clicker is a macOS 15+ menu bar app (no Dock icon, no main window) that speaks Apple's Companion protocol directly to Apple TVs, the same protocol the iPhone's Remote uses: Bonjour discovery, HomeKit-style pair-setup and pair-verify, an encrypted session, HID buttons, touch, app launch, power, volume and remote text input. There is no bridge process and no Python. The wire formats were checked against [pyatv](https://github.com/postlund/pyatv)'s Companion implementation (`pyatv/protocols/companion`, `pyatv/auth/hap_srp.py`, `support/opack.py`); when in doubt about a format, read pyatv rather than guessing.

Dependencies: [BigInt](https://github.com/attaswift/BigInt) for the SRP modular arithmetic, [Sparkle](https://sparkle-project.org) 2 for updates (a default package trait, left out of the Mac App Store build: see [app-store.md](app-store.md)), and [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) for the global shortcut's storage and Carbon registration. Everything else is CryptoKit, Network, AppKit and SwiftUI.

The rest of the docs are listed in the [index](README.md).

## Layout

```
Sources/Clicker                  the shipped executable: main.swift runs ClickerApp with .live
Sources/ClickerDemo              the development executable: the same app plus --demo
├── main.swift  parses --demo; without it, runs .live like Clicker
├── DemoScenario                 every scenario as data: TVs, behavior, steps, timings
├── DemoTV                       a made-up Apple TV: TXT record, endpoint, how it answers
├── DemoWorld, DemoEnvironment   builds RemoteDependencies from a scenario; plays its steps
└── DemoSession, DemoPairingSession, DemoDiscovery, DemoCredentialBackend, DemoSettings

Sources/ClickerApp               the app, a library both executables run
├── App/        ClickerApp (App, AppDelegate), AppEnvironment, StatusItemController, MenuBarPanel,
│               PanelMetrics / PanelGeometry / PanelBackdropView, PanelHeightBridge,
│               PanelOutsideClickMonitor, AboutWindow, PanelHotKey
├── Views/      MenuBarView (screen switch, notices), RemotePadView, ClickpadGeometry,
│               DevicePickerMenu, AppPickerView, TVTextFieldView, PINCodeField,
│               RemoteOverlayCards, InlineNoticeView, SettingsScreen, ShortcutRow,
│               ActionMenus, AboutView, Spinner, TrackpadSwipeMonitor
├── Intents/    the Shortcuts actions, their entities and RemoteButton, IntentHost, IntentError
│               (see intents.md)
├── Stores/     RemoteController (all UI-facing state), RemoteDependencies, ControllerSettings,
│               CredentialStore, IdentityStore, UpdateController (Sparkle)
├── Services/   DeviceDiscovery, RemoteSession, PairingSession (the seams), DeviceBrowser
│               (NWBrowser), PortKnocker (Rescan's wake knock)
├── Support/    Surface (glass and material helpers, SurfaceButtonStyle)
└── Models/     AppleTVDevice, RemoteCommand+Display, TrackpadSwipe

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
                container-migration.plist, InternetAccessPolicy.plist, AppIcon.icon,
                StatusIcon/
script/         build_and_run.sh, package_app.sh, release.sh, render_icon.sh,
                make_status_icons.swift
.github/        ci.yml (lint, test, package both builds), release.yml (on v* tags), dependabot.yml
site/           the Astro website (see site.md)
```

Files are named after their primary type. AppKit bridging stays narrow and lives in `App/`; SwiftUI is the source of truth for content. `RemoteCommand+Display.swift` holds the app-only presentation of protocol types (button titles, SF Symbols, power tooltips).

## Modules and isolation

`Package.swift` (tools 6.2) has one trait, `Sparkle`, on by default and off in the [Mac App Store build](app-store.md), and four targets:

- `ClickerApp`, the app, builds with `.defaultIsolation(MainActor.self)`: everything is on the main actor unless it says otherwise, so `@MainActor` is not written on stores or views. Pure value types that SwiftUI or the tests use off the main actor (`ClickpadGeometry`, `PanelGeometry`, `TrackpadSwipe`, `AppleTVDevice`, `ConnectionInfo`, `IdentityStore`, `PanelHeightEffect`) are marked `nonisolated`, as are the `RemoteSession` and `PairingSession` protocols the protocol module's actors conform to. What the executables need is `package`: `ClickerApp.run(in:)`, `AppEnvironment`, `RemoteDependencies` and its protocols, and the few `RemoteController` and `UpdateController` members a demo step touches.
- `Clicker`, the shipped executable, is just a `main.swift`. `ClickerDemo` has its own `main.swift` plus the demo sources (scenarios and fakes); only it reads `--demo`, and nothing `Clicker` builds depends on it. See [development.md](development.md#demo-mode). Both build with the same Swift settings as `ClickerApp`.
- `ClickerCompanion` keeps Swift's nonisolated default, so nothing in it is main-actor isolated. Its actors (the connection, the client, the pairing session) run on their own executors; a synchronous codec such as `TextInputArchive.session(from:)` runs on whatever actor calls it, which is the main actor when `RemoteController.listenForEvents` decodes an event. It exposes its API with `package` access: anything the app or the tests need must say `package`, inits of structs included, since memberwise inits are internal.

All targets enable the `NonisolatedNonsendingByDefault` and `InferIsolatedConformances` upcoming features: a nonisolated `async` function runs on its caller's actor unless it is `@concurrent`.

## Where state lives

`RemoteController` owns everything the UI shows: the device list (fed by `DeviceDiscovery`, which is `DeviceBrowser` in a real run), the selected TV, pairing state, the live `RemoteSession` (a `CompanionClient`), connection and power state, media-control flags, the text-input session, notices, and the transient UI flags other parts of the app consult (the Apps picker and device popover being open, shortcut recording, held keys). Commands go through `RemoteController.perform`, which serializes them; Shortcuts actions reach the controller through `IntentHost` and use `send`, the awaited form of `perform`, on the same queue ([intents.md](intents.md)). Everything it reaches outside the process goes through `RemoteDependencies`, built once at launch by the `AppEnvironment`; what it remembers between launches (selection, recents, favorites, last addresses, each TV's last fetched apps) goes through `ControllerSettings`, which is user defaults in a real run. `CredentialStore` keeps pairings, `IdentityStore` the client's own identity, and `UpdateController` wraps Sparkle (compiled out of the App Store build, where `UpdateController.isIncluded` is false).
