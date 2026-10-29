# Unverified and open

What is reasoned out or documented but not yet confirmed. When you confirm one, move the fact to the doc it belongs in and delete it here.

## Against a TV

- The identity-change path (stale credentials dropped, pair card with notice) against a factory-reset TV.
- The pairing-lost path (`CompanionError.pairingLost`) against a TV that had Clicker removed from Remotes and Devices. It is reasoned from HAP pair-verify, where M4 carries error 2 for an unknown controller.
- Whether port knocking on Rescan ever wakes an Apple TV. The Living Room TV has not been seen to drop off Bonjour.
- Caption settings (`_mcc` 12 and 13): payload unknown. The other `_mcc` commands, user accounts and touch work but have no UI.
- Why a long-lived session stops answering `_hidC` (see [protocol.md](protocol.md#connection-lifecycle)), whether the TV still acts on the presses it leaves unanswered, and whether it lets go of a button whose release never comes when the session drops. The lines that would tell a late or mismatched reply from none (`Response without a waiting request`, `Ignoring request from device`) are debug level and not persisted, so stream them with `/usr/bin/log stream --level debug --predicate 'subsystem == "com.jakejarvis.Clicker"'` while it happens.

## In the app

- The first-launch panel open alongside the Local Network prompt: whether the prompt's click closes the panel, and whether that reads badly.
- The macOS 15 vibrancy fallback: the development machine runs macOS 27 and nothing has been run on 15.
- Increase Contrast (System Settings › Accessibility › Display) with the real setting on: the popovers' high-contrast plain appearance and `.rowHighlight`, and the panel's glass and `SurfaceModifier`. The views' own response (full-strength fills and hairlines through `ColorSchemeContrast.faded`, the PIN border) has been looked at through the environment override in [testing.md](testing.md#looking-at-the-panel). Light and dark mode have been.
- Reduce Motion with the setting on: the fades that replace the remote/Settings slide, the cards' scale and the text field's move, the ghosted remote without its blur, presses without the shrink, the pairing check without its bounce. Built from `accessibilityReduceMotion`, which has no override to look at it with.
- Open at Login actually opening the app at the next login. Registration itself works: the toggle from `/Applications/Clicker.app` leaves `sfltool dumpbtm` showing Clicker `[enabled, allowed, notified]`.
- The `check` and `first` feed parameters from a real Sparkle run. `updater(_:mayPerform:)` and `feedParameters(for:sendingSystemProfile:)` are the Swift names of Sparkle's delegate methods as read from its headers, not seen called; after the first release that has them, check that its `update_check` events in PostHog carry a `check` other than `unknown`. When a fresh install sends `first=1` depends on the scheduled-check question below.
- The update notice with a real feed. In short launches against a local feed, Sparkle 2.10 never ran its scheduled check, with or without a backdated `SULastCheckTime`; the cause wasn't chased. The manual path (Check for Updates…, download, signature check, install, relaunch) works.

## The Mac App Store build

- A store-signed build getting through App Store Connect's processing. The first upload failed on the quarantine attribute that `package_app.sh` now clears; confirm the next one passes.
- The release workflow's upload step has not run. Its altool command was checked only against Xcode 27's altool with a fake package, and the wording it treats as a duplicate upload is a guess.
- A TestFlight install against a TV: keychain pairings shared with the direct download, the Local Network prompt, the shortcut, Open at Login, Settings without Updates, and whether installing replaces a direct-download copy in `/Applications`.
- App Review's view of an app that needs an Apple TV, and of the export-compliance exemption.

## The release DMG

- The window on macOS 15, whose shorter title bar the picture's extra 20 pt are meant to cover. Only macOS 27 has shown it.
- `release.sh` building it on the release runner: attaching the writable image has only run locally.

## Under the sandbox

- The global shortcut, Open at Login (`SMAppService`), and the Local Network prompt for a fresh identity. All are documented to work sandboxed.
- The 0.2.x → 0.3.0 container migration when Sparkle, rather than a manual copy, does the install.
- Whether the per-path XPC service cache described in [releasing.md](releasing.md#sparkle-in-the-sandbox) clears on logout or only on reboot.
