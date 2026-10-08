import Foundation
import Network
import Observation

/// Browses Bonjour for `_companion-link._tcp` and keeps a list of Apple TVs.
///
/// The browser runs for the app's whole life: `NWBrowser` reports additions,
/// removals and TXT changes as they happen and follows network path changes,
/// so the list normally needs no manual refresh. `restart()` exists for the
/// picker's Rescan action; it re-issues the Bonjour query but cannot flush
/// records mDNSResponder still caches.
@MainActor
@Observable
final class DeviceBrowser {
    private(set) var devices: [AppleTVDevice] = []
    private(set) var isBrowsing = false
    private(set) var isRescanning = false
    private(set) var errorMessage: String?

    /// Called on the main actor whenever the device list changes.
    var onUpdate: (([AppleTVDevice]) -> Void)?

    /// How long after a restart removals are held back, so a partial first
    /// callback from the new browser cannot drop the selected TV.
    static let rescanGrace: Duration = .seconds(2)

    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var latestFound: [AppleTVDevice] = []
    @ObservationIgnored private var rescanTask: Task<Void, Never>?
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

    /// Cancels the browser and starts a fresh one, keeping the current list
    /// until the new results have settled.
    func restart() {
        guard !isRescanning else { return }
        browser?.cancel()
        browser = nil
        isRescanning = true
        Log.discovery.info("Restarted browsing for Apple TVs")
        start()
        rescanTask = Task { [weak self] in
            try? await Task.sleep(for: Self.rescanGrace)
            guard let self, !Task.isCancelled else { return }
            isRescanning = false
            update(with: latestFound)
        }
    }

    private func update(with found: [AppleTVDevice]) {
        latestFound = found
        var merged = Self.merge(found)
        if isRescanning {
            // Hold removals back until the grace period ends.
            let seen = Set(merged.map(\.id))
            merged = Self.sort(merged + devices.filter { !seen.contains($0.id) })
        }
        guard merged != devices else { return }
        devices = merged
        Log.discovery.info("Apple TVs on network: \(merged.map(\.name).joined(separator: ", "), privacy: .public)")
        onUpdate?(merged)
    }

    /// Collapses one result per interface into one device per id, keeping the
    /// first result's fields and the union of interfaces, sorted by name.
    static func merge(_ found: [AppleTVDevice]) -> [AppleTVDevice] {
        var unique: [String: AppleTVDevice] = [:]
        var order: [String] = []
        for device in found {
            if var existing = unique[device.id] {
                existing.interfaces = Array(Set(existing.interfaces + device.interfaces)).sorted()
                unique[device.id] = existing
            } else {
                unique[device.id] = device
                order.append(device.id)
            }
        }
        return sort(order.compactMap { unique[$0] })
    }

    private static func sort(_ devices: [AppleTVDevice]) -> [AppleTVDevice] {
        devices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
