import Foundation
import Testing

@testable import Clicker

@Suite struct TextInputArchiveTests {
    @Test func insertPayloadMatchesRTIShape() throws {
        let uuid = UUID()
        let payload = TextInputArchive.insertTextPayload(sessionUUID: uuid, text: "hello")
        let plist = try PropertyListSerialization.propertyList(from: payload, format: nil) as? [String: Any]
        let dictionary = try #require(plist)
        #expect(dictionary["$archiver"] as? String == "RTIKeyedArchiver")
        #expect(dictionary["$version"] as? Int == 100000)

        let objects = try #require(dictionary["$objects"] as? [Any])
        let classNames = objects.compactMap { ($0 as? [String: Any])?["$classname"] as? String }
        #expect(classNames.contains("RTITextOperations"))
        #expect(classNames.contains("TIKeyboardOutput"))
        #expect(classNames.contains("NSUUID"))
        let classLists = objects.compactMap { ($0 as? [String: Any])?["$classes"] as? [String] }
        #expect(classLists.contains(["RTITextOperations", "NSObject"]))
        #expect(classLists.contains(["TIKeyboardOutput", "NSObject"]))
        #expect(objects.contains { $0 as? String == "hello" })

        let top = try #require(dictionary["$top"] as? [String: Any])
        #expect(top["textOperations"] != nil)
    }

    @Test func clearPayloadAssertsEmptyText() throws {
        let payload = TextInputArchive.clearTextPayload(sessionUUID: UUID())
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: payload, format: nil) as? [String: Any])
        let objects = try #require(plist["$objects"] as? [Any])
        let operations = try #require(objects.compactMap { $0 as? [String: Any] }.first { $0["textToAssert"] != nil })
        #expect(operations["keyboardOutput"] != nil)
        #expect(objects.contains { $0 as? String == "" })
    }

    @Test func replacePayloadAssertsEmptyTextAndInserts() throws {
        let payload = TextInputArchive.replaceTextPayload(sessionUUID: UUID(), text: "hell")
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: payload, format: nil) as? [String: Any])
        let objects = try #require(plist["$objects"] as? [Any])
        let dictionaries = objects.compactMap { $0 as? [String: Any] }
        let operations = try #require(dictionaries.first { $0["textToAssert"] != nil })
        #expect(operations["keyboardOutput"] != nil)
        #expect(dictionaries.contains { $0["insertionText"] != nil })
        #expect(objects.contains { $0 as? String == "" })
        #expect(objects.contains { $0 as? String == "hell" })
    }

    /// Simulates a `_tiD` payload from the TV using the same private class
    /// names tvOS sends, then reads it back.
    @Test func readsSessionFromRemoteArchive() throws {
        let uuid = UUID()
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.outputFormat = .binary
        archiver.setClassName("RTIDocumentState", for: FakeDocumentState.self)
        archiver.setClassName("TIDocumentState", for: FakeDocState.self)
        archiver.encode(uuid as NSUUID, forKey: "sessionUUID")
        archiver.encode(FakeDocumentState(docSt: FakeDocState(contextBeforeInput: "Stranger")), forKey: "documentState")
        archiver.finishEncoding()

        // Mimic RTIKeyedArchiver's archiver name.
        let plist = try #require(
            try PropertyListSerialization.propertyList(
                from: archiver.encodedData, options: [.mutableContainers], format: nil) as? NSMutableDictionary)
        plist["$archiver"] = "RTIKeyedArchiver"
        let payload = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)

        let session = try #require(TextInputArchive.session(from: payload))
        #expect(session.sessionUUID == uuid)
        #expect(session.currentText == "Stranger")
    }

    @Test func readsSessionWithoutDocumentState() throws {
        let uuid = UUID()
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.encode(uuid as NSUUID, forKey: "sessionUUID")
        archiver.finishEncoding()
        let session = try #require(TextInputArchive.session(from: archiver.encodedData))
        #expect(session.sessionUUID == uuid)
        #expect(session.currentText == "")
    }

    /// tvOS 27 archives the session UUID as 16 raw bytes rather than an NSUUID.
    @Test func readsSessionArchivedAsRawBytes() throws {
        let uuid = UUID()
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.encode(withUnsafeBytes(of: uuid.uuid) { Data($0) } as NSData, forKey: "sessionUUID")
        archiver.finishEncoding()
        let session = try #require(TextInputArchive.session(from: archiver.encodedData))
        #expect(session.sessionUUID == uuid)
    }

    @Test func rejectsGarbage() {
        #expect(TextInputArchive.session(from: Data([1, 2, 3])) == nil)
    }
}

@objc(ClickerTestFakeDocumentState)
private final class FakeDocumentState: NSObject, NSCoding {
    let docSt: FakeDocState
    init(docSt: FakeDocState) { self.docSt = docSt }
    required init?(coder: NSCoder) { return nil }
    func encode(with coder: NSCoder) { coder.encode(docSt, forKey: "docSt") }
}

@objc(ClickerTestFakeDocState)
private final class FakeDocState: NSObject, NSCoding {
    let contextBeforeInput: String
    init(contextBeforeInput: String) { self.contextBeforeInput = contextBeforeInput }
    required init?(coder: NSCoder) { return nil }
    func encode(with coder: NSCoder) {
        coder.encode(contextBeforeInput as NSString, forKey: "contextBeforeInput")
        coder.encode("" as NSString, forKey: "contextAfterInput")
    }
}
