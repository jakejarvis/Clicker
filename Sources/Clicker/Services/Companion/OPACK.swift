import Foundation

/// A value in Apple's OPACK serialization format, which the Companion protocol
/// uses for every message payload.
indirect enum OPACKValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case uuid(UUID)
    case date(Double)
    case int(Int64)
    case double(Double)
    case string(String)
    case data(Data)
    case array([OPACKValue])
    case dictionary([OPACKValue: OPACKValue])
}

// MARK: - Convenience accessors

extension OPACKValue {
    subscript(key: String) -> OPACKValue? {
        guard case .dictionary(let dictionary) = self else { return nil }
        return dictionary[.string(key)]
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var intValue: Int64? {
        switch self {
        case .int(let value): return value
        case .double(let value): return Int64(exactly: value)
        case .bool(let value): return value ? 1 : 0
        default: return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .int(let value): return value != 0
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .double(let value): return value
        case .int(let value): return Double(value)
        default: return nil
        }
    }

    var dataValue: Data? {
        if case .data(let value) = self { return value }
        return nil
    }

    var arrayValue: [OPACKValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var dictionaryValue: [OPACKValue: OPACKValue]? {
        if case .dictionary(let value) = self { return value }
        return nil
    }

    /// The dictionary with only its string-keyed entries, which is every key
    /// Apple uses in practice.
    var stringKeyedDictionary: [String: OPACKValue]? {
        guard let dictionary = dictionaryValue else { return nil }
        var result: [String: OPACKValue] = [:]
        for (key, value) in dictionary {
            if case .string(let name) = key { result[name] = value }
        }
        return result
    }

    static func dictionary(_ entries: [String: OPACKValue]) -> OPACKValue {
        var result: [OPACKValue: OPACKValue] = [:]
        for (key, value) in entries { result[.string(key)] = value }
        return .dictionary(result)
    }
}

extension OPACKValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByBooleanLiteral, ExpressibleByFloatLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int64) { self = .int(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(floatLiteral value: Double) { self = .double(value) }
    init(arrayLiteral elements: OPACKValue...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, OPACKValue)...) {
        var result: [OPACKValue: OPACKValue] = [:]
        for (key, value) in elements { result[.string(key)] = value }
        self = .dictionary(result)
    }
}

extension OPACKValue: CustomStringConvertible {
    var description: String {
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .uuid(let value): return value.uuidString
        case .date(let value): return "date(\(value))"
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .string(let value): return "\"\(value)\""
        case .data(let value): return "<\(value.count) bytes>"
        case .array(let values): return "[" + values.map(\.description).joined(separator: ", ") + "]"
        case .dictionary(let entries):
            let body = entries
                .map { "\($0.key.description): \($0.value.description)" }
                .sorted()
                .joined(separator: ", ")
            return "{" + body + "}"
        }
    }
}

// MARK: - Codec

enum OPACKError: Error, Equatable {
    case truncated
    case unsupportedMarker(UInt8)
    case invalidPointer(Int)
    case invalidString
}

enum OPACK {
    static func encode(_ value: OPACKValue) -> Data {
        var output = Data()
        encode(value, into: &output)
        return output
    }

    static func decode(_ data: Data) throws -> OPACKValue {
        var decoder = Decoder(bytes: [UInt8](data))
        return try decoder.decodeValue()
    }

