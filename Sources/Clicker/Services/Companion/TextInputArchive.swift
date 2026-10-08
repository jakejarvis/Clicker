import Foundation

/// Builds and reads the keyed-archive payloads tvOS's remote text input
/// service (RTI) exchanges inside `_tiStart`, `_tiStarted` and `_tiC`.
///
/// tvOS writes these with `RTIKeyedArchiver`, so the `$archiver` field is
/// swapped on the way in and out; the object graph itself is a plain
/// `NSKeyedArchiver` archive.
enum TextInputArchive {
    struct Session: Hashable, Sendable {
        let sessionUUID: UUID
        /// Text already in the focused field on the TV.
        let currentText: String
    }

    private static let remoteArchiverName = "RTIKeyedArchiver"
    private static let foundationArchiverName = "NSKeyedArchiver"

    // MARK: - Reading

    /// Extracts the session identifier and current text from a `_tiD` payload.
    ///
    /// The archive is walked by hand following keyed-archiver UIDs, mirroring
    /// pyatv, so decoding never depends on tvOS-private classes being resolvable.
    static func session(from archive: Data) -> Session? {
        guard let plist = try? PropertyListSerialization.propertyList(from: archive, format: nil) as? [String: Any],
            let objects = plist["$objects"] as? [Any],
            let top = plist["$top"] as? [String: Any]
        else { return nil }

        let graph = ArchiveGraph(objects: objects)
        // tvOS 26 archives the session as an NSUUID; tvOS 27 (measured on
        // 27.0, 2026-10) stores the 16 raw bytes as NSData instead.
        let uuidBytes: Data?
        switch graph.resolve(top["sessionUUID"]) {
        case let data as Data: uuidBytes = data
        case let object as [String: Any]: uuidBytes = object["NS.uuidbytes"] as? Data
        default: uuidBytes = nil
        }
        guard let uuidBytes, uuidBytes.count == 16 else { return nil }
        let uuid = uuidBytes.withUnsafeBytes { UUID(uuid: $0.load(as: uuid_t.self)) }

        var text = ""
        if let documentState = graph.resolve(top["documentState"]) as? [String: Any],
            let docState = graph.resolve(documentState["docSt"]) as? [String: Any],
            let context = graph.resolve(docState["contextBeforeInput"]) as? String
        {
            text = context
        }
        return Session(sessionUUID: uuid, currentText: text)
    }

    private struct ArchiveGraph {
        let objects: [Any]

        /// Follows a UID reference into `$objects`; passes other values through.
        func resolve(_ value: Any?) -> Any? {
            guard let value else { return nil }
            guard let index = Self.uidValue(value) else { return value }
            guard objects.indices.contains(index) else { return nil }
            let object = objects[index]
            if let string = object as? String, string == "$null" { return nil }
            return object
        }

        /// `CFKeyedArchiverUID` has no public accessor, but its description is
        /// stable: `<CFKeyedArchiverUID 0x…>{value = 12}`.
        static func uidValue(_ value: Any) -> Int? {
            let description = String(describing: value)
            guard description.hasPrefix("<CFKeyedArchiverUID"),
                let range = description.range(of: "{value = ")
            else { return nil }
            let digits = description[range.upperBound...].prefix { $0.isNumber }
            return Int(digits)
        }
    }

    // MARK: - Writing

    /// Payload that inserts `text` at the cursor in the TV's focused field.
    static func insertTextPayload(sessionUUID: UUID, text: String) -> Data {
        let output = KeyboardOutput(insertionText: text)
        return encode(TextOperations(sessionUUID: sessionUUID, keyboardOutput: output, textToAssert: nil))
    }

    /// Payload that clears the TV's focused field.
    static func clearTextPayload(sessionUUID: UUID) -> Data {
        let output = KeyboardOutput(insertionText: nil)
        return encode(TextOperations(sessionUUID: sessionUUID, keyboardOutput: output, textToAssert: ""))
    }

    /// Payload that replaces the field's contents with `text` in one
    /// operation: the empty assertion clears the field and the keyboard output
    /// is applied to the result, so a backspace is a single `_tiC` event
    /// rather than a clear followed by an insert.
    static func replaceTextPayload(sessionUUID: UUID, text: String) -> Data {
        let output = KeyboardOutput(insertionText: text)
        return encode(TextOperations(sessionUUID: sessionUUID, keyboardOutput: output, textToAssert: ""))
    }

    private static func encode(_ operations: TextOperations) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.outputFormat = .binary
        archiver.setClassName("RTITextOperations", for: TextOperations.self)
        archiver.setClassName("TIKeyboardOutput", for: KeyboardOutput.self)
        archiver.encode(operations, forKey: "textOperations")
        archiver.finishEncoding()
        let data = archiver.encodedData
        return replacingArchiverName(in: data, with: remoteArchiverName) ?? data
    }

    /// Rewrites `$archiver` (and fills in `$classes` where the archiver left it
    /// out) while preserving keyed-archiver UIDs, which
    /// `PropertyListSerialization` round-trips intact.
    private static func replacingArchiverName(in archive: Data, with name: String) -> Data? {
        guard
            let plist = try? PropertyListSerialization.propertyList(
                from: archive, options: [.mutableContainers], format: nil),
            let dictionary = plist as? NSMutableDictionary
        else { return nil }
        dictionary["$archiver"] = name
        if let objects = dictionary["$objects"] as? NSMutableArray {
            for case let object as NSMutableDictionary in objects {
                if let className = object["$classname"] as? String, object["$classes"] == nil {
                    object["$classes"] = [className, "NSObject"]
                }
            }
        }
        return try? PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
    }
}

// MARK: - Archive object graph

@objc(ClickerRTITextOperations)
private final class TextOperations: NSObject, NSCoding {
    let sessionUUID: UUID
    let keyboardOutput: KeyboardOutput
    let textToAssert: String?

    init(sessionUUID: UUID, keyboardOutput: KeyboardOutput, textToAssert: String?) {
        self.sessionUUID = sessionUUID
        self.keyboardOutput = keyboardOutput
        self.textToAssert = textToAssert
    }

    required init?(coder: NSCoder) {
        guard let uuid = coder.decodeObject(forKey: "targetSessionUUID") as? UUID,
            let output = coder.decodeObject(forKey: "keyboardOutput") as? KeyboardOutput
        else { return nil }
        sessionUUID = uuid
        keyboardOutput = output
        textToAssert = coder.decodeObject(forKey: "textToAssert") as? String
    }

    func encode(with coder: NSCoder) {
        coder.encode(sessionUUID as NSUUID, forKey: "targetSessionUUID")
        coder.encode(keyboardOutput, forKey: "keyboardOutput")
        if let textToAssert {
            coder.encode(textToAssert as NSString, forKey: "textToAssert")
        }
    }
}

@objc(ClickerTIKeyboardOutput)
private final class KeyboardOutput: NSObject, NSCoding {
    let insertionText: String?

    init(insertionText: String?) {
        self.insertionText = insertionText
    }

    required init?(coder: NSCoder) {
        insertionText = coder.decodeObject(forKey: "insertionText") as? String
    }

    func encode(with coder: NSCoder) {
        if let insertionText {
            coder.encode(insertionText as NSString, forKey: "insertionText")
        }
    }
}
