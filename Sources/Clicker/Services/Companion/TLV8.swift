import Foundation

/// TLV8 as used by HomeKit-style pairing (one byte tag, one byte length).
/// Values longer than 255 bytes are split across repeated tags and joined on read.
enum TLV8 {
    enum Tag: UInt8, Sendable {
        case method = 0x00
        case identifier = 0x01
        case salt = 0x02
        case publicKey = 0x03
        case proof = 0x04
        case encryptedData = 0x05
        case state = 0x06
        case error = 0x07
        case retryDelay = 0x08
        case certificate = 0x09
        case signature = 0x0A
        case permissions = 0x0B
        case fragmentData = 0x0C
        case fragmentLast = 0x0D
        case name = 0x11
        case flags = 0x13
    }

    enum ErrorCode: UInt8, Sendable {
        case unknown = 0x01
        case authentication = 0x02
        case backoff = 0x03
        case maxPeers = 0x04
        case maxTries = 0x05
        case unavailable = 0x06
        case busy = 0x07

        var message: String {
            switch self {
            case .unknown: return "The Apple TV reported an unknown error."
            case .authentication: return "The PIN was not accepted."
            case .backoff: return "The Apple TV asked to wait before trying again."
            case .maxPeers: return "The Apple TV has reached its pairing limit."
            case .maxTries: return "Too many failed attempts. Try again later."
            case .unavailable: return "Pairing is currently unavailable."
            case .busy: return "The Apple TV is busy with another pairing."
            }
        }
    }

    struct Items: Sendable {
        private var storage: [UInt8: Data] = [:]

        subscript(tag: Tag) -> Data? {
            get { storage[tag.rawValue] }
            set { storage[tag.rawValue] = newValue }
        }

        subscript(raw tag: UInt8) -> Data? {
            storage[tag]
        }

        var errorCode: ErrorCode? {
            guard let bytes = self[.error], let first = bytes.first else { return nil }
            return ErrorCode(rawValue: first)
        }

        fileprivate mutating func append(_ value: Data, forTag tag: UInt8) {
            if let existing = storage[tag] {
                storage[tag] = existing + value
            } else {
                storage[tag] = value
            }
        }
    }

    static func encode(_ items: [(Tag, Data)]) -> Data {
        var output = Data()
        for (tag, value) in items {
            var offset = 0
            repeat {
                let chunk = value.subdata(in: offset..<min(offset + 255, value.count))
                output.append(tag.rawValue)
                output.append(UInt8(chunk.count))
                output.append(chunk)
                offset += chunk.count
            } while offset < value.count
        }
        return output
    }

    static func decode(_ data: Data) throws -> Items {
        var items = Items()
        var index = data.startIndex
        while index < data.endIndex {
            guard data.index(index, offsetBy: 2) <= data.endIndex else { throw TLV8Error.truncated }
            let tag = data[index]
            let length = Int(data[index + 1])
            let valueStart = index + 2
            let valueEnd = valueStart + length
            guard valueEnd <= data.endIndex else { throw TLV8Error.truncated }
            items.append(data.subdata(in: valueStart..<valueEnd), forTag: tag)
            index = valueEnd
        }
        return items
    }
}

enum TLV8Error: Error {
    case truncated
}
