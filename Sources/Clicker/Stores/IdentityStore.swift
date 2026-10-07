import Foundation

/// Stable identity for this install, kept in user defaults.
enum IdentityStore {
    static let clientNameKey = "clientName"
    private static let deviceIDKey = "clientDeviceID"

    static var defaultClientName: String {
        Host.current().localizedName ?? "Clicker"
    }

    static func identity() -> ClientIdentity {
        let defaults = UserDefaults.standard
        let name = defaults.string(forKey: clientNameKey).flatMap { $0.isEmpty ? nil : $0 } ?? defaultClientName

        let deviceID: String
        if let stored = defaults.string(forKey: deviceIDKey) {
            deviceID = stored
        } else {
            // Locally administered unicast MAC address.
            var bytes = (0..<6).map { _ in UInt8.random(in: 0...255) }
            bytes[0] = (bytes[0] | 0x02) & 0xFE
            deviceID = bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
            defaults.set(deviceID, forKey: deviceIDKey)
        }

        return ClientIdentity(name: name, deviceID: deviceID)
    }
}
