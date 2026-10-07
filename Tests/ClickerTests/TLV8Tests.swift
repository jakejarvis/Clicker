import Foundation
import Testing
@testable import Clicker

@Suite struct TLV8Tests {
    @Test func encodesAndDecodes() throws {
        let encoded = TLV8.encode([(.state, Data([0x01])), (.publicKey, Data([1, 2, 3]))])
        #expect(encoded == Data([0x06, 0x01, 0x01, 0x03, 0x03, 0x01, 0x02, 0x03]))
        let items = try TLV8.decode(encoded)
        #expect(items[.state] == Data([0x01]))
        #expect(items[.publicKey] == Data([1, 2, 3]))
        #expect(items[.salt] == nil)
    }

    @Test func splitsAndJoinsLongValues() throws {
        let value = Data((0..<600).map { UInt8($0 % 251) })
        let encoded = TLV8.encode([(.encryptedData, value)])
        #expect(encoded.count == 600 + 3 * 2)
        let items = try TLV8.decode(encoded)
        #expect(items[.encryptedData] == value)
    }

    @Test func reportsErrorCodes() throws {
        let items = try TLV8.decode(TLV8.encode([(.state, Data([0x04])), (.error, Data([0x02]))]))
        #expect(items.errorCode == .authentication)
    }

    @Test func rejectsTruncatedInput() {
        #expect(throws: TLV8Error.truncated) { try TLV8.decode(Data([0x06, 0x05, 0x01])) }
    }
}
