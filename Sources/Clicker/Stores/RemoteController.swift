import Foundation
import Observation

enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    var isBusy: Bool { self == .connecting }
}

enum PairingState: Equatable, Sendable {
    case idle
    case starting
    case awaitingPIN
    case finishing
    case failed(String)
}

/// App-wide remote control state: which Apple TV is selected, whether we are
/// connected to it, and the actions the UI can trigger.
@MainActor
@Observable
final class RemoteController {
    let browser = DeviceBrowser()
    let credentialStore = CredentialStore()

    private(set) var selectedDeviceID: String?
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var powerState: PowerState = .unknown
    private(set) var pairingState: PairingState = .idle
    private(set) var apps: [AppleTVApp] = []
    private(set) var isLoadingApps = false
    private(set) var lastActionError: String?

    @ObservationIgnored private var client: CompanionClient?
    @ObservationIgnored private var clientDeviceID: String?
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var pairingSession: CompanionPairingSession?
    @ObservationIgnored private var pairingDeviceID: String?
    @ObservationIgnored private var commandQueue: Task<Void, Never>?

    private static let selectedDeviceKey = "selectedDeviceID"

    init() {
        selectedDeviceID = UserDefaults.standard.string(forKey: Self.selectedDeviceKey)
        browser.onUpdate = { [weak self] devices in
            self?.devicesDidChange(devices)
        }
    }

    // MARK: - Devices