    // The encoder never emits back-references; inline encoding is always valid.
    private static func encode(_ value: OPACKValue, into output: inout Data) {
        switch value {
        case .null:
            output.append(0x04)
        case .bool(let flag):
            output.append(flag ? 0x01 : 0x02)
        case .uuid(let uuid):
            output.append(0x05)
            withUnsafeBytes(of: uuid.uuid) { output.append(contentsOf: $0) }
        case .date(let seconds):
            output.append(0x06)
            appendLittleEndian(seconds.bitPattern, byteCount: 8, into: &output)
        case .int(let number):
            if number < 0 {
                output.append(0x33)
                appendLittleEndian(UInt64(bitPattern: number), byteCount: 8, into: &output)
            } else if number < 0x28 {
                output.append(UInt8(number) + 0x08)
            } else if number <= 0xFF {
                output.append(0x30)
                appendLittleEndian(UInt64(number), byteCount: 1, into: &output)
            } else if number <= 0xFFFF {
                output.append(0x31)
                appendLittleEndian(UInt64(number), byteCount: 2, into: &output)
            } else if number <= 0xFFFF_FFFF {
                output.append(0x32)
                appendLittleEndian(UInt64(number), byteCount: 4, into: &output)
            } else {
                output.append(0x33)
                appendLittleEndian(UInt64(number), byteCount: 8, into: &output)
            }
        case .double(let number):
            output.append(0x36)
            appendLittleEndian(number.bitPattern, byteCount: 8, into: &output)
        case .string(let string):
            let bytes = Data(string.utf8)
            appendLengthPrefixed(bytes, shortBase: 0x40, longBase: 0x60, into: &output)
        case .data(let bytes):
            appendLengthPrefixed(bytes, shortBase: 0x70, longBase: 0x90, into: &output)
        case .array(let values):
            if values.count < 0x0F {
                output.append(0xD0 + UInt8(values.count))
                for value in values { encode(value, into: &output) }
            } else {
                output.append(0xDF)
                for value in values { encode(value, into: &output) }
                output.append(0x03)
            }
        case .dictionary(let entries):
            // Sort for deterministic output; the protocol does not care about order.
            let ordered = entries.sorted { $0.key.description < $1.key.description }
            if ordered.count < 0x0F {
                output.append(0xE0 + UInt8(ordered.count))
                for (key, value) in ordered {
                    encode(key, into: &output)
                    encode(value, into: &output)
                }
            } else {
                output.append(0xEF)
                for (key, value) in ordered {
                    encode(key, into: &output)
                    encode(value, into: &output)
                }
                output.append(0x03)
            }
        }
    }

    private static func appendLengthPrefixed(
        _ bytes: Data, shortBase: UInt8, longBase: UInt8, into output: inout Data
    ) {
        let count = bytes.count
        if count <= 0x20 {
            output.append(shortBase + UInt8(count))
        } else if count <= 0xFF {
            output.append(longBase + 1)
            appendLittleEndian(UInt64(count), byteCount: 1, into: &output)
        } else if count <= 0xFFFF {
            output.append(longBase + 2)
            appendLittleEndian(UInt64(count), byteCount: 2, into: &output)
        } else if shortBase == 0x40, count <= 0xFF_FFFF {
            // Strings use a 3-byte length for 0x63; data skips straight to 4 bytes.
            output.append(longBase + 3)
            appendLittleEndian(UInt64(count), byteCount: 3, into: &output)
        } else if shortBase == 0x40 {
            output.append(longBase + 4)
            appendLittleEndian(UInt64(count), byteCount: 4, into: &output)
        } else if count <= 0xFFFF_FFFF {
            output.append(longBase + 3)
            appendLittleEndian(UInt64(count), byteCount: 4, into: &output)
        } else {
            output.append(longBase + 4)
            appendLittleEndian(UInt64(count), byteCount: 8, into: &output)
        }
        output.append(bytes)
    }

    private static func appendLittleEndian(_ value: UInt64, byteCount: Int, into output: inout Data) {
        for shift in 0..<byteCount {
            output.append(UInt8(truncatingIfNeeded: value >> (8 * UInt64(shift))))
        }
    }

