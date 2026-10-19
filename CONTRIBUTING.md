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
./script/build_and_run.sh --native      # SwiftPM's native build system: links the real SDK like CI, so controls look as released
./script/render_icon.sh                 # preview Resources/AppIcon.icon and refresh the site's icon PNGs
swift script/make_status_icons.swift   # regenerate menu bar PDFs from Resources/StatusIcon/*.svg
swift test                              # codec, crypto, SRP and text-input tests
```

The app icon is `Resources/AppIcon.icon`, an Icon Composer document: `icon.json` plus the SVG layers in `Assets/` (a silver remote over dark controls on a graphite gradient). Open it in Icon Composer to adjust the glass, or edit the SVGs directly; `package_app.sh` compiles it with `actool` into `Assets.car` (the Liquid Glass icon macOS 26 and later render live, with the system's dark, clear and tinted variants) and an `AppIcon.icns` fallback for macOS 15. `script/render_icon.sh` renders the document with Icon Composer's `ictool` so you can look at every appearance without installing the app.

Launching the binary with `--regular` shows a Dock icon, which some tooling needs in order to see the process.

Code is formatted with the toolchain's `swift-format` (configured in `.swift-format`); CI runs the lint:

```bash
swift format --in-place --recursive --parallel Sources Tests Package.swift
swift format lint --strict --recursive --parallel Sources Tests Package.swift
```

### Pairing storage in development builds

Signed release builds keep pairing credentials in the data protection keychain (one "Clicker: <TV name>" item per Apple TV). Ad-hoc signed development builds cannot use it and keep an owner-only file at `~/Library/Containers/com.jakejarvis.Clicker/Data/Library/Application Support/Clicker/pairings.json` instead (the app is sandboxed, so Application Support and its preferences live in its container). The two are not migrated, so a development build after a release build looks unpaired.

## Demo mode and screenshots

`--demo [scenario]` launches with made-up Apple TVs and opens the panel by itself. Nothing touches the network, and saved pairings and settings are left alone (except the keyboard shortcut: recording one in the demo's Settings writes the real preference). It exists only in debug builds and in release builds made with `script/package_app.sh --release --with-demo` (the `DEMO` compilation condition; `build_and_run.sh` always passes `--with-demo`, `release.sh` and CI's package step never do), so a published Clicker.app ignores the argument. Scenarios: `ready` (the default), `asleep`, `typing`, `settings`, `pair`, `pin`, `paired`, `offline`, `searching` and `choose`, plus the trouble states `pairingdisabled`, `reset` (stale pairing dropped after a factory reset), `removed` (stale pairing dropped after Clicker was removed from the TV's Remotes and Devices), `pairingfailed` (wrong code), `savefailed` (the TV accepted the pairing but the keychain refused to store it), `connectionfailed`, `disconnected`, `hdmi` (Mute just failed and is disabled), `update` (a pending update: an inline notice under the remote and Update to… menu items) and `notices` (a failed connection and a pending update, stacked).

```bash
open -n dist/Clicker.app --args --demo pin
```

`script/screenshots.sh <VM>` captures every scenario in light and dark mode in a [VMPal](https://vmpal.com) macOS VM, so the menu bar and wallpaper are stock: lossless PNGs at the guest's native resolution with the clock set to 9:41, in `dist/screenshots`. `--install` builds a release copy with the demo scenarios compiled in and installs it in the VM first. The VM needs agent control and administrator commands approved in its Settings › AI Agents, and Screen Recording allowed for VMPal Tools inside it.

## Releasing

Pushing a `vX.Y.Z` tag runs `.github/workflows/release.yml` on a macOS runner. It lints and tests first, then calls `script/release.sh`, which builds a universal app, signs it with the Developer ID certificate and the hardened runtime, notarizes and staples it, and produces `Clicker-X.Y.Z.dmg`, `Clicker-X.Y.Z.zip` and a Sparkle `appcast.xml`. The appcast is the published one from `gh-pages` with the new version added on top, so every release stays listed (Sparkle needs the older items to offer the last compatible version to a Mac the newest one no longer supports; `BASE_APPCAST` overrides the source for a local run). The workflow publishes the DMG and zip as a GitHub release, commits the appcast to the `gh-pages` branch, writes the Homebrew cask (inlined in the workflow, so edit it there) to `jakejarvis/homebrew-tap`, and asks Vercel to redeploy the site so its homepage download button and changelog (both built from the GitHub releases API at deploy time) show the release. `https://clicker.jarv.is/appcast.xml` (the app's `SUFeedURL`) is a Vercel rewrite to that file (`site/vercel.json`). Every publish step is idempotent, so a run that failed partway can be re-run from the Actions tab (a release that is already published is kept, and the appcast is regenerated from its zip with `release.sh --appcast-only`); on failure the job keeps `dist/release` (notarytool's logs included) as an artifact.

