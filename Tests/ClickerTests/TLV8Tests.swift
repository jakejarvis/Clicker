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

    @Test func encodesSlicesWithNonZeroStartIndex() throws {
        let backing = Data([9, 9, 9, 1, 2, 3, 4, 5])
        let slice = backing.dropFirst(3)
        #expect(slice.startIndex == 3)
        let encoded = TLV8.encode([(.signature, slice), (.state, Data([1]).dropFirst(0))])
        #expect(encoded == Data([0x0A, 0x05, 1, 2, 3, 4, 5, 0x06, 0x01, 0x01]))

        let longSlice = Data(repeating: 0xAB, count: 10 + 300).dropFirst(10)
        #expect(try TLV8.decode(TLV8.encode([(.encryptedData, longSlice)]))[.encryptedData] == Data(longSlice))
    }

    @Test func reportsErrorCodes() throws {
        let items = try TLV8.decode(TLV8.encode([(.state, Data([0x04])), (.error, Data([0x02]))]))
        #expect(items.errorCode == .authentication)
    }

    @Test func rejectsTruncatedInput() {
        #expect(throws: TLV8Error.truncated) { try TLV8.decode(Data([0x06, 0x05, 0x01])) }
    }
}
