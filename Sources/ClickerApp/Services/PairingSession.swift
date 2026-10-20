import ClickerCompanion

/// One pair-setup with an Apple TV: what `RemoteController` asks of
/// `CompanionPairingSession`.
package nonisolated protocol PairingSession: AnyObject, Sendable {
    /// Connects and asks the TV to show a code.
    func start() async throws
    /// Proves the code and returns the credentials to store.
    func finish(
        pin: String, clientName: String, deviceID: String, deviceName: String, deviceModel: String?
    ) async throws -> PairingCredentials
    func cancel() async
}

extension CompanionPairingSession: PairingSession {}
