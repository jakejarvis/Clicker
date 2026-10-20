import ClickerApp
import Observation

/// The scenario's TVs, all on the "network" from the start.
@Observable
final class DemoDiscovery: DeviceDiscovery {
    private(set) var devices: [AppleTVDevice] = []
    private(set) var isRescanning = false
    var errorMessage: String? { nil }
    @ObservationIgnored var onUpdate: (([AppleTVDevice]) -> Void)?
    @ObservationIgnored private let found: [AppleTVDevice]

    init(devices: [AppleTVDevice]) {
        found = devices
    }

    func start() {
        guard devices != found else { return }
        devices = found
        onUpdate?(devices)
    }

    /// Shows the Rescan row's spinner; there is nothing new to find.
    func rescan(knocking host: String?) {
        isRescanning = true
        Task {
            try? await Task.sleep(for: .seconds(1))
            isRescanning = false
        }
    }
}
