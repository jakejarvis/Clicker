# Contributing

Clicker is a SwiftUI menu bar app built with SwiftPM. It requires macOS 15 or later and a Swift 6 toolchain. [docs/how-it-works.md](docs/how-it-works.md) explains the code layout and the protocol; [AGENTS.md](AGENTS.md) records design rules and dead ends already explored.

## Build and run

```bash
./script/build_and_run.sh
```

The script kills a running copy and calls `script/package_app.sh`, which builds with SwiftPM, stages `dist/Clicker.app` from `Resources/Info.plist` with Sparkle.framework embedded, and ad-hoc signs it; then it launches the app. Ad-hoc builds leave out the feed URL, so they never update themselves. Other modes:

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

Launching the binary with `--regular` shows a Dock icon, which some tooling needs in order to see the process.

Code is formatted with the toolchain's `swift-format` (configured in `.swift-format`); CI runs the lint:

```bash
swift format --in-place --recursive --parallel Sources Tests Package.swift
swift format lint --strict --recursive --parallel Sources Tests Package.swift
```

### Pairing storage in development builds

Signed release builds keep pairing credentials in the data protection keychain (one "Clicker: <TV name>" item per Apple TV). Ad-hoc signed development builds cannot use it and keep an owner-only file at `~/Library/Application Support/Clicker/pairings.json` instead. The two are not migrated, so a development build after a release build looks unpaired.

## Demo mode and screenshots

`--demo [scenario]` launches with made-up Apple TVs and opens the panel by itself. Nothing touches the network, and saved pairings and settings are left alone. Scenarios: `ready` (the default), `asleep`, `typing`, `settings`, `pair`, `pin`, `paired`, `offline`, `searching` and `choose`.

```bash
open -n dist/Clicker.app --args --demo pin
```

`script/screenshots.sh <VM>` captures every scenario in light and dark mode in a [VMPal](https://vmpal.com) macOS VM, so the menu bar and wallpaper are stock: lossless PNGs at the guest's native resolution with the clock set to 9:41, in `dist/screenshots`. `--install` builds a release copy and installs it in the VM first. The VM needs agent control and administrator commands approved in its Settings › AI Agents, and Screen Recording allowed for VMPal Tools inside it.

## Releasing

Pushing a `vX.Y.Z` tag runs `.github/workflows/release.yml` on a macOS runner. It calls `script/release.sh`, which builds a universal app, signs it with the Developer ID certificate and the hardened runtime, notarizes and staples it, and produces `Clicker-X.Y.Z.dmg`, `Clicker-X.Y.Z.zip` and a Sparkle `appcast.xml`. The workflow publishes the DMG and zip as a GitHub release, then commits the appcast to the `gh-pages` branch. `https://clicker.jarv.is/appcast.xml` (the app's `SUFeedURL`) is a Vercel rewrite to that file (`site/vercel.json`).

```bash
git tag -a v1.2.3 -m "Release notes in Markdown"
git push origin v1.2.3
```

The tag message becomes the release notes on GitHub and in Sparkle's update window. `CFBundleVersion` is derived from the version (`1.2.3` → `10203`), so minor and patch numbers stay below 100.

The workflow reads these from the `release` environment (restricted to `v*` tags):

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | Developer ID Application certificate and key, `base64 -i cert.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | Password of that `.p12` |
| `ASC_API_KEY_P8` | App Store Connect team API key (Developer role), contents of the `.p8` |
| `ASC_KEY_ID`, `ASC_ISSUER_ID` | That key's ID and issuer |
| `SPARKLE_ED_PRIVATE_KEY` | Sparkle EdDSA key, from `generate_keys -x` |

To dry-run a release locally with the keychain's certificate and a notarytool profile (`xcrun notarytool store-credentials clicker-notary`):

```bash
NOTARY_PROFILE=clicker-notary NOTES_FILE=notes.md \
  script/release.sh --version 1.2.3 --identity <certificate SHA-1>
```

Sparkle's tools (`generate_keys`, `sign_update`, `generate_appcast`) are in `.build/artifacts/sparkle/Sparkle/bin` after `swift package resolve`. To test an update end to end, build two versions with `DOWNLOAD_URL_PREFIX=http://localhost:8000/`, serve the newer one's `dist/release` with `python3 -m http.server 8000`, install the older one and launch it with `--args -SUFeedURL http://localhost:8000/appcast.xml`.