    /// Online devices merged with paired devices that are not currently visible.
    var devices: [AppleTVDevice] {
        var result = browser.devices
        let onlineIDs = Set(result.map(\.id))
        for credentials in credentialStore.credentials where !onlineIDs.contains(credentials.deviceID) {
            result.append(AppleTVDevice(offline: credentials))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var selectedDevice: AppleTVDevice? {
        guard let selectedDeviceID else { return nil }
        return devices.first { $0.id == selectedDeviceID }
    }

    var selectedCredentials: PairingCredentials? {
        guard let selectedDeviceID else { return nil }
        return credentialStore.credentials(for: selectedDeviceID)
    }

    func isPaired(_ device: AppleTVDevice) -> Bool {
        credentialStore.credentials(for: device.id) != nil
    }

    func start() {
        browser.start()
        connectIfNeeded()
    }

    func select(_ device: AppleTVDevice) {
        guard device.id != selectedDeviceID else {
            connectIfNeeded()
            return
        }
        cancelPairing()
        disconnect()
        selectedDeviceID = device.id
        UserDefaults.standard.set(device.id, forKey: Self.selectedDeviceKey)
        apps = []
        powerState = .unknown
        lastActionError = nil
        connectIfNeeded()
    }

    func forgetPairing(for device: AppleTVDevice) {
        if device.id == clientDeviceID {
            disconnect()
        }
        credentialStore.remove(deviceID: device.id)
        if selectedDeviceID == device.id, !device.isOnline {
            selectedDeviceID = nil
            UserDefaults.standard.removeObject(forKey: Self.selectedDeviceKey)
        }
    }

    private func devicesDidChange(_ devices: [AppleTVDevice]) {
        for device in devices {
            credentialStore.updateName(device.name, model: device.model, for: device.id)
        }
        if selectedDeviceID == nil || self.devices.first(where: { $0.id == selectedDeviceID }) == nil {
            let preferred = devices.first { isPaired($0) } ?? devices.first
            if let preferred {
                selectedDeviceID = preferred.id
                UserDefaults.standard.set(preferred.id, forKey: Self.selectedDeviceKey)
            }
        }
        connectIfNeeded()
    }

    // MARK: - Connection

    /// Called when the menu bar panel opens.
    func panelDidAppear() {
        browser.start()
        lastActionError = nil
        connectIfNeeded()
    }

    func connectIfNeeded() {
        guard connectTask == nil else { return }
        guard let device = selectedDevice, let endpoint = device.endpoint,
              let credentials = credentialStore.credentials(for: device.id)
        else { return }
        if client != nil, clientDeviceID == device.id, connectionState == .connected { return }

        disconnect()
        connectionState = .connecting
        let identity = IdentityStore.identity()
        let client = CompanionClient(endpoint: endpoint, credentials: credentials, identity: identity)
        self.client = client
        clientDeviceID = device.id

        connectTask = Task { [weak self] in
            do {
                try await client.connect()
                guard let self, self.client === client else {
                    await client.disconnect()
                    return
                }
                self.connectionState = .connected
                self.listenForEvents(from: client)
                if let state = try? await client.fetchPowerState() {
                    self.powerState = state
                }
                self.refreshApps()
            } catch {
                guard let self, self.client === client else { return }
                Log.remote.error("Connect failed: \(String(describing: error), privacy: .public)")
                self.connectionState = .failed(Self.describe(error))
                self.client = nil
                self.clientDeviceID = nil
            }
            self?.connectTask = nil
        }
    }

    func retryConnection() {
        disconnect()
        connectIfNeeded()
    }

    func disconnect() {
        connectTask?.cancel()
        connectTask = nil
        eventTask?.cancel()
        eventTask = nil
        if let client {
            Task { await client.disconnect() }
        }
        client = nil
        clientDeviceID = nil
        connectionState = .disconnected
        powerState = .unknown
    }

    private func listenForEvents(from client: CompanionClient) {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            for await event in client.events {
                guard let self, self.client === client else { return }
                switch event.name {
                case "TVSystemStatus", "SystemStatus":
                    if let raw = event.content["state"]?.intValue, let state = PowerState(rawValue: raw) {
                        self.powerState = state
                    }
                default:
                    break
                }
            }
            guard let self, self.client === client else { return }
            // The stream ends when the connection closes.
            self.client = nil
            self.clientDeviceID = nil
            if self.connectionState == .connected {
                self.connectionState = .disconnected
            }
        }
    }

    // MARK: - Actions

    func press(_ command: HIDCommand) {
        perform { try await $0.press(command) }
    }

    func buttonDown(_ command: HIDCommand) {
        perform { try await $0.buttonDown(command) }
    }

    func buttonUp(_ command: HIDCommand) {
        perform { try await $0.buttonUp(command) }
    }

    func launch(_ app: AppleTVApp) {
        perform { try await $0.launchApp(bundleIdentifier: app.bundleIdentifier) }
    }

    func refreshApps() {
        guard !isLoadingApps else { return }
        isLoadingApps = true
        perform(
            { [weak self] client in
                let apps = try await client.fetchApps()
                self?.apps = apps
            },
            completion: { [weak self] in self?.isLoadingApps = false }
        )
    }

    /// Runs an action against the connected client. Actions are serialized so a
    /// button "down" is always delivered before its "up".
    private func perform(
        _ action: @escaping @MainActor @Sendable (CompanionClient) async throws -> Void,
        completion: (@MainActor () -> Void)? = nil
    ) {
        let previous = commandQueue
        commandQueue = Task { [weak self] in
            await previous?.value
            defer { completion?() }
            guard let self else { return }
            guard let client = await self.readyClient() else { return }
            do {
                try await action(client)
                self.lastActionError = nil
            } catch {
                Log.remote.error("Command failed: \(String(describing: error), privacy: .public)")
                self.lastActionError = Self.describe(error)
                switch error {
                case CompanionError.disconnected, CompanionError.notConnected:
                    self.disconnect()
                default:
                    break
                }
            }
        }
    }

    /// Returns a connected client, connecting first when necessary.
    private func readyClient() async -> CompanionClient? {
        connectIfNeeded()
        if let task = connectTask {
            await task.value
        }
        guard connectionState == .connected, let client else { return nil }
        return client
    }

    // MARK: - Pairing

    func beginPairing() {
        guard let device = selectedDevice, let endpoint = device.endpoint else { return }
        guard !device.pairingDisabled else {
            pairingState = .failed(CompanionError.pairingDisabled.localizedDescription)
            return
        }
        cancelPairing()
        disconnect()
        pairingState = .starting
        pairingDeviceID = device.id
        let session = CompanionPairingSession(endpoint: endpoint)
        pairingSession = session
        Task { [weak self] in
            do {
                try await session.start()
                guard let self, self.pairingSession === session else { return }
                self.pairingState = .awaitingPIN
            } catch {
                guard let self, self.pairingSession === session else { return }
                self.pairingState = .failed(Self.describe(error))
                self.pairingSession = nil
            }
        }
    }

    func submitPIN(_ pin: String) {
        guard let session = pairingSession, let device = selectedDevice, device.id == pairingDeviceID else { return }
        let digits = pin.filter(\.isNumber)
        guard digits.count == 4 else {
            pairingState = .failed("Enter the four-digit PIN shown on the Apple TV.")
            return
        }
        pairingState = .finishing
        let clientName = IdentityStore.identity().name
        Task { [weak self] in
            do {
                let credentials = try await session.finish(pin: digits, clientName: clientName, device: device)
                guard let self, self.pairingSession === session else { return }
                self.credentialStore.save(credentials)
                self.pairingSession = nil
                self.pairingDeviceID = nil
                self.pairingState = .idle
                self.connectIfNeeded()
            } catch {
                guard let self, self.pairingSession === session else { return }
                await session.cancel()
                self.pairingSession = nil
                self.pairingState = .failed(Self.describe(error))
            }
        }
    }

    func cancelPairing() {
        if let session = pairingSession {
            Task { await session.cancel() }
        }
        pairingSession = nil
        pairingDeviceID = nil
        pairingState = .idle
    }

    private static func describe(_ error: Error) -> String {
        if let companionError = error as? CompanionError {
            return companionError.localizedDescription
        }
        return error.localizedDescription
    }
}
