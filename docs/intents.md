# Shortcuts actions (App Intents)

Clicker offers its remote to the Shortcuts app, and so to automations and Spotlight, through Apple's [App Intents](https://developer.apple.com/documentation/appintents) framework. The code is in `Sources/ClickerApp/Intents/`. There are no App Shortcuts (Siri phrases); see [No Siri phrases](#no-siri-phrases).

## The actions

| Action | Type | Does |
|---|---|---|
| Press Remote Button | `PressButtonIntent` | Presses one of the 17 buttons in `RemoteButton` (every `HIDCommand` but Sleep and Wake) |
| Open App on Apple TV | `OpenTVAppIntent` | Launches an app by bundle identifier and adds it to the recents, as the Apps picker does |
| Put Apple TV to Sleep | `SleepAppleTVIntent` | Presses Sleep, as the power menu does |
| Wake Apple TV | `WakeAppleTVIntent` | Presses Wake |
| Type Text on Apple TV | `TypeTextIntent` | Types into the TV's focused field, then Return if asked; fails when no field is focused |
| Switch Apple TV | `SwitchAppleTVIntent` | Selects a TV, as the device menu does |
| Show Remote | `ShowRemoteIntent` | Opens the panel |

Every action but the last two takes an optional Apple TV. Left empty it means the TV selected in the panel. Given, the action selects that TV first, exactly as picking it in the device menu does, so the panel follows: the controller holds one session, and a temporary override would tear it down and rebuild it twice per action.

Two entities back the pickers. `AppleTVEntity` lists paired TVs, online or not, so an automation can wake one that is asleep. `TVAppEntity` lists the connected TV's apps or, while none is connected, every TV's last fetched list. That cache is `knownAppsByDevice` in `ControllerSettings`, written after each app fetch and kept like the recents (dropped with a pairing, moved with a re-keyed one). Without it the editor's app picker is empty whenever the TV is asleep. An app is launched by bundle identifier, so one picked from one TV opens on any TV that has it.

## How an action reaches the app

`AppDelegate.applicationDidFinishLaunching` sets `IntentHost.controller` and `IntentHost.openPanel`. The system may launch Clicker just to run an action, and an action can arrive while the launch is still going, so `IntentHost.current()` waits up to five seconds for the controller. Each intent's `perform()` resolves the controller and calls `perform(on:)`, which is what the tests call with a demo controller.

`RemoteController.prepareForIntent(deviceID:)` gets the TV ready: it selects the named TV, waits up to `RemoteTimings.intentDiscoveryTimeout` (five seconds) for Bonjour to report the selected one (knocking first if it is offline, as Rescan does), and connects. A failed connect gets a fresh attempt, unlike a panel press, which `readyClient` drops after a failure until the next Retry or panel open. The reason comes back as an `IntentError` in the panel's words: no TV selected, not paired, not found on the network, the connect's own failure message, or no focused text field.

Commands then go through `RemoteController.send`, the awaited form of `perform`. Both use one synchronous `enqueue`, so an action's command keeps its place in the same queue as the panel's presses. `perform` still drops a command silently when there is no session; `send` throws `CommandNotSent` instead. Intent presses log to the `remote` category with "from Shortcuts" appended (`Press Play/Pause from Shortcuts`).

## Isolation

`ClickerApp` is main-actor by default, and App Intents' protocols require `SendableMetatype`, which an isolated conformance can't satisfy. The shapes that compile:

- **Intents** are main-actor structs with a `nonisolated` conformance: `struct PressButtonIntent: nonisolated AppIntent`. Their `title`, `description`, `parameterSummary` and empty `init()` are marked `nonisolated`, and `perform()` is marked `@MainActor`, since the conformance otherwise infers it nonisolated. Don't write `nonisolated struct` for an intent with parameters: the `@Parameter` wrapper's storage is a mutable reference, and the compiler refuses `nonisolated` on it.
- **Entities, queries and `RemoteButton`** have only immutable or value storage, so they are `nonisolated` types. The query methods are `@MainActor`, since they read the controller.

## Literals the build reads

The system learns titles, descriptions, parameter names and enum case names from the bundle, not by running the app, so they must be literals. `RemoteButton.caseDisplayRepresentations` therefore repeats the titles from `HIDCommand.title`, and `RemoteButtonTests` fails when they drift.

## Metadata in the bundle

The system finds the actions in `Contents/Resources/Metadata.appintents`. Xcode writes it with `appintentsmetadataprocessor`; neither SwiftPM nor Swift Build runs that for a package, so `package_app.sh` does in `extract_app_intents_metadata`:

- **Inputs.** Swift Build already emits the `.swiftconstvalues` files the processor reads, under `.build/out/Intermediates.noindex/Clicker.build/<Debug|Release>/ClickerApp-t.build/Objects-normal/<arch>/`. This is one more reason to stay on Swift Build (see [development.md](development.md#linked-sdk-and-toolchain)). Debug builds keep one file per source and leave a deleted source's file behind, so the script passes only the current sources' files, plus the whole-module `ClickerApp-primary.swiftconstvalues` of a release build. The host's slice is read; the metadata is the same for every architecture.
- **One run, for `ClickerApp`.** The intents live in the library both executables link statically, and one run with `--module-name ClickerApp` produces metadata that `linkd` indexes for the app. Xcode's static-library shape (`--static-metadata-file-list`, `AppIntentsPackage`) is the fallback if the type names it records ever fail to resolve in the executable.
- **Flags.** `--toolchain-dir`, `--sdk-root`, `--xcode-version` (the Xcode build, such as `27A9275`), `--platform-family macOS`, `--deployment-target` and `--target-triple` from the package, and `--no-app-shortcuts-localization`, since there are no phrases.
- **The check.** The processor exits 0 having written nothing when it finds no intents, so the script fails unless `extract.actionsdata` exists and names `PressButtonIntent`. CI packages both flavors, so a broken extraction fails CI.
- **Order.** The metadata is copied in before `xattr -cr` and the final `codesign`, so the app's signature covers it.

## Only team-signed builds run actions

The metadata of an ad-hoc build is indexed like any other, but when the process registers, `linkd` rejects it: "Unable to get teamId" then "Rejecting invalid client due to requiresValidatedBundle". AppKit then logs `Error registering app with intents framework`. A team-signed build is accepted ("Accepting [pid]:com.jakejarvis.Clicker") and logs no error. So test actions on a team-signed build, never an ad-hoc or `--demo` one. To make one, build with a Developer ID identity that the profile lists, and install that copy:

```bash
./script/package_app.sh --sign <SHA-1 of the Developer ID Application certificate>
```

A team-signed build keeps pairings in the keychain, not in the ad-hoc builds' `pairings.json`, so it sees the release build's pairings ([sandbox-and-keychain.md](sandbox-and-keychain.md)). Logic is covered without any of this by `AppIntentsTests`, which run the intents against the demo TVs.

## No Siri phrases

An `AppShortcutsProvider` would add the actions to Siri and to Spotlight's suggestions with spoken phrases. Xcode builds phrase-matching assets for those in a second step, `appintentsnltrainingprocessor`, and a SwiftPM build has no equivalent; without the assets Siri may not match the phrases. Don't add a provider without solving that and checking it with Siri.
