import Foundation
import Network

/// An Apple TV discovered on the local network, or one we have credentials for
/// that is not currently advertising.
struct AppleTVDevice: Identifiable, Hashable, Sendable {
    /// The `rpMRtID` UUID from the TXT record, which tvOS keeps stable. The
    /// `rpBA` address rotates, so it is only a fallback, then the Bonjour name.
    let id: String
    var name: String
    var model: String?
    var endpoint: NWEndpoint?
    var pairingDisabled: Bool
    var isOnline: Bool

    var modelDisplayName: String {
        guard let model else { return "Apple TV" }
        switch model {
        case "AppleTV2,1": return "Apple TV (2nd gen)"
        case "AppleTV3,1", "AppleTV3,2": return "Apple TV (3rd gen)"
        case "AppleTV5,3": return "Apple TV HD"
        case "AppleTV6,2": return "Apple TV 4K"
        case "AppleTV11,1": return "Apple TV 4K (2nd gen)"
        case "AppleTV14,1": return "Apple TV 4K (3rd gen)"
        default: return model.hasPrefix("AppleTV") ? "Apple TV" : model
        }
    }

    /// Model family without the generation, for tight spaces.
    var shortModelName: String {
        guard let model else { return "Apple TV" }
        switch model {
        case "AppleTV5,3": return "Apple TV HD"
        case "AppleTV6,2", "AppleTV11,1", "AppleTV14,1": return "Apple TV 4K"
        default: return "Apple TV"
        }
    }

    static let pairingDisabledFlag: UInt64 = 0x04
    static let pairingWithPINFlag: UInt64 = 0x4000

    init(id: String, name: String, model: String?, endpoint: NWEndpoint?, pairingDisabled: Bool) {
        self.id = id
        self.name = name
        self.model = model
        self.endpoint = endpoint
        self.pairingDisabled = pairingDisabled
        self.isOnline = endpoint != nil
    }

    /// Builds a device from a `_companion-link._tcp` browse result, or `nil`
    /// when the result is not an Apple TV (Macs, iPhones and HomePods also
    /// advertise this service).
    init?(result: NWBrowser.Result) {
        guard case .service(let name, _, _, _) = result.endpoint else { return nil }
        guard case .bonjour(let record) = result.metadata else { return nil }

        var txt: [String: String] = [:]
        for (key, value) in record.dictionary { txt[key.lowercased()] = value }

        guard let model = txt["rpmd"], model.hasPrefix("AppleTV") else { return nil }

        var flags: UInt64 = 0
        if let raw = txt["rpfl"] {
            let hex = raw.lowercased().hasPrefix("0x") ? String(raw.dropFirst(2)) : raw
            flags = UInt64(hex, radix: 16) ?? 0
        }

        self.init(
            id: txt["rpmrtid"]?.uppercased() ?? txt["rpba"] ?? name,
            name: name,
            model: model,
            endpoint: result.endpoint,
            pairingDisabled: flags & Self.pairingDisabledFlag != 0
        )
    }

    init(offline credentials: PairingCredentials) {
        self.init(
            id: credentials.deviceID,
            name: credentials.deviceName,
            model: credentials.deviceModel,
            endpoint: nil,
            pairingDisabled: false
        )
    }
}
