# Development

Clicker is a SwiftUI menu bar app built with SwiftPM. It needs macOS 15 or later and a Swift 6 toolchain (the package uses tools version 6.2). See [architecture.md](architecture.md) for the code layout before changing anything.

## Build and run

```bash
./script/build_and_run.sh
```

The script kills a running copy, calls `script/package_app.sh` to build with SwiftPM and stage `dist/Clicker.app` (Info.plist from `Resources/`, Sparkle.framework embedded, compiled icon, ad-hoc signature, sandbox entitlements), then launches it. It always compiles the `--demo` scenarios in. Modes:

```bash
./script/build_and_run.sh --install    # copy to /Applications and launch from there
./script/build_and_run.sh --release    # optimized build; SRP pairing math is much faster
./script/build_and_run.sh --telemetry  # launch and stream com.jakejarvis.Clicker logs
./script/build_and_run.sh --logs       # launch and stream every log line from the process
./script/build_and_run.sh --verify     # launch and confirm the process exists
./script/build_and_run.sh --debug      # run under lldb
swift test
```

Launch arguments the app understands:

- `--regular` shows a Dock icon (the app is normally an accessory), which some tooling needs to see the process.
- `--demo [scenario]` runs against made-up Apple TVs; see [Demo mode](#demo-mode).

Ad-hoc builds leave out `SUFeedURL`, so they never update themselves and Settings says updates are off. `script/package_app.sh --app-store` builds the Mac App Store version instead, without Sparkle; see [app-store.md](app-store.md).

### Building inside a sandboxed shell

`swift build` fails in a sandboxed agent shell (the module cache, and git cloning the dependencies), so run SwiftPM and the scripts outside the sandbox. `log show` inside the sandbox prints nothing at all, with no error, so read logs outside it too; an empty log read inside the sandbox means nothing.

### Linked SDK and toolchain

AppKit and SwiftUI pick some looks and behaviors by the SDK a binary records in `LC_BUILD_VERSION` (the shortcut recorder's bezel was one; see [panel.md](panel.md#global-shortcut)), so a build that records a different SDK from the shipped one looks different. Two rules keep local builds identical to releases:

- `package_app.sh` passes `-platform_version macos <deployment target> <SDK>` to the linker and fails if any slice records an SDK other than `xcrun --show-sdk-version`. Swift Build, SwiftPM 6.4's default, records the deployment target (`sdk 15.0`) whatever SDK it compiles against. Don't switch to `--build-system native` instead: it is deprecated in 6.4, and universal builds go through Swift Build anyway. The deployment target is read from `Package.swift`, so raising it there is enough. Plain `swift build` and `swift test` don't get the flag, which is fine for tests but not for judging how anything looks.
- CI and `release.yml` run on the `xcode-27` runner image with `DEVELOPER_DIR` pinned to the same Xcode as local development (27.1). When updating Xcode locally, move both workflows' `DEVELOPER_DIR` with it.

Linking the newest SDK doesn't narrow compatibility: the deployment target (`.macOS(.v15)`, `minos 15.0`) decides where the app runs, and macOS 15 draws it with its own 15-era looks whatever SDK it was linked against. Check anything version-dependent on a macOS 15 machine or VM, and keep newer APIs behind `#available`.

## Formatting

The toolchain's `swift-format`, configured in `.swift-format` (4 spaces, 120 columns). `AlwaysUseLowerCamelCase` is off so the SRP code can keep RFC 5054 names (`N`, `A`, `B`, `M1`). When the formatter's wrapping reads badly, restructure the code (a local `let`) rather than fighting it. CI runs the lint:

```bash
swift format --in-place --recursive --parallel Sources Tests Package.swift
swift format lint --strict --recursive --parallel Sources Tests Package.swift
```

Markdown files are not hard-wrapped: one line per paragraph or list item.

## Logs

Subsystem `com.jakejarvis.Clicker`, categories `connection`, `pairing`, `discovery`, `remote` (every HID press and release at info level), `storage` and `updates`. Sparkle logs under `org.sparkle-project.Sparkle`. Debug-level messages are not persisted, so log at info anything you want to read back.

```bash
/usr/bin/log show --last 5m --info --predicate 'subsystem == "com.jakejarvis.Clicker"'
```

Use the full path: zsh has a `log` builtin that swallows the arguments.

## Demo mode

`--demo [scenario]` launches with fake Living Room, Bedroom and Office TVs, in-memory pairings, an instant "connection", commands that go nowhere and pairing that accepts any code. The panel opens by itself half a second after launch, and the Settings name is overridden through the volatile argument domain, so nothing is persisted. The one exception is the global shortcut: recording one in the demo's Settings writes the real preference.

```bash
open -n dist/Clicker.app --args --demo pin
```

Scenarios: `ready` (the default), `asleep`, `typing`, `settings`, `apps` (the Apps picker open), `devices` (the device list open), `pair`, `pin`, `paired`, `offline`, `searching` and `choose`, plus the trouble states `pairingdisabled`, `reset` (stale pairing dropped after a factory reset), `removed` (stale pairing dropped after Clicker was removed from the TV's Remotes and Devices), `pairingfailed` (wrong code), `savefailed` (the TV accepted the pairing but storage refused it), `connecting`, `connectionfailed`, `disconnected`, `hdmi` (Mute just failed and is disabled), `update` (a pending update) and `notices` (a failed connection and a pending update, stacked). Every overlay card, inline notice and the pending-update state has one, so check wording on screen there rather than against a TV.

Demo mode is compiled only under the `DEMO` condition. `Package.swift` defines it for debug builds (so `swift test` sees it), `package_app.sh --release --with-demo` adds it to a release build (`build_and_run.sh` always passes `--with-demo`), and `release.sh` and CI's package step never do, so a published Clicker.app has no `DemoScenario`, no `RemoteController.demo` and ignores `--demo`. In code, `RemoteController.isDemo` is the always-present check (`false` in release); anything that reads the scenario itself goes in `#if DEMO`, and the demo-only controller methods live in the `#if DEMO` extension at the end of `RemoteController.swift`. A new card, notice or state should get a scenario.

## Pairing storage in development builds

Signed release builds keep pairings in the data protection keychain; ad-hoc builds and `swift test` cannot, and use a `pairings.json` file instead. The two are not migrated, so a development build after a release build looks unpaired. Where the file lives, and why, is in [sandbox-and-keychain.md](sandbox-and-keychain.md).

## Icons

The app icon is `Resources/AppIcon.icon`, an Icon Composer document: `icon.json` plus the SVG layers in `Assets/`. Open it in Icon Composer to adjust the glass, or edit the SVGs. `package_app.sh` compiles it with `actool` into `Assets.car` (the Liquid Glass icon macOS 26 and later render live, with dark, clear and tinted variants) and an `AppIcon.icns` fallback for macOS 15.

```bash
./script/render_icon.sh                # render every appearance with ictool and refresh the site's icon PNGs
swift script/make_status_icons.swift   # regenerate the menu bar PDFs from Resources/StatusIcon/*.svg
```

## Website

`site/` is the Astro site for clicker.jarv.is, deployed on Vercel and fully static. The homepage's download button (newest release's DMG) and `/changelog` are built from the GitHub releases API at deploy time (an optional `GITHUB_TOKEN` build variable raises the rate limit), and `site/vercel.json` rewrites `/appcast.xml` to the `gh-pages` branch. Keep it static: a server-rendered version once crashed on cold start (the Astro adapter's build-time import got bundled into the function), which turned every non-prerendered path, 404s included, into a 500.
