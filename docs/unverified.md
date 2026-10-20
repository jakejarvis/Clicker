# Unverified and open

What is reasoned out or documented but not yet confirmed. When you confirm one, move the fact to the doc it belongs in and delete it here.

## Against a TV

- Held keys: whether tvOS auto-repeats a direction held over `_hidC` (as it does for the Siri Remote's clickpad), and how a held Return or Delete behaves. Before keys were held, holds only ever came from the on-screen buttons (Siri).
- Trackpad swipes: the direction sign (a downward two-finger scroll must move Home Screen focus down, with Natural scrolling on and off) and `TrackpadSwipe.gain` (one tile per slow swipe, several per flick, no runaway in a long list). Tune the constant there.
- The identity-change path (stale credentials dropped, pair card with notice) against a factory-reset TV.
- The pairing-lost path (`CompanionError.pairingLost`) against a TV that had Clicker removed from Remotes and Devices. It is reasoned from HAP pair-verify, where M4 carries error 2 for an unknown controller.
- Whether port knocking on Rescan ever wakes an Apple TV. The Living Room TV has not been seen to drop off Bonjour.
- Caption settings (`_mcc` 12 and 13): payload unknown. The other `_mcc` commands, user accounts and touch work but have no UI.

## In the app

- The first-launch panel open alongside the Local Network prompt: whether the prompt's click closes the panel, and whether that reads badly.
- The macOS 15 vibrancy fallback: the development machine runs macOS 27 and nothing has been run on 15.
- Open at Login actually opening the app at the next login. Registration itself works: the toggle from `/Applications/Clicker.app` leaves `sfltool dumpbtm` showing Clicker `[enabled, allowed, notified]`.
- The update notice with a real feed. In short launches against a local feed, Sparkle 2.10 never ran its scheduled check, with or without a backdated `SULastCheckTime`; the cause wasn't chased. The manual path (Check for Updates…, download, signature check, install, relaunch) works.

## Under the sandbox

- The global shortcut, Open at Login (`SMAppService`), and the Local Network prompt for a fresh identity. All are documented to work sandboxed.
- The 0.2.x → 0.3.0 container migration when Sparkle, rather than a manual copy, does the install.
- Whether the per-path XPC service cache described in [releasing.md](releasing.md#sparkle-in-the-sandbox) clears on logout or only on reboot.
