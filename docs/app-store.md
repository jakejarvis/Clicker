# The Mac App Store build

The same app, built without its updater and uploaded to App Store Connect instead of notarized. `script/package_app.sh --app-store` builds it, and the release workflow uploads it on every tag when its secrets are set. Its App Store Connect record is "Clicker - Remote Control" (Apple ID 6824713472), with the same bundle ID as the direct download.

## What differs from the direct download

- **No Sparkle.** Sparkle is a default package trait in `Package.swift`. `--app-store` builds with `--disable-default-traits`, so the `#if Sparkle` code, Sparkle.framework (with `Installer.xpc`), the `Contents/Frameworks` rpath and the `SU*` Info.plist keys are left out rather than switched off: App Review rule 2.4.5(vii) allows no updater besides the store. `UpdateController.isIncluded` is false, so Settings has no Updates section or Check for Updates button; the menus and the update notice hide themselves because `isEnabled` is false and `pendingUpdateVersion` stays nil.
- **Entitlements.** A copy of `Resources/Clicker.entitlements` minus Sparkle's `temporary-exception.mach-lookup` keys, which only its installer needs and which App Review questions. The sandbox, `network.client` and the keychain group are the same.
- **Provisioning profile.** `Resources/Clicker-AppStore.provisionprofile`, a Mac App Store Connect profile listing one Apple Distribution certificate, expiring 2027-10-19.
- **Export compliance.** Its Info.plist sets `ITSAppUsesNonExemptEncryption` to NO, so App Store Connect doesn't ask on every upload. The app's crypto is CryptoKit plus SRP on BigInt; declaring it exempt is the owner's call, not Apple's verdict. If App Store Connect or App Review disputes it, answer its questionnaire and use the key or `ITSEncryptionExportComplianceCode` it gives back.
- **No notarization.** The store re-signs what it distributes, and a store-signed build launches only from TestFlight or the App Store.

Both builds ship `Resources/PrivacyInfo.xcprivacy`, which App Store uploads check. It declares UserDefaults (reason CA92.1), the only required-reason API the code uses; add an entry if code starts using another (file timestamps, system boot time, disk space).

Both builds have one bundle ID, so they share a sandbox container. Signed for real they also share a team and keychain group, so someone switching from one to the other keeps their pairings. An ad-hoc `--app-store` build has no keychain entitlements and uses the file backend, like any ad-hoc build ([sandbox-and-keychain.md](sandbox-and-keychain.md)).

## Building

```bash
script/package_app.sh --app-store
script/package_app.sh --release --universal --app-store --version 1.2.3 --sign <Apple Distribution SHA-1> --installer "3rd Party Mac Developer Installer: Jake Jarvis (B5ZWKBCUTU)"
```

The first is ad hoc and runs locally, which is enough to look at it (`open -n dist/Clicker.app --args --demo settings`). The second signs with Apple Distribution, embeds the profile and wraps the app in `dist/Clicker.pkg` with `productbuild`. `package_app.sh` refuses a signing certificate the profile doesn't list.

- Resolving with the trait off rewrites `Package.resolved` without Sparkle's pin, so the App Store build also passes `--force-resolved-versions`. Don't drop it: a local App Store build would quietly unpin Sparkle in the next commit.
- `package_app.sh` clears every extended attribute from the bundle before signing. A file downloaded in a browser, such as a fresh provisioning profile, carries `com.apple.quarantine`; `cp` copies it into the bundle, and App Store Connect rejects the package for it (error 91109). `com.apple.provenance` stays: the system sets it, it can't be removed, and App Store Connect doesn't reject it.
- Every `package_app.sh` run deletes `dist/Clicker.pkg` first, whatever the flavor, so deliver or copy a signed package before building anything else.

## Build numbers

`CFBundleVersion` is derived from the version (`1.2.3` → `10203`), as for Sparkle. App Store Connect never takes a build number twice, even one that failed processing, so uploading the same version again needs `--build N` (1 to 99, App Store only): `CFBundleVersion` becomes `10203.N`, which sorts after `10203` and before the next version's `10204`. Direct builds never take it, since Sparkle compares the number too. A rejection that needs a code fix ships as a new tag instead.

The version on App Store Connect's version page must match the build's `CFBundleShortVersionString`.

## Uploading

By hand: open Transporter, drag in `dist/Clicker.pkg` and click Deliver. Processing takes 15 to 30 minutes; a failure shows as an issue on the delivery in Transporter and arrives by email.

From the release workflow, when `APP_STORE_P12_BASE64` and `APP_STORE_P12_PASSWORD` are set in the `release` environment (see [releasing.md](releasing.md#secrets)):

- The credentials step imports the Apple Distribution and Mac Installer Distribution identities into the job's keychain with the Developer ID one.
- The last step, "Upload the App Store build", packages at the tag's version and uploads with `xcrun altool --upload-package`, using the API key notarization uses (a Developer-role team key can upload builds). altool finds the key by file name, so the step copies it to `AuthKey_<id>.p8` in a directory named by `API_PRIVATE_KEYS_DIR`.
- It uses the long form of `--upload-package` (`--type macos`, `--apple-id` from `APP_STORE_APPLE_ID` in the workflow, and the bundle ID and versions) with camelCase `--apiKey` and `--apiIssuer`, which is what Xcode 26's altool documents; CI pins Xcode 27.1, whose altool accepts the same form.
- It runs last, so a failure leaves the GitHub release, appcast, cask and site published, and because it replaces `dist/Clicker.app`.
- An `ERROR:` line fails the step even if altool exits 0. On a re-run, an error naming a duplicate (`Redundant Binary Upload`, `has already been used`, `DUPLICATE`) counts as done. A bare "must be higher than the previously uploaded version" fails, since it can mean a later build is there and this version has none.
- Without the secret the step does nothing.

To make the `.p12`: in Keychain Access, under My Certificates, select both "Apple Distribution: Jake Jarvis" and "3rd Party Mac Developer Installer: Jake Jarvis" (each with its key), choose File › Export Items… and set a password. Then:

```bash
base64 -i appstore.p12 | gh secret set APP_STORE_P12_BASE64 --env release
gh secret set APP_STORE_P12_PASSWORD --env release
```

## TestFlight and review

A processed build appears in TestFlight; an internal group with automatic distribution offers it in the TestFlight app on your Mac. Quit a direct-download copy before installing it, since the two share a bundle ID.

Submitting for review is a click in App Store Connect: fill in What's New, choose the build, Add for Review, Submit, with manual release so approval doesn't publish on its own. Don't automate it from the workflow: every tag would go to App Review unattended, and a TestFlight install against a real TV is the check before it.

The listing carries over between versions: screenshots (16:10, such as 2880×1800), description, the homepage as support URL, `https://clicker.jarv.is/privacy` as privacy policy, App Privacy "Data Not Collected", Utilities, 4+. App Review likely has no Apple TV, so the review notes say the app needs one on the same network and attach a short screen recording of pairing and using the remote; `--demo` is compiled out of release builds.

## Renewals

The Apple Distribution and Mac Installer Distribution certificates last a year. When they're renewed, export the `.p12` again for the secret and regenerate the profile, which lists the certificate, into `Resources/Clicker-AppStore.provisionprofile`. The profile itself expires 2027-10-19.
