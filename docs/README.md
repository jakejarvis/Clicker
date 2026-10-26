# Clicker documentation

For contributors. The [README](../README.md) one level up is for people using the app.

Clicker is a native SwiftUI menu bar remote for Apple TV that speaks Apple's Companion protocol directly: no bridge process, no Python, no third-party service.

## Working on the app

- [development.md](development.md): building and running, launch arguments, formatting, logs, demo mode, icons.
- [testing.md](testing.md): unit tests, looking at the panel on screen, recording glitches, testing against a TV, measuring resource usage.
- [releasing.md](releasing.md): cutting a release, secrets, the DMG window, the appcast, Sparkle packaging and update behavior, testing an update locally, Homebrew.
- [app-store.md](app-store.md): the Mac App Store build without Sparkle, its signing, build numbers, uploading by hand or from the release workflow, TestFlight and review.
- [site.md](site.md): the clicker.jarv.is website, its pages and release data, the appcast route and update check counts, and how the homepage's panel shot was made.

## How it works

- [architecture.md](architecture.md): dependencies, code layout, module isolation, where state lives. Start here.
- [protocol.md](protocol.md): discovery, pairing, the session, commands, mute, text input, the connection lifecycle, codec and crypto gotchas.
- [panel.md](panel.md): the status item and custom `NSPanel`, its height animation, keys, the global shortcut, dismissal, first launch, menus.
- [input.md](input.md): buttons and the clickpad, the keyboard and held keys, focus, trackpad swipes, text entry.
- [design.md](design.md): visual rules (metrics, surfaces, glyphs) and the layout of the remote, overlay cards, pickers and Settings.
- [sandbox-and-keychain.md](sandbox-and-keychain.md): where pairings and preferences are stored, signing and the provisioning profile, the App Sandbox and container migration.
- [unverified.md](unverified.md): what is reasoned out but not yet confirmed.

## Conventions for these docs

- Write what is true now. When a change is made, update the fact in place instead of adding a dated note; keep a rejected alternative only as a short "don't, because" so nobody tries it again.
- Don't hard-wrap Markdown: one line per paragraph or list item.
- Put a fact in the one doc where someone changing that code would look, and link to it from elsewhere.
