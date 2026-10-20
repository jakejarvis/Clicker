# Releasing and updates

## Cutting a release

Pushing a `vX.Y.Z` tag runs `.github/workflows/release.yml` on a macOS runner. It lints and tests, then calls `script/release.sh`, which builds a universal app, signs it with the Developer ID certificate and the hardened runtime, notarizes and staples it, and produces `Clicker-X.Y.Z.dmg`, `Clicker-X.Y.Z.zip` and a Sparkle `appcast.xml`. The workflow then:

1. publishes the DMG and zip as a GitHub release;
2. commits the appcast to the `gh-pages` branch, which `https://clicker.jarv.is/appcast.xml` (the app's `SUFeedURL`) rewrites to (`site/vercel.json`);
3. writes the Homebrew cask to `jakejarvis/homebrew-tap`;
4. asks Vercel to redeploy the site, so the homepage's download button and the changelog show the release;
5. when the App Store secrets are set, builds the Mac App Store package and uploads it to App Store Connect, where it lands in TestFlight ([app-store.md](app-store.md#uploading)). Submitting it for review stays manual.

```bash
git tag -a --cleanup=verbatim -F notes.md v1.2.3
git push origin v1.2.3
```

The tag's whole message (`%(contents)`, signature block stripped) becomes the release notes on GitHub and in Sparkle's update window, so write it in Markdown in a file and pass it with `-F`. `--cleanup=verbatim` keeps it as written, since `git tag -m` strips every line that starts with `#`. `release.sh` validates the notes before building and fails on a lightweight tag or an empty message.

The tag is the only version source. `CFBundleVersion` is derived from it (`1.2.3` → `10203`) because Sparkle compares that, so minor and patch numbers stay below 100. The App Store build can add a resubmission number (`10203.1`, see [app-store.md](app-store.md#build-numbers)).

Every publish step is idempotent (a leftover draft is replaced, an unchanged appcast not committed), so a run that failed partway can be re-run from the Actions tab. When the release is already published, the re-run keeps it and regenerates the appcast from the published zip (`gh release download`, then `release.sh --appcast-only`): the zip the re-run built is signed differently, and an appcast describing it would make Sparkle reject the download. On failure the job keeps `dist/release`, notarytool's logs included, as an artifact.

Trust notarytool's verdict. `syspolicy_check distribution` has rejected an app notarytool accepted with a generic "Gatekeeper rejected this file" on macOS 27, while `spctl` accepted it, so `release.sh` only warns on it.

### Secrets

The workflow reads these from the `release` environment, which is restricted to `v*` tags:

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | Developer ID Application certificate and key, `base64 -i cert.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | Password of that `.p12` |
| `ASC_API_KEY_P8` | App Store Connect team API key (Developer role), contents of the `.p8` |
| `ASC_KEY_ID`, `ASC_ISSUER_ID` | That key's ID and issuer |
| `SPARKLE_ED_PRIVATE_KEY` | Sparkle EdDSA key, from `generate_keys -x` |
| `VERCEL_DEPLOY_HOOK_URL` | Optional. A deploy hook from the Vercel project's Git settings; without it the site refreshes on the next push to `main` |
| `HOMEBREW_TAP_TOKEN` | Optional. A fine-grained token with Contents read and write on `jakejarvis/homebrew-tap` only; without it the cask stays at its last version |
| `APP_STORE_P12_BASE64` | Optional. Apple Distribution and Mac Installer Distribution certificates with their keys in one `.p12`, `base64 -i appstore.p12`; without it no App Store build is uploaded ([app-store.md](app-store.md#uploading)) |
| `APP_STORE_P12_PASSWORD` | Password of that `.p12` |

`SUPublicEDKey` in `Resources/Info.plist` must be the public half of `SPARKLE_ED_PRIVATE_KEY`. A mismatch doesn't break the release it ships in, but every later update fails its signature check. To check, compare it with `generate_keys -p` for the key the secret came from, or sign any file with `sign_update --ed-key-file` and the secret and verify it against the plist key with `sign_update --verify`.

### Dry run

With the keychain's certificate and a notarytool profile (`xcrun notarytool store-credentials clicker-notary`):

```bash
NOTARY_PROFILE=clicker-notary NOTES_FILE=notes.md script/release.sh --version 1.2.3 --identity <certificate SHA-1>
```

## The appcast

The appcast accumulates. `release.sh` seeds `generate_appcast`'s directory with `origin/gh-pages:appcast.xml` (or `BASE_APPCAST` for a local run); the tool keeps every item whose zip is absent and adds the new one on top, with `--maximum-versions 0` (otherwise it prunes to three per branch point). Sparkle only needs the newest item to update, but a release that raises the minimum macOS leaves older Macs with nothing unless the previous items are there. Never regenerate the feed from an empty directory.

## Packaging Sparkle

Sparkle 2 comes through SwiftPM. `script/package_app.sh` copies Sparkle.framework from `.build/artifacts/sparkle/...` with `ditto` (CI zips the app with `ditto` too, so the framework's symlinks survive), keeps `Installer.xpc` and drops `Downloader.xpc`, replaces SwiftPM's `.build` and toolchain rpaths with `@executable_path/../Frameworks`, and signs inside out without `--deep`. Sparkle's tools (`generate_keys`, `sign_update`, `generate_appcast`) are in `.build/artifacts/sparkle/Sparkle/bin` after `swift package resolve`.

### Sparkle in the sandbox

A sandboxed app cannot launch Sparkle's installer itself, so Info.plist sets `SUEnableInstallerLauncherService`, `Installer.xpc` stays in the framework (signed first), and the entitlements carry the `-spks` and `-spki` mach-lookup exceptions. `Downloader.xpc` is only for apps without `network.client`.

If an update fails with "An error occurred while connecting to the installer" (`SUSparkleErrorDomain` 4005), check whether launchd registered `org.sparkle-project.InstallerLauncher` in the app's domain: `launchctl print pid/<pid>` lists a sandboxed app's bundled services, and the launchd log shows `failed lookup ... error = 3`. Bundled XPC services seem to be cached per bundle path for the login session, so a path that last held a build without `Installer.xpc` (any 0.2.x) can fail this way until a reboot; `lsregister`, touching or renaming the bundle don't help. A user updating 0.2.x to 0.3.0 and then trying the next update without restarting may see it once.

## Updates in the app

- Ad-hoc builds remove `SUFeedURL`, so `UpdateController.isEnabled` is false and the updater never starts; Settings says updates are off.
- The Mac App Store build has no Sparkle at all, and Settings has no Updates section ([app-store.md](app-store.md)).
- Updates are alert-only: `SUAllowsAutomaticUpdates` is false in Info.plist, which hides Sparkle's "automatically download and install" checkbox and overrides any stored preference. Settings offers only Check Automatically.
- Gentle reminders, which an accessory app needs: a background find always just sets `pendingUpdateVersion`, which shows an inline notice under the remote with an Update button and turns both menus' item into Update to X…. Sparkle's alert only comes from a click on Update or Check for Updates…, never on its own, since right after launch (at login, with Open at Login) it would land in front of whatever the user was doing.
- While a Sparkle window is up, the app switches to `.regular` and hides the panel, then restores the launch activation policy.

## Testing an update locally

No notarization needed. Package the newer version and build a feed for it (it signs with the EdDSA key in the login keychain):

```bash
script/package_app.sh --sign <SHA-1> --version 0.2.0
ditto -c -k --sequesterRsrc --keepParent dist/Clicker.app feed/Clicker-0.2.0.zip
generate_appcast --download-url-prefix http://localhost:8765/ -o feed/appcast.xml feed
```

Then package the older version and point it at the feed by editing its `Info.plist` (Sparkle 2 ignores a `-SUFeedURL` launch argument): `plutil -replace SUFeedURL -string http://localhost:8765/appcast.xml` and `plutil -insert NSAppTransportSecurity -json '{"NSAllowsLocalNetworking": true}'`, then re-run the final `codesign` line from `package_app.sh`. Install it, serve the feed with `python3 -m http.server 8765 --bind 127.0.0.1` and use Check for Updates…. The signing certificate must be the one the provisioning profile lists.

## Homebrew

`brew install --cask jakejarvis/tap/clicker`, from the `jakejarvis/homebrew-tap` repository. Its `Casks/clicker.rb` installs the release DMG, says `auto_updates` (Sparkle owns updates, so `brew upgrade` skips it without `--greedy`, and Homebrew installs update anyway) and has a Sparkle livecheck on the appcast's `shortVersionString` (`sparkle:version` is the derived build number).

The whole cask is inlined in the release workflow's "Bump the Homebrew cask" step, which writes it to the tap with the version and the published DMG's digest. Edit the cask there, so a change (new `zap` paths, say) ships with the release that needs it; edits made in the tap are overwritten. `brew audit --new` fails only on GitHub notability, a rule for homebrew/cask submissions, not taps; `brew audit --cask --online` passes.