```bash
git tag -a --cleanup=verbatim -F notes.md v1.2.3
git push origin v1.2.3
```

The tag message becomes the release notes on GitHub and in Sparkle's update window, so write it in Markdown in a file and pass it with `-F`: `--cleanup=verbatim` keeps it exactly as written, since `git tag -m` otherwise strips every line that starts with `#`. The release fails on a lightweight tag or an empty message. `CFBundleVersion` is derived from the version (`1.2.3` → `10203`), so minor and patch numbers stay below 100.

The workflow reads these from the `release` environment (restricted to `v*` tags):

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | Developer ID Application certificate and key, `base64 -i cert.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | Password of that `.p12` |
| `ASC_API_KEY_P8` | App Store Connect team API key (Developer role), contents of the `.p8` |
| `ASC_KEY_ID`, `ASC_ISSUER_ID` | That key's ID and issuer |
| `SPARKLE_ED_PRIVATE_KEY` | Sparkle EdDSA key, from `generate_keys -x` |
| `VERCEL_DEPLOY_HOOK_URL` | Optional. A deploy hook from the Vercel project's Git settings; without it the download button and changelog refresh on the next push to `main` |
| `HOMEBREW_TAP_TOKEN` | Optional. A fine-grained token with Contents read and write on `jakejarvis/homebrew-tap` only, for writing `Casks/clicker.rb` with the release's DMG; without it the cask stays at its last version (it says `auto_updates`, so Sparkle updates Homebrew installs anyway) |

`SUPublicEDKey` in `Resources/Info.plist` must be the public half of `SPARKLE_ED_PRIVATE_KEY`: a mismatch does not break the first release but makes every later update fail its signature check. Before the first release, compare it with what `generate_keys -p` prints for the key the secret was exported from (or sign any file with `sign_update --ed-key-file` and the secret, then check it against the plist key with `sign_update --verify`).

To dry-run a release locally with the keychain's certificate and a notarytool profile (`xcrun notarytool store-credentials clicker-notary`):

```bash
NOTARY_PROFILE=clicker-notary NOTES_FILE=notes.md \
  script/release.sh --version 1.2.3 --identity <certificate SHA-1>
```

Sparkle's tools (`generate_keys`, `sign_update`, `generate_appcast`) are in `.build/artifacts/sparkle/Sparkle/bin` after `swift package resolve`. To test an update end to end without notarizing, package the newer version with `script/package_app.sh --sign <SHA-1> --version 0.2.0`, zip it (`ditto -c -k --sequesterRsrc --keepParent dist/Clicker.app feed/Clicker-0.2.0.zip`) and run `generate_appcast --download-url-prefix http://localhost:8765/ -o feed/appcast.xml feed` (it signs with the EdDSA key in the login keychain). Then package the older version, point it at the feed (`plutil -replace SUFeedURL -string http://localhost:8765/appcast.xml` and `plutil -insert NSAppTransportSecurity -json '{"NSAllowsLocalNetworking": true}'` on its `Info.plist`, then re-run the final `codesign` line from `package_app.sh`), install it, serve the feed with `python3 -m http.server 8765 --bind 127.0.0.1` and use Check for Updates…. Sparkle 2 ignores a `-SUFeedURL` launch argument, so the plist edit is needed. The signing certificate must be one the provisioning profile lists; `package_app.sh` checks.

### Mac App Store build

`script/package_app.sh --app-store` builds the App Store flavor. SwiftPM's default `Sparkle` trait is turned off (`--disable-default-traits`), so the updater, its UI, Sparkle.framework and the `SU*` Info.plist keys are all left out; the store updates the app and allows no other updater. It is signed with `Resources/Clicker.entitlements` minus Sparkle's mach-lookup exceptions, so it runs in the same sandbox container, with the same keychain group, as the direct download, and someone switching between the two keeps their pairings. Without `--sign` it is ad-hoc signed like any dev build, which is enough to try it locally.

For a submission, put a Mac App Store distribution profile for `com.jakejarvis.Clicker` at `Resources/Clicker-AppStore.provisionprofile` and run:

```bash
script/package_app.sh --release --universal --app-store --version 1.2.3 \
  --sign "Apple Distribution: …" --installer "3rd Party Mac Developer Installer: …"
```

That writes `dist/Clicker.pkg`, which is uploaded with Transporter. An App Store-signed app does not launch outside the store. App Review will likely have no Apple TV, so attach a short screen recording of pairing and using the remote to the review notes; `--demo` is compiled out of release builds.
