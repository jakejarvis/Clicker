# Storage, signing and the sandbox

## Pairing credentials

`CredentialStore` picks a backend at launch, and the `storage` log category says which:

- Signed release builds, Developer ID and Mac App Store alike, use the data protection keychain (the same team and keychain group, so the two share pairings): one generic-password item per TV, service `com.jakejarvis.Clicker.pairing`, account the device UUID, label "Clicker: <TV name>", value the JSON-encoded `PairingCredentials`.
- Ad-hoc builds and CI get no validated entitlements and fall back to an owner-only (0600) `pairings.json` in Application Support. For a packaged ad-hoc app, which is sandboxed, that is `~/Library/Containers/com.jakejarvis.Clicker/Data/Library/Application Support/Clicker/`; for an unsandboxed process such as `swift test`, `~/Library/Application Support/Clicker/`.

There is no migration between the two, so a development build after a release build looks unpaired.

`save` throws when the backend refuses, and leaves the in-memory list as it was, so a TV whose pairing wasn't stored never counts as paired. `submitPIN` turns that into a failed pair card; name updates and re-keys only log.

`security find-generic-password` cannot see data protection items. To check the keychain path, read the storage log and relaunch.

## Why the keychain needs a provisioning profile

- The data protection keychain (`kSecUseDataProtectionKeychain`) never prompts, but macOS honors `keychain-access-groups` and `com.apple.application-identifier` only when a provisioning profile validates them. Without one, secd answers -34018 even though the entitlements are in the signature. An ad-hoc binary carrying them is killed by AMFI ("restricted entitlements"), and a Developer ID binary without a profile is killed with "No matching profile found". The app-groups entitlement alone doesn't help.
- A plain `SecItemCopyMatching` returns "not found" even without validated entitlements, so it can't detect the fallback case. The store reads its own `keychain-access-groups` entitlement through `SecTaskCreateFromSelf` and queries with that `kSecAttrAccessGroup`; -34018 there means "use the file".
- The legacy login keychain needs no profile but ties item ACLs to the code signature, so every ad-hoc rebuild would prompt. Don't go back to it.

## Signing

`script/package_app.sh` embeds `Resources/Clicker.provisionprofile` (a Developer ID profile for `com.jakejarvis.Clicker`) only for real identities, and refuses a real identity without the profile. Every build signs with a copy of `Resources/Clicker.entitlements` (`dist/Clicker.entitlements`) minus what it can't carry: ad-hoc builds drop the three restricted keychain keys and get no profile, and the [Mac App Store build](app-store.md) drops Sparkle's mach-lookup exceptions and embeds `Resources/Clicker-AppStore.provisionprofile` instead.

To try the keychain path locally, `script/package_app.sh --sign <SHA-1>`; notarization isn't needed to run a local build. The keychain holds several Developer ID certificates for the team and the profile lists one. An app signed with another launches nowhere (`open` reports "Launch failed", POSIX 163, and AMFI logs nothing), so pass the SHA-1 of the listed certificate; `package_app.sh` compares the two and refuses a mismatch.

Moving from ad-hoc to Developer ID signing changes the code identity, so the Local Network prompt appears once more and Open at Login may need turning on again.

## App Sandbox

Every build is sandboxed, ad-hoc ones included. `Resources/Clicker.entitlements` holds:

- `app-sandbox`;
- `network.client`, for Bonjour browsing, the Companion TCP session and `PortKnocker`. There is no server entitlement: the TV never connects to us;
- Sparkle's mach-lookup exceptions, `com.jakejarvis.Clicker-spks` and `-spki` as `temporary-exception.mach-lookup.global-name` (see [releasing.md](releasing.md#sparkle-in-the-sandbox)), left out of the Mac App Store build;
- the restricted keychain keys, for real identities only.

Sparkle's service names come from the running bundle ID, so a copy under another bundle ID has those lookups denied unless its entitlements are edited to match. That doesn't matter in practice: an ad-hoc copy has no feed, and a Developer ID copy under another ID wouldn't match the profile, so the update path can only be tested with the real ID.

## Preferences and container migration

User defaults (in the container's `Preferences/com.jakejarvis.Clicker.plist`) hold the client identity (`clientDeviceID`), `favoriteAppIDsByDevice`, `recentAppIDsByDevice`, the shortcut (`KeyboardShortcuts_togglePanel`), `hasCompletedFirstLaunch`, the Invert Swipes setting and Sparkle's state.

Releases before the sandbox kept these, and Application Support, outside any container. `Resources/container-migration.plist` moves `${Library}/Preferences/com.jakejarvis.Clicker.plist` and `${ApplicationSupport}/Clicker` into `~/Library/Containers/com.jakejarvis.Clicker` on the first sandboxed launch. Keeping `clientDeviceID` is what lets existing pairings verify afterwards. Keychain items aren't in the container and need nothing.

The system runs the migration only when it creates the container, so a container left behind by a test build means the real data never moves. Test with another bundle ID (an ad-hoc copy as, say, `com.jakejarvis.Clicker.sandboxtest`, with a manifest pointing at seeded test paths), and check that the originals are gone, the data is in the container, and the log shows no sandbox denials.
