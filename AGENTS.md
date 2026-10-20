# AGENTS.md

Clicker is a native SwiftUI menu bar remote for Apple TV (macOS 15+, no Dock icon, no main window). It speaks Apple's Companion protocol directly: Bonjour discovery, HomeKit-style pairing, an encrypted session, HID buttons, touch, apps, power, volume and text input. No bridge process, no Python. When in doubt about a wire format, read pyatv's Companion implementation rather than guessing.

The docs in [docs/](docs/README.md) record what the code does on purpose and the dead ends already explored. Read the one for the area you're changing before you change it:

| Changing | Read |
|---|---|
| Anything, first time here | [docs/architecture.md](docs/architecture.md): layout, module isolation, where state lives |
| Building, running, logs, demo mode | [docs/development.md](docs/development.md) |
| Verifying a change, screen captures, measuring | [docs/testing.md](docs/testing.md) |
| `ClickerCompanion`, discovery, connecting, pairing | [docs/protocol.md](docs/protocol.md) |
| The status item, the `NSPanel`, its keys and menus | [docs/panel.md](docs/panel.md) |
| Buttons, keyboard, focus, trackpad swipes, text | [docs/input.md](docs/input.md) |
| How anything looks | [docs/design.md](docs/design.md) |
| Credentials, entitlements, signing, the sandbox | [docs/sandbox-and-keychain.md](docs/sandbox-and-keychain.md) |
| Releases, Sparkle, Homebrew | [docs/releasing.md](docs/releasing.md) |
| Something nobody has confirmed yet | [docs/unverified.md](docs/unverified.md) |

## Rules that apply everywhere

- Run `swift build`, `swift test`, the scripts and `/usr/bin/log show` outside the sandbox: SwiftPM fails inside it, and `log show` silently prints nothing.
- Build, run and look at the real panel before claiming a UI change works (`./script/build_and_run.sh`, `--demo <scenario>` for any state). Check presses and focus from the `remote` log, not by eye.
- Format with `swift format --in-place --recursive --parallel Sources Tests Package.swift`; CI runs `swift format lint --strict` on the same paths.
- The app target is main-actor by default; `ClickerCompanion` is nonisolated and exposes its API with `package` access. See [docs/architecture.md](docs/architecture.md#modules-and-isolation).
- Keep files named after their primary type, AppKit bridging narrow (in `App/`), and SwiftUI the source of truth for content.
- Give every new overlay card, notice or UI state a `--demo` scenario.
- The README is for users; build, protocol and release details go in `docs/`. When something changes, update the fact where it lives instead of appending a dated note, and move items out of `docs/unverified.md` once confirmed. Don't hard-wrap Markdown.
- Commit messages: imperative summary, a body that explains why, ending with the Co-Authored-By line from the session's attribution reminder.