    /// Decoder that mirrors the object-list semantics Apple's encoder relies on
    /// for back-references: strings, data, UUIDs, dates and floats are recorded
    /// (deduplicated) as they are decoded, and pointer markers index that list.
    private struct Decoder {
        let bytes: [UInt8]
        var index = 0
        var objects: [OPACKValue] = []

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        mutating func decodeValue() throws -> OPACKValue {
            let marker = try nextByte()
            var recordObject = true
            let value: OPACKValue

            switch marker {
            case 0x01:
                value = .bool(true)
                recordObject = false
            case 0x02:
                value = .bool(false)
                recordObject = false
            case 0x04:
                value = .null
                recordObject = false
            case 0x05:
                let raw = try take(16)
                var uuidBytes: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                withUnsafeMutableBytes(of: &uuidBytes) { $0.copyBytes(from: raw) }
                value = .uuid(UUID(uuid: uuidBytes))
            case 0x06:
                value = .date(Double(bitPattern: try littleEndian(byteCount: 8)))
            case 0x08...0x2F:
                value = .int(Int64(marker - 0x08))
                recordObject = false
            case 0x35:
                value = .double(Double(Float(bitPattern: UInt32(try littleEndian(byteCount: 4)))))
            case 0x36:
                value = .double(Double(bitPattern: try littleEndian(byteCount: 8)))
            case 0x30...0x33:
                let byteCount = 1 << Int(marker & 0x0F)
                value = .int(Int64(bitPattern: try littleEndian(byteCount: byteCount)))
                recordObject = false
            case 0x40...0x60:
                value = try string(length: Int(marker - 0x40))
            case 0x61...0x64:
                let length = Int(try littleEndian(byteCount: Int(marker & 0x0F)))
                value = try string(length: length)
            case 0x70...0x90:
                value = .data(Data(try take(Int(marker - 0x70))))
            case 0x91...0x94:
                let length = Int(try littleEndian(byteCount: 1 << (Int(marker & 0x0F) - 1)))
                value = .data(Data(try take(length)))
            case 0xA0...0xC0:
                value = try object(at: Int(marker - 0xA0))
                recordObject = false
            case 0xC1...0xC4:
                let pointer = Int(try littleEndian(byteCount: Int(marker - 0xC0)))
                value = try object(at: pointer)
                recordObject = false
            case 0xD0...0xDF:
                var values: [OPACKValue] = []
                let count = Int(marker & 0x0F)
                if count == 0x0F {
                    while try peekByte() != 0x03 {
                        values.append(try decodeValue())
                    }
                    index += 1
                } else {
                    for _ in 0..<count { values.append(try decodeValue()) }
                }
                value = .array(values)
                recordObject = false
            case 0xE0...0xEF:
                var entries: [OPACKValue: OPACKValue] = [:]
                let count = Int(marker & 0x0F)
                if count == 0x0F {
                    while try peekByte() != 0x03 {
                        let key = try decodeValue()
                        entries[key] = try decodeValue()
                    }
                    index += 1
                } else {
                    for _ in 0..<count {
                        let key = try decodeValue()
                        entries[key] = try decodeValue()
                    }
                }
                value = .dictionary(entries)
                recordObject = false
            default:
                throw OPACKError.unsupportedMarker(marker)
            }

            if recordObject, !objects.contains(value) {
                objects.append(value)
            }
            return value
        }

        private func object(at pointer: Int) throws -> OPACKValue {
            guard objects.indices.contains(pointer) else { throw OPACKError.invalidPointer(pointer) }
            return objects[pointer]
        }

        private mutating func string(length: Int) throws -> OPACKValue {
            guard let string = String(bytes: try take(length), encoding: .utf8) else {
                throw OPACKError.invalidString
            }
            return .string(string)
        }

        private func peekByte() throws -> UInt8 {
            guard index < bytes.count else { throw OPACKError.truncated }
            return bytes[index]
        }

        private mutating func nextByte() throws -> UInt8 {
            let byte = try peekByte()
            index += 1
            return byte
        }

        private mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
            guard count >= 0, index + count <= bytes.count else { throw OPACKError.truncated }
            defer { index += count }
            return bytes[index..<(index + count)]
        }

        private mutating func littleEndian(byteCount: Int) throws -> UInt64 {
            guard byteCount <= 8 else { throw OPACKError.unsupportedMarker(0x34) }
            var result: UInt64 = 0
            for (offset, byte) in try take(byteCount).enumerated() {
                result |= UInt64(byte) << (8 * UInt64(offset))
            }
            return result
        }
    }
}
