import Foundation

/// Long-term keys produced by pair-setup. These are what let the app skip the
/// PIN on later connections, so they are stored privately on disk.
struct PairingCredentials: Codable, Hashable, Sendable {
    /// Stable identifier for the Apple TV (see `AppleTVDevice.id`).
    var deviceID: String
    /// Name of the Apple TV at pairing time, shown while it is offline.
    var deviceName: String
    var deviceModel: String?
    /// The Apple TV's pairing identifier.
    var accessoryIdentifier: Data
    /// The Apple TV's long-term Ed25519 public key.
    var accessoryPublicKey: Data
    /// Our pairing identifier, a UUID string.
    var clientIdentifier: String
    /// Our long-term Ed25519 private key seed.
    var clientPrivateKey: Data
    var pairedAt: Date
}
