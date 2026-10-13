import Foundation

/// Long-term keys produced by pair-setup. These are what let the app skip the
/// PIN on later connections, so they are stored privately on disk.
package struct PairingCredentials: Codable, Hashable, Sendable {
    /// Stable identifier for the Apple TV (see `AppleTVDevice.id`).
    package var deviceID: String
    /// Name of the Apple TV at pairing time, shown while it is offline.
    package var deviceName: String
    package var deviceModel: String?
    /// The Apple TV's pairing identifier.
    package var accessoryIdentifier: Data
    /// The Apple TV's long-term Ed25519 public key.
    package var accessoryPublicKey: Data
    /// Our pairing identifier, a UUID string.
    package var clientIdentifier: String
    /// Our long-term Ed25519 private key seed.
    package var clientPrivateKey: Data
    package var pairedAt: Date

    package init(
        deviceID: String, deviceName: String, deviceModel: String?, accessoryIdentifier: Data,
        accessoryPublicKey: Data, clientIdentifier: String, clientPrivateKey: Data, pairedAt: Date
    ) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.deviceModel = deviceModel
        self.accessoryIdentifier = accessoryIdentifier
        self.accessoryPublicKey = accessoryPublicKey
        self.clientIdentifier = clientIdentifier
        self.clientPrivateKey = clientPrivateKey
        self.pairedAt = pairedAt
    }
}
