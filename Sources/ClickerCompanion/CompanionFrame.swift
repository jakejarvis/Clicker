import Foundation
import Network

/// Frame types on the wire. Every frame is a one-byte type, a three-byte
/// big-endian payload length and the payload.
package enum CompanionFrameType: UInt8, Sendable {
    case unknown = 0
    case noOp = 1
    case pairSetupStart = 3
    case pairSetupNext = 4
    case pairVerifyStart = 5
    case pairVerifyNext = 6
    case unencryptedOPACK = 7
    case encryptedOPACK = 8
    case plainOPACK = 9
    case pairingAttemptRequest = 10
    case pairingAttemptResponse = 11
    case sessionStartRequest = 16
    case sessionStartResponse = 17
    case sessionData = 18
    case familyIdentityRequest = 32
    case familyIdentityResponse = 33
    case familyIdentityUpdate = 34

    package var isAuthentication: Bool {
        switch self {
        case .pairSetupStart, .pairSetupNext, .pairVerifyStart, .pairVerifyNext: return true
        default: return false
        }
    }

    package var isOPACK: Bool {
        switch self {
        case .unencryptedOPACK, .encryptedOPACK, .plainOPACK: return true
        default: return false
        }
    }

    /// Responses to a `*Start` frame arrive as the matching `*Next` type.
    package var responseType: CompanionFrameType {
        switch self {
        case .pairSetupStart: return .pairSetupNext
        case .pairVerifyStart: return .pairVerifyNext
        default: return self
        }
    }
}

package enum CompanionMessageType: Int64, Sendable {
    case event = 1
    case request = 2
    case response = 3
}

package enum CompanionError: Error, LocalizedError, Sendable {
    case notConnected
    case disconnected
    case timeout
    case connectionFailed(NWError)
    case unexpectedResponse(String)
    case remoteError(String)
    case pairingError(String)
    case authenticationFailed(String)
    /// Pair-verify reached a TV whose pairing identifier is not the one we
    /// paired with: it was reset or re-paired, so our credentials are dead.
    case identityChanged
    /// Pair-verify was refused outright: the TV no longer has our pairing
    /// (Clicker was removed from Remotes and Devices), so our credentials
    /// are dead just as after a reset.
    case pairingLost
    case encryptionFailed
    case pairingDisabled

    package var errorDescription: String? {
        switch self {
        case .notConnected: return String(localized: "Not connected to the Apple TV.")
        case .disconnected: return String(localized: "The connection to the Apple TV was closed.")
        case .timeout: return String(localized: "The Apple TV didn't respond in time.")
        case .connectionFailed: return String(localized: "Couldn't connect to the Apple TV.")
        case .unexpectedResponse: return String(localized: "The Apple TV sent an unexpected reply.")
        case .remoteError: return String(localized: "The Apple TV refused that command.")
        case .pairingError(let message): return message
        case .authenticationFailed(let message): return message
        case .identityChanged: return String(localized: "This Apple TV was reset, so it needs to be paired again.")
        case .pairingLost:
            return String(localized: "This Apple TV no longer recognizes Clicker, so it needs to be paired again.")
        case .encryptionFailed: return String(localized: "Couldn't decrypt a message from the Apple TV.")
        case .pairingDisabled:
            return String(
                localized:
                    "Pairing is turned off on this Apple TV. Allow it in Settings › Remotes and Devices › Remote App and Devices."
            )
        }
    }
}
