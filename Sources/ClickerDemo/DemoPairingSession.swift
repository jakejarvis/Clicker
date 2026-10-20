import ClickerApp
import ClickerCompanion

/// A made-up TV's side of pair-setup: the code shows after `latency`, and
/// any code is accepted unless the TV says otherwise.
actor DemoPairingSession: PairingSession {
    private let tv: DemoTV
    private let latency: Duration

    init(tv: DemoTV, latency: Duration) {
        self.tv = tv
        self.latency = latency
    }

    func start() async throws {
        try await Task.sleep(for: latency)
    }

    func finish(
        pin: String, clientName: String, deviceID: String, deviceName: String, deviceModel: String?
    ) async throws -> PairingCredentials {
        try await Task.sleep(for: latency)
        // What a real TV's M4 error item turns into.
        guard tv.acceptsCode else { throw CompanionError.pairingError(TLV8.ErrorCode.authentication.message) }
        return tv.credentials(pairedAt: .now)
    }

    func cancel() async {}
}
