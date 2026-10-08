import Foundation
import Observation
import SwiftUI

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
    /// Credentials are saved; the card shows a check for a moment before the
    /// remote takes over.
    case succeeded
    case failed(String)
}

/// Which page the menu bar panel is showing. Settings replaces the remote in
/// place; there is no separate window.
enum PanelScreen: Hashable, Sendable {
    case remote
    case settings
}

/// App-wide remote control state: which Apple TV is selected, whether we are
/// connected to it, and the actions the UI can trigger.
@MainActor
@Observable
final class RemoteController {
    let browser = DeviceBrowser()
    let credentialStore: CredentialStore
    /// Canned state for screenshots (`--demo`); see `DemoScenario`.
    let demo: DemoScenario?

    private(set) var selectedDeviceID: String?
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var powerState: PowerState = .unknown
    private(set) var pairingState: PairingState = .idle
    private(set) var apps: [AppleTVApp] = []
    private(set) var isLoadingApps = false
    private(set) var lastActionError: String?
    /// Non-nil while the Apple TV has a text field focused.
    private(set) var keyboardSession: TextInputArchive.Session?
    /// Our mirror of the text in the TV's focused field.
    private(set) var tvText = ""
    /// Software mute: the volume is set to zero and restored on unmute.
    private(set) var isMuted = false
    var screen: PanelScreen = .remote

    @ObservationIgnored private var client: CompanionClient?
    @ObservationIgnored private var clientDeviceID: String?
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var pairingSession: CompanionPairingSession?
    @ObservationIgnored private var pairingDeviceID: String?
    @ObservationIgnored private var commandQueue: Task<Void, Never>?
    @ObservationIgnored private var volumeBeforeMute: Double = 0.5
    /// Hides the menu bar panel; installed by `StatusItemController`. Used
    /// before presenting windows the panel would otherwise float above.
    @ObservationIgnored var dismissPanel: () -> Void = {}

    private static let selectedDeviceKey = "selectedDeviceID"

    init(demo: DemoScenario? = DemoScenario.current) {
        self.demo = demo
        if let demo {
            Log.remote.info("Demo mode: \(demo.rawValue, privacy: .public)")
            DemoScenario.overrideDefaults()
            let paired = demo.pairedDevices.map(DemoScenario.credentials(for:))
            credentialStore = CredentialStore(backend: DemoCredentialBackend(initial: paired))
            selectedDeviceID = demo.selectedDeviceID
            pairingState = demo.pairingState
            if demo.pairingState == .awaitingPIN { pairingDeviceID = demo.selectedDeviceID }
            screen = demo.screen
        } else {
            credentialStore = CredentialStore()
            selectedDeviceID = UserDefaults.standard.string(forKey: Self.selectedDeviceKey)
        }
        browser.onUpdate = { [weak self] devices in
            self?.devicesDidChange(devices)
        }
    }

    // MARK: - Devices

    /// Online devices merged with paired devices that are not currently visible.
    var devices: [AppleTVDevice] {
        var result = demo?.onlineDevices ?? browser.devices
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
        return credentialStore.credentials(for: device.id) != nil
    }

    /// Menu bar glyph in Resources/StatusIcon: filled while connected,
    /// outlined otherwise.
    var menuBarIconName: String {
        connectionState == .connected ? "Connected" : "Disconnected"
    }

    /// Short state for the selected device's card and header.
    var selectedStateDescription: String {
        guard let device = selectedDevice else { return "" }
        if !isPaired(device) { return device.isOnline ? "Not paired" : "Offline" }
        if !device.isOnline { return "Offline" }
        switch connectionState {
        case .connecting: return "Connecting…"
        case .failed: return "Connection failed"
        case .disconnected: return "Not connected"
        case .connected:
            // "Ready" means connected and the TV is on; only sleep is called out.
            switch powerState.isOn {
            case .some(false): return "Asleep"
            default: return "Ready"
            }
        }
    }

