import Foundation
import Testing

/// The string catalogs as files: every language started in them is finished,
/// and the Info.plist catalog translates what Info.plist actually says.
@Suite struct StringCatalogTests {
    private static let root = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../..")
    private static let catalogs = [
        "Sources/ClickerApp/Resources/Localizable.xcstrings",
        "Resources/InfoPlist.xcstrings",
    ]

    private static func strings(in path: String) throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: root.appending(path: path))
        let catalog = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(catalog["strings"] as? [String: [String: Any]])
    }

    /// Every `stringUnit` state under a localization, plural and device
    /// variations included.
    private static func states(in node: Any) -> [String] {
        guard let dictionary = node as? [String: Any] else { return [] }
        if let unit = dictionary["stringUnit"] as? [String: Any] {
            return [unit["state"] as? String ?? ""]
        }
        return dictionary.values.flatMap(states(in:))
    }

    /// A language with any translation ships, so a key it is missing would
    /// show up in English in the middle of it.
    @Test(arguments: catalogs)
    func everyLanguageIsComplete(_ path: String) throws {
        let strings = try Self.strings(in: path)
        let live = strings.filter { _, entry in
            entry["shouldTranslate"] as? Bool != false && entry["extractionState"] as? String != "stale"
        }
        let languages = Set(
            live.values.flatMap { ($0["localizations"] as? [String: Any])?.keys.map { $0 } ?? [] }
        ).subtracting(["en"])
        for language in languages.sorted() {
            for (key, entry) in live.sorted(by: { $0.key < $1.key }) {
                let localization = (entry["localizations"] as? [String: Any])?[language]
                let states = localization.map(Self.states(in:)) ?? []
                #expect(
                    !states.isEmpty && states.allSatisfy { $0 == "translated" },
                    "\(path): \"\(key)\" is not translated to \(language)")
            }
        }
    }

    /// Translators work from the catalog's English, which must be what
    /// Info.plist shows English speakers.
    @Test func infoPlistCatalogMatchesInfoPlist() throws {
        let data = try Data(contentsOf: Self.root.appending(path: "Resources/Info.plist"))
        let info = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        for (key, entry) in try Self.strings(in: "Resources/InfoPlist.xcstrings") {
            let english = (entry["localizations"] as? [String: Any])?["en"]
            let value = ((english as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
            #expect(value != nil, "InfoPlist.xcstrings has no English for \(key)")
            #expect(value == info[key] as? String, "InfoPlist.xcstrings and Info.plist differ on \(key)")
        }
    }
}
