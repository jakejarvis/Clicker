import Foundation
import Testing

@testable import Clicker

@Suite struct OPACKTests {
    @Test func roundTripsScalars() throws {
        let values: [OPACKValue] = [
            .null, .bool(true), .bool(false), .int(0), .int(0x27), .int(0x28), .int(0xFF), .int(0x100),
            .int(0x1_0000), .int(0x1_0000_0000), .int(-5), .double(3.25), .string(""), .string("hello"),
            .string(String(repeating: "x", count: 40)), .string(String(repeating: "y", count: 300)),
            .data(Data()), .data(Data(repeating: 7, count: 33)), .data(Data(repeating: 1, count: 70_000)),
            .uuid(UUID()), .date(123.5),
        ]
        for value in values {
            let decoded = try OPACK.decode(OPACK.encode(value))
            #expect(decoded == value, "\(value)")
        }
    }

    @Test func roundTripsContainers() throws {
        let message: OPACKValue = [
            "_i": "_hidC",
            "_t": 2,
            "_x": 1234,
            "_c": ["_hBtS": 1, "_hidC": 6],
            "list": [1, "two", 3.0, true, .null],
            "big": .array((0..<20).map { OPACKValue.int(Int64($0)) }),
        ]
        var wide: [String: OPACKValue] = [:]
        for index in 0..<20 { wide["key\(index)"] = .string("value\(index)") }

        #expect(try OPACK.decode(OPACK.encode(message)) == message)
        #expect(try OPACK.decode(OPACK.encode(.dictionary(wide))) == .dictionary(wide))
    }

    @Test func matchesKnownEncodings() {
        #expect(OPACK.encode(.int(5)) == Data([0x0D]))
        #expect(OPACK.encode(.int(0x30)) == Data([0x30, 0x30]))
        #expect(OPACK.encode(.string("ab")) == Data([0x42, 0x61, 0x62]))
        #expect(OPACK.encode(.data(Data([1, 2]))) == Data([0x72, 0x01, 0x02]))
        #expect(OPACK.encode(.bool(true)) == Data([0x01]))
        #expect(OPACK.encode([.int(1)]) == Data([0xD1, 0x09]))
        #expect(OPACK.encode(["a": 1]) == Data([0xE1, 0x41, 0x61, 0x09]))
    }

    @Test func resolvesBackReferences() throws {
        // ["name", "name"] where the second element points at the first object.
        let bytes = Data([0xD2, 0x44, 0x6E, 0x61, 0x6D, 0x65, 0xA0])
        #expect(try OPACK.decode(bytes) == .array(["name", "name"]))

        // {"k": "v", "k2": "v"} using a one-byte pointer marker.
        let dict = Data([0xE2, 0x41, 0x6B, 0x41, 0x76, 0x42, 0x6B, 0x32, 0xC1, 0x01])
        #expect(try OPACK.decode(dict) == ["k": "v", "k2": "v"])
    }

    @Test func decodesEndlessContainers() throws {
        let list = Data([0xDF, 0x09, 0x0A, 0x03])
        #expect(try OPACK.decode(list) == .array([1, 2]))
        let dict = Data([0xEF, 0x41, 0x61, 0x09, 0x03])
        #expect(try OPACK.decode(dict) == ["a": 1])
    }

    @Test func rejectsTruncatedInput() {
        #expect(throws: OPACKError.truncated) { try OPACK.decode(Data([0x44, 0x61])) }
        #expect(throws: OPACKError.truncated) { try OPACK.decode(Data()) }
    }
}
