# Localization

Clicker ships in English only, but every user-facing string goes through a String Catalog, so adding a language means translating catalogs, not changing code. Two catalogs:

- `Sources/ClickerApp/Resources/Localizable.xcstrings`: the app's strings, plus the error messages `ClickerCompanion` shows in the UI (`CompanionError`, `TLV8.ErrorCode`, the pairing failures). The demo target's strings are made up and stay out.
- `Resources/InfoPlist.xcstrings`: Info.plist values macOS shows, which is only `NSLocalNetworkUsageDescription` (the Local Network prompt). Its English must match `Resources/Info.plist`; `StringCatalogTests` checks that.

English is the source language and the keys are the English text, so an English string needs nothing in the catalog beyond its key.

## Writing strings

SwiftUI localizes a string literal it receives as a `LocalizedStringKey`: `Text`, `Button`, `Toggle`, `.help`, `.accessibilityLabel`, `.alert`, and our own views that take one (`SettingsSection`, `SettingsRow`, `PanelNavigationBar`, `CardTitle`, `CardCaption`, `InlineNotice.Action`). A `String` value is shown as it is. So:

- Anything built as a `String` uses `String(localized:)`: menu item titles, `HIDCommand.title`, `PowerState.title`, controller messages such as `selectedStateDescription`, error descriptions, AppKit placeholders, VoiceOver labels assembled in code. It reads the main bundle, which works from `ClickerCompanion` too.
- A `let` holding a choice of literals is a `String` unless annotated: write `let help: LocalizedStringKey = canType ? "…" : "…"`, as `MenuBarView.keyboardButton` does.
- Text that must not be translated, or is already localized, uses `Text(verbatim:)`: TV and app names, separators, an error's `localizedDescription`. `CardCaption(verbatim:)` follows the same rule.
- Don't give a view both an `init(_ key: LocalizedStringKey)` and a generic `init<S: StringProtocol>(_: S)`: a literal picks the generic one and is never localized or extracted. Label the string one `verbatim:` instead.
- Interpolate rather than concatenate (`"Pair with \(device.name)"` becomes `Pair with %@`), so a translation can move the name. Counts become `%lld` keys that a translation can give plural variants.
- Add `comment:` where a word is ambiguous out of context (`TV`, `Back`, `Pair`, `Ready`, `Natural`). One key has one translation, so a word used in two senses with two comments ends up with one of them; `xcstringstool` warns when that happens.
- Not localized: logs, `ClickerCompanion`'s protocol-level details (`unexpectedResponse` texts, `MediaControlFlags.descriptions`), the ⌥-click details' values (flags, interfaces, addresses; their labels are localized), Apple product names, "Siri" and "Clicker".

## Keeping the catalog in sync

```bash
script/sync_strings.sh          # add new strings, drop or mark stale the removed ones
script/sync_strings.sh --check  # what CI runs: fail if the catalog is out of date
```

Run it after changing any user-facing string and commit the catalog with the code. Swift Build writes a `.stringsdata` file per source file, listing every literal the compiler typed as `LocalizedStringKey`, `LocalizedStringResource` or `String(localized:)`, with the right format specifiers. The script builds `ClickerApp` and merges those files into the catalog with `xcstringstool sync`, keeping translations. That is what Xcode does on build. A string removed from the code is deleted when it has no translations and marked stale when it has some. If the build layout changes and the script finds no `.stringsdata`, `xcstringstool extract` parses sources without compiling, but it can only guess format specifiers.

## How it ships

SwiftPM compiles `Localizable.xcstrings` into `Clicker_ClickerApp.bundle`, `ClickerApp`'s resource bundle. `Text`, `Button` and `String(localized:)` look in the main bundle, not in `Bundle.module`, so `package_app.sh` copies the bundle's `.lproj` folders into `Contents/Resources` and doesn't ship the bundle. That keeps every call site free of `bundle: .module`. It compiles `InfoPlist.xcstrings` into the same folders with `xcstringstool compile`.

A catalog compiles only its translations: the source language produces no `.lproj`, so today's English-only app has none. English comes from the keys in code and from Info.plist.

`package_app.sh` writes `CFBundleLocalizations`: `en` plus every `.lproj` it copied. Without English listed, a Mac set to English and then German would get German, the only localization macOS could see.

## Adding a language

1. Translate every key in both catalogs, in Xcode's catalog editor or by editing the JSON (`"de" : { "stringUnit" : { "state" : "translated", "value" : "…" } }`). `StringCatalogTests` fails while any language present in a catalog has a key that isn't `translated`, since a partial language shows English halfway through.
2. Use tvOS's own term in that language for the remote's buttons and states, not a fresh translation, so Clicker reads like Apple's Remote. Apple publishes its localization glossaries for this.
3. Prefer languages KeyboardShortcuts already ships, so the shortcut recorder matches the rest of Settings.
4. Look at it with `-AppleLanguages '(de)'` in every `--demo` scenario.

App Store metadata and the website are translated separately ([app-store.md](app-store.md), [site.md](site.md)).

## Checking long and unlocalized text

```bash
./script/build_and_run.sh --install --pseudo
open -n /Applications/Clicker.app --args --demo settings -AppleLanguages '(en-XA)'
```

`--pseudo` (passed through to `package_app.sh`, development builds only) adds an `en-XA` pseudo-language: `script/pseudo_localize.py` makes accented, bracketed copies of both catalogs about 30% longer than English, and the script compiles them into the app. The catalogs in the repository are not touched. `build_and_run.sh --pseudo` launches in `en-XA`; add `-AppleLanguages '(en-XA)'` yourself to a `--demo` launch. In that run:

- Plain English text skipped localization (only "Siri", names and values should stay plain).
- A clipped bracket or a missing `]` is text truncated at German-like lengths.

In `en-XA` the remote, the overlay cards and the notices wrap and fit, and Settings rows that can't fit put their control under the title ([design.md](design.md#settings)).
