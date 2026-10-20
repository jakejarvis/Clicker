import ClickerApp
import ClickerCompanion
import Foundation
import Network

/// The made-up Apple TVs behind one demo run, with in-memory stand-ins for
/// the keychain and user defaults, so nothing a demo does is persisted.
final class DemoWorld {
    let scenario: DemoScenario
    /// How long pair-setup takes on the "TV". A second in the app, so the
    /// spinner shows; tests pass zero.
    private let latency: Duration
    /// The session the controller is using, for `.dropSession`.
    private var session: DemoSession?

    init(scenario: DemoScenario, latency: Duration = .seconds(1)) {
        self.scenario = scenario
        self.latency = latency
    }

    func dependencies() -> RemoteDependencies {
        let settings = DemoSettings()
        settings.selectedDeviceID = scenario.selected?.id
        settings.recentAppIDsByDevice = [DemoTV.livingRoom.id: DemoScenario.recentAppIDs]
        settings.favoriteAppIDsByDevice = [DemoTV.livingRoom.id: DemoScenario.favoriteAppIDs]
        return RemoteDependencies(
            discovery: DemoDiscovery(devices: scenario.online.map(\.device)),
            credentialBackend: DemoCredentialBackend(
                initial: scenario.paired.map { $0.credentials(pairedAt: .distantPast) },
                refusesStore: scenario.refusesStore),
            settings: settings,
            identity: { ClientIdentity(name: DemoScenario.clientName, deviceID: "02:D3:30:00:00:01") },
            makeSession: { _, credentials, _ in
                var tv = self.tv(id: credentials.deviceID)
                if credentials.pairedAt != .distantPast { tv.connectError = nil }
                let session = DemoSession(tv: tv)
                self.session = session
                return session
            },
            makePairingSession: { endpoint in
                DemoPairingSession(tv: self.tv(endpoint: endpoint), latency: self.latency)
            },
            localNetworkAccess: { [scenario] in scenario.localNetworkDenied ? .denied : .allowed },
            timings: scenario.timings
        )
    }

    /// Takes the scenario's steps one at a time, each once the app is ready
    /// for it, as a person clicking through would.
    func play(on controller: RemoteController) async {
        for step in scenario.steps {
            switch step {
            case .beginPairing:
                controller.beginPairing()
            case .enterCode(let code):
                await until { controller.pairingState == .awaitingPIN }
                controller.submitPIN(code)
            case .showSettings:
                controller.showSettings()
            case .openApps:
                // Opened once the list is in, so the picker isn't caught empty.
                await until { !controller.apps.isEmpty }
                controller.isAppPickerPresented = true
            case .openDevices:
                controller.devicePickerPresentation = DevicePickerPresentation(showsDetails: false)
            case .mute:
                await until { controller.canMute }
                controller.toggleMute()
            case .dropSession:
                // Once the connect has finished its follow-up requests: the
                // app refresh it queues would otherwise run after the drop
                // and connect again, as any queued command does.
                await until { controller.connectionState == .connected && !controller.apps.isEmpty }
                session?.drop()
            }
        }
    }

    private func tv(id: String) -> DemoTV {
        (scenario.online + scenario.paired).first { $0.id == id } ?? .livingRoom
    }

    private func tv(endpoint: NWEndpoint) -> DemoTV {
        scenario.online.first { $0.endpoint == endpoint } ?? .livingRoom
    }

    /// Waits for the controller to get somewhere, giving up after a while
    /// so a scenario that cannot get there leaves the app as it is.
    private func until(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
