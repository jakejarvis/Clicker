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
    /// Raw `rpFl` bits.
    var flags: UInt64 = 0
    /// The whole TXT record as advertised, keys in their original case, for
    /// the picker's details view.
    var txtRecord: [String: String] = [:]
    /// Interfaces the service was seen on, as `en0 (Wi‑Fi)`, sorted and unique.
    var interfaces: [String] = []

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

    // MARK: - TXT record accessors

    /// Case-insensitive TXT lookup; tvOS advertises mixed-case keys.
    func txt(_ key: String) -> String? {
        if let value = txtRecord[key] { return value }
        let wanted = key.lowercased()
        return txtRecord.first { $0.key.lowercased() == wanted }?.value
    }

    /// `rpBA`: the Bluetooth address, which rotates.
    var bluetoothAddress: String? { txt("rpBA") }

    /// `rpVr`: the Companion (Rapport) protocol version.
    var companionVersion: String? { txt("rpVr") }

    var flagsHex: String { "0x" + String(flags, radix: 16, uppercase: true) }

    /// The flag bits pyatv knows, spelled out.
    var flagDescriptions: [String] {
        var names: [String] = []
        if flags & Self.pairingDisabledFlag != 0 { names.append("Pairing disabled") }
        if flags & Self.pairingWithPINFlag != 0 { names.append("PIN pairing") }
        return names
    }

    // MARK: - Initializers

    init(
        id: String,
        name: String,
        model: String?,
        endpoint: NWEndpoint?,
        pairingDisabled: Bool,
        flags: UInt64 = 0,
        txtRecord: [String: String] = [:],
        interfaces: [String] = []
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.endpoint = endpoint
        self.pairingDisabled = pairingDisabled
        self.isOnline = endpoint != nil
        self.flags = flags
        self.txtRecord = txtRecord
        self.interfaces = interfaces
    }

    /// Builds a device from a `_companion-link._tcp` browse result, or `nil`
    /// when the result is not an Apple TV (Macs, iPhones and HomePods also
    /// advertise this service).
    init?(result: NWBrowser.Result) {
        guard case .service(let name, _, _, _) = result.endpoint else { return nil }
        guard case .bonjour(let record) = result.metadata else { return nil }
        let interfaces = result.interfaces.map { "\($0.name) (\(Self.describe($0.type)))" }
        self.init(name: name, txt: record.dictionary, endpoint: result.endpoint, interfaces: interfaces)
    }

    /// The parsing half of `init?(result:)`, separated so tests can feed a
    /// TXT dictionary without an `NWBrowser.Result`.
    init?(name: String, txt record: [String: String], endpoint: NWEndpoint?, interfaces: [String]) {
        var txt: [String: String] = [:]
        for (key, value) in record { txt[key.lowercased()] = value }

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
            endpoint: endpoint,
            pairingDisabled: flags & Self.pairingDisabledFlag != 0,
            flags: flags,
            txtRecord: record,
            interfaces: Array(Set(interfaces)).sorted()
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

    private static func describe(_ type: NWInterface.InterfaceType) -> String {
        switch type {
        case .wifi: return "Wi‑Fi"
        case .wiredEthernet: return "Ethernet"
        case .cellular: return "Cellular"
        case .loopback: return "Loopback"
        default: return "Other"
        }
    }
}
