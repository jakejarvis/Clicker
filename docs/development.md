# Development

Clicker is a SwiftUI menu bar app built with SwiftPM. It needs macOS 15 or later and a Swift 6 toolchain (the package uses tools version 6.2). See [architecture.md](architecture.md) for the code layout before changing anything.

## Build and run

```bash
./script/build_and_run.sh
```

The script kills a running copy, calls `script/package_app.sh` to build with SwiftPM and stage `dist/Clicker.app` (Info.plist from `Resources/`, Sparkle.framework embedded, compiled icon, ad-hoc signature, sandbox entitlements), then launches it. It stages the `ClickerDemo` executable, which is the app as shipped plus `--demo`; see [Demo mode](#demo-mode). Modes:

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

`--demo [scenario]` launches against made-up Living Room, Bedroom and Office TVs: they are "discovered" at once, connect instantly, accept and ignore commands, and take about a second for each pair-setup step. Pairings, the selection and the app lists live in memory, and the Settings name is overridden through the volatile argument domain, so none of that is persisted. Settings' own controls are not faked: changing the name, Invert Swipes, Open at Login or the global shortcut in a demo run changes the real preference. The panel opens by itself half a second after launch, and a second later the scenario's steps run (open a popover, start pairing, enter a code, mute, drop the session), each once the app is ready for it. An unknown scenario name exits with the list of names.

```bash
open -n dist/Clicker.app --args --demo pin
```

Scenarios: `ready` (the default), `asleep`, `typing`, `settings`, `apps` (the Apps picker open), `devices` (the device list open), `pair`, `pin`, `paired`, `offline`, `searching` and `choose`, plus the trouble states `pairingdisabled`, `reset` (stale pairing dropped after a factory reset), `removed` (stale pairing dropped after Clicker was removed from the TV's Remotes and Devices), `pairingfailed` (wrong code), `pairinglocalnetwork` (pair-setup timed out on a denied local network), `savefailed` (the TV accepted the pairing but storage refused it), `connecting`, `connectionfailed`, `localnetwork` (macOS denied Local Network access), `disconnected`, `hdmi` (Mute just failed and is disabled), `update` (a pending update) and `notices` (a failed connection and a pending update, stacked). Every overlay card, inline notice and the pending-update state has one, so check wording on screen there rather than against a TV. `choose` has its paired TVs offline: with any TV online the controller picks one itself, so a Choose card next to online TVs can't happen.

Demo mode is its own executable target, `ClickerDemo`, and the app has no demo code at all. `RemoteController` reaches the outside world only through `RemoteDependencies` (discovery, the Companion session, pair-setup, the credential backend, the remembered settings, the client identity and a few timings), and `ClickerApp.run(in:)` takes an `AppEnvironment` that builds them. The `Clicker` executable passes `.live`; `ClickerDemo` passes `.live` too unless `--demo` is given, and then a `DemoWorld` of fakes. So every scenario reaches its state through the controller's real code: `pairingfailed` enters a code the made-up TV rejects, `reset` fails pair-verify with `identityChanged`, `hdmi` mutes on an output that ignores SetVolume and waits for the confirmation to time out (shortened to half a second), `disconnected` has the TV close the session and holds off the reconnect. A scenario is one `DemoScenario` literal in `DemoScenario.all`: which TVs are online and paired, how Living Room behaves (`DemoTV`), the steps, and any timing it stretches. `package_app.sh --with-demo` stages `ClickerDemo` as `Contents/MacOS/Clicker` (`build_and_run.sh` always passes it); `release.sh` and CI never do, and `--with-demo` refuses to sign, so a published Clicker.app has no demo code and ignores `--demo`. A new card, notice or state should get a scenario, reached by the steps a user would take where possible.

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

The homepage shot is `site/src/assets/panel.png`, a 2x crop of the panel from the black-wallpaper App Store capture (`script/screenshots.sh --appearance dark --out dist/screenshots-black`, then `sips -c 1026 544 --cropOffset 66 1966 dist/screenshots-black/raw/01-ready-dark.png --out site/src/assets/panel.png` with the sandbox off), and the menu bar above it is `site/src/components/MenuBar.astro`, sized and spaced at 1px per point to match that capture (the panel is centred under it for the page, not hung under Clicker's item as on screen). Its Wi-Fi, battery and Control Center glyphs are SF Symbols exported with `npx sf-symbols-svg --size 13 --padding 0` (which reads the SF Pro Text fonts in `/Library/Fonts`); Siri isn't an SF Symbol, so it's drawn by hand. Re-crop when the panel's size changes, since the crop rectangle comes from that capture.