    func start() {
        if demo == nil { browser.start() }
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
        rememberSelection(device.id)
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
            rememberSelection(nil)
        }
    }

    private func devicesDidChange(_ devices: [AppleTVDevice]) {
        adoptCredentialsForRenamedIdentifiers(devices)
        for device in devices {
            credentialStore.updateName(device.name, model: device.model, for: device.id)
        }
        if selectedDeviceID == nil || self.devices.first(where: { $0.id == selectedDeviceID }) == nil {
            let preferred = devices.first { isPaired($0) } ?? devices.first
            if let preferred {
                selectedDeviceID = preferred.id
                rememberSelection(preferred.id)
            }
        }
        connectIfNeeded()
    }

    /// Earlier builds keyed credentials by the rotating `rpBA` address. When an
    /// unpaired device shows up whose name and model match a paired device
    /// that is not on the network, treat them as the same Apple TV.
    private func adoptCredentialsForRenamedIdentifiers(_ devices: [AppleTVDevice]) {
        let onlineIDs = Set(devices.map(\.id))
        for device in devices where credentialStore.credentials(for: device.id) == nil {
            let orphan = credentialStore.credentials.first {
                !onlineIDs.contains($0.deviceID)
                    && $0.deviceName == device.name
                    && ($0.deviceModel == nil || device.model == nil || $0.deviceModel == device.model)
            }
            guard let orphan else { continue }
            credentialStore.rekey(from: orphan.deviceID, to: device.id)
            if selectedDeviceID == orphan.deviceID {
                selectedDeviceID = device.id
                rememberSelection(device.id)
            }
        }
    }

    /// Keeps the selection for the next launch; demo runs leave it alone.
    private func rememberSelection(_ deviceID: String?) {
        guard demo == nil else { return }
        UserDefaults.standard.set(deviceID, forKey: Self.selectedDeviceKey)
    }

    // MARK: - Connection

    /// Called when the menu bar panel opens.
    func panelDidAppear() {
        if demo == nil { browser.start() }
        lastActionError = nil
        connectIfNeeded()
    }

    func connectIfNeeded(isRetry: Bool = false) {
        if let demo {
            connectDemo(demo)
            return
        }
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
                if let session = try? await client.startTextInput() {
                    self.keyboardSession = session
                    self.tvText = session.currentText
                }
                self.refreshApps()
            } catch {
                guard let self, self.client === client else { return }
                Log.remote.error("Connect failed: \(String(describing: error), privacy: .public)")
                self.client = nil
                self.clientDeviceID = nil
                self.connectTask = nil
                // A TV that just dropped another session often ignores the
                // very next connection; one quiet retry covers that.
                if !isRetry, case CompanionError.timeout = error {
                    try? await Task.sleep(for: .seconds(1))
                    self.connectIfNeeded(isRetry: true)
                    return
                }
                self.connectionState = .failed(Self.describe(error))
            }
            self?.connectTask = nil
        }
    }

    /// Stands in for a connection in demo mode: a paired, online TV is ready
    /// at once, with the scenario's power state, apps and text field.
    private func connectDemo(_ demo: DemoScenario) {
        guard connectionState != .connected, let device = selectedDevice, device.isOnline, isPaired(device) else {
            return
        }
        connectionState = .connected
        powerState = demo.powerState
        apps = DemoScenario.apps
        if let session = demo.keyboardSession {
            keyboardSession = session
            tvText = session.currentText
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
        keyboardSession = nil
        tvText = ""
        isMuted = false
    }

    /// Called when the menu bar panel closes.
    func panelDidDisappear() {
        screen = .remote
    }

    /// Esc backs out of Settings first; returns false when the panel should close.
    /// Esc backs out one level: Settings, then an in-progress pairing. Returns
    /// false when there is nothing to back out of, so the panel closes.
    func handleEscape() -> Bool {
        if screen != .remote {
            withAnimation(.snappy(duration: 0.3)) { screen = .remote }
            return true
        }
        if pairingState != .idle {
            cancelPairing()
            return true
        }
        return false
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
                case "_tiStarted":
                    if let payload = event.content["_tiD"]?.dataValue,
                        let session = TextInputArchive.session(from: payload)
                    {
                        self.keyboardSession = session
                        self.tvText = session.currentText
                    }
                case "_tiStopped":
                    self.keyboardSession = nil
                    self.tvText = ""
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
        if command == .volumeUp || command == .volumeDown { isMuted = false }
        Log.remote.info("Press \(command.title, privacy: .public)")
        perform { try await $0.press(command) }
    }

    /// Mutes by remembering the current volume and setting it to zero, since
    /// the Companion button set has no mute. Unmute restores the saved level.
    func toggleMute() {
        if isMuted {
            isMuted = false
            let restore = volumeBeforeMute
            perform { try await $0.setVolume(restore) }
        } else {
            isMuted = true
            perform { [weak self] client in
                let current = try await client.fetchVolume()
                if current > 0 { self?.volumeBeforeMute = current }
                try await client.setVolume(0)
            }
        }
    }

    func buttonDown(_ command: HIDCommand) {
        if command == .volumeUp || command == .volumeDown { isMuted = false }
        Log.remote.info("Down \(command.title, privacy: .public)")
        perform { try await $0.buttonDown(command) }
    }

    func buttonUp(_ command: HIDCommand) {
        Log.remote.info("Up \(command.title, privacy: .public)")
        perform { try await $0.buttonUp(command) }
    }

    /// Mirrors an edit in the panel's text field to the TV. Appending sends
    /// only the new characters; anything else replaces the field.
    func updateTVText(_ newText: String) {
        guard let session = keyboardSession else { return }
        let previous = tvText
        tvText = newText
        guard newText != previous else { return }

        if newText.hasPrefix(previous) {
            let delta = String(newText.dropFirst(previous.count))
            guard !delta.isEmpty else { return }
            perform { try await $0.insertText(delta, session: session) }
        } else {
            perform { client in
                try await client.clearText(session: session)
                if !newText.isEmpty {
                    try await client.insertText(newText, session: session)
                }
            }
        }
    }

    func clearTVText() {
        updateTVText("")
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
                self.isMuted = false
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
        if demo != nil {
            beginDemoPairing()
            return
        }
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
        if demo != nil {
            submitDemoPIN()
            return
        }
        guard let session = pairingSession, let device = selectedDevice, device.id == pairingDeviceID else {
            Log.pairing.info("Ignoring PIN: no pairing in progress for the selected device")
            return
        }
        let digits = pin.filter(\.isNumber)
        guard digits.count == 4 else {
            pairingState = .failed("Enter the four-digit PIN shown on the Apple TV.")
            return
        }
        Log.pairing.info("Submitting PIN to \(device.name, privacy: .public)")
        pairingState = .finishing
        let clientName = IdentityStore.identity().name
        Task { [weak self] in
            do {
                let credentials = try await session.finish(pin: digits, clientName: clientName, device: device)
                guard let self, self.pairingSession === session else { return }
                self.credentialStore.save(credentials)
                self.pairingSession = nil
                self.pairingDeviceID = nil
                self.pairingState = .succeeded
                self.connectIfNeeded()
                try? await Task.sleep(for: .seconds(1.2))
                if self.pairingState == .succeeded { self.pairingState = .idle }
            } catch {
                guard let self, self.pairingSession === session else { return }
                Log.pairing.error("Pair-setup failed: \(String(describing: error), privacy: .public)")
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

    /// Demo pairing: the TV "shows a code" after a second.
    private func beginDemoPairing() {
        guard let device = selectedDevice else { return }
        pairingDeviceID = device.id
        pairingState = .starting
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, self.pairingState == .starting, self.pairingDeviceID == device.id else { return }
            self.pairingState = .awaitingPIN
        }
    }

    /// Demo pairing: any code is accepted, then the usual check and connect.
    private func submitDemoPIN() {
        guard let device = selectedDevice, pairingState == .awaitingPIN else { return }
        pairingState = .finishing
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, self.pairingState == .finishing else { return }
            self.credentialStore.save(DemoScenario.credentials(for: device))
            self.pairingDeviceID = nil
            self.pairingState = .succeeded
            self.connectIfNeeded()
            try? await Task.sleep(for: .seconds(1.2))
            if self.pairingState == .succeeded { self.pairingState = .idle }
        }
    }

    private static func describe(_ error: Error) -> String {
        if let companionError = error as? CompanionError {
            return companionError.localizedDescription
        }
        return error.localizedDescription
    }
}
