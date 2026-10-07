import Foundation
import Network
import Observation

/// Browses Bonjour for `_companion-link._tcp` and keeps a list of Apple TVs.
@MainActor
@Observable
final class DeviceBrowser {
    private(set) var devices: [AppleTVDevice] = []
    private(set) var isBrowsing = false
    private(set) var errorMessage: String?

    /// Called on the main actor whenever the device list changes.
    var onUpdate: (([AppleTVDevice]) -> Void)?

    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private let queue = DispatchQueue(label: "com.jakejarvis.Clicker.discovery")

    func start() {
        guard browser == nil else { return }

        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: "_companion-link._tcp", domain: nil),
            using: parameters
        )

        browser.stateUpdateHandler = { [weak self] state in
            let browsing: Bool
            var failure: String?
            switch state {
            case .ready:
                browsing = true
            case .failed(let error):
                browsing = false
                failure = error.localizedDescription
            case .cancelled:
                browsing = false
            default:
                browsing = false
            }
            Task { @MainActor in
                guard let self else { return }
                self.isBrowsing = browsing
                self.errorMessage = failure
                if failure != nil {
                    Log.discovery.error("Browser failed: \(failure ?? "", privacy: .public)")
                    self.restartAfterFailure()
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap(AppleTVDevice.init(result:))
            Task { @MainActor in
                self?.update(with: found)
            }
        }

        self.browser = browser
        browser.start(queue: queue)
        Log.discovery.info("Started browsing for Apple TVs")
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
    }

    private func update(with found: [AppleTVDevice]) {
        // The same device shows up once per network interface.
        var unique: [String: AppleTVDevice] = [:]
        for device in found where unique[device.id] == nil {
            unique[device.id] = device
        }
        let sorted = unique.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        guard sorted != devices else { return }
        devices = sorted
        Log.discovery.info("Apple TVs on network: \(sorted.map(\.name).joined(separator: ", "), privacy: .public)")
        onUpdate?(sorted)
    }

    private func restartAfterFailure() {
        browser?.cancel()
        browser = nil
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.start()
        }
    }
}
