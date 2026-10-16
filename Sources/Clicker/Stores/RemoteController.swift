import ClickerCompanion
import Foundation
import Network
import Observation
import SwiftUI

nonisolated enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    var isBusy: Bool { self == .connecting }
}

nonisolated enum PairingState: Equatable, Sendable {
    case idle
    case starting
    case awaitingPIN
    case finishing
    /// Credentials are saved; the card shows a check for a moment before the
    /// remote takes over.
    case succeeded
    case failed(String)
}

/// Where the live Companion session landed: the resolved address and the
/// session id the TV handed back.
nonisolated struct ConnectionInfo: Hashable, Sendable {
    var address: String
    var port: UInt16
    var sessionID: UInt64
    /// The tvOS version from the TV's `_systemInfo` reply, when it sent one.
    var osVersion: String?

    init(address: String, port: UInt16, sessionID: UInt64, osVersion: String? = nil) {
        self.address = address
        self.port = port
        self.sessionID = sessionID
        self.osVersion = osVersion
    }

    /// `nil` when the connection has no resolved host/port endpoint.
    init?(endpoint: NWEndpoint?, sessionID: UInt64, osVersion: String? = nil) {
        guard case .hostPort(let host, let port)? = endpoint else { return nil }
        // IPv6 link-local addresses carry a `%en0` scope; the interface is
        // listed separately.
        let address = String(describing: host).split(separator: "%", maxSplits: 1).first.map(String.init) ?? ""
        self.init(address: address, port: port.rawValue, sessionID: sessionID, osVersion: osVersion)
    }

    var addressDescription: String {
        address.contains(":") ? "[\(address)]:\(port)" : "\(address):\(port)"
    }

    var sessionDescription: String { "0x" + String(sessionID, radix: 16, uppercase: true) }
}

/// Which page the menu bar panel is showing. Settings replaces the remote in
/// place; there is no separate window.
nonisolated enum PanelScreen: Hashable, Sendable {
    case remote
    case settings
}

/// The device picker's popover while it is open: plain, or the ⌥-click
/// details mode. The mode rides on the item because an `isPresented`
/// popover rendered its content with the previous mode when both changed
/// in the same click.
nonisolated struct DevicePickerPresentation: Identifiable, Hashable, Sendable {
    let showsDetails: Bool
    var id: Bool { showsDetails }
}

/// App-wide remote control state: which Apple TV is selected, whether we are
/// connected to it, and the actions the UI can trigger.
@Observable
final class RemoteController {
    let browser = DeviceBrowser()
    let credentialStore: CredentialStore

    private(set) var selectedDeviceID: String?
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var powerState: PowerState = .unknown
    /// Where the live session landed, for the picker's details view.
    private(set) var connectionInfo: ConnectionInfo?
    private(set) var pairingState: PairingState = .idle
    /// Why the selected TV is back to needing a pairing, shown on the pair
    /// card in place of the usual caption. Set when pair-verify finds the TV's
    /// identity changed and the stale credentials were dropped.
    private(set) var pairingNotice: String?
    private(set) var apps: [AppleTVApp] = []
    private(set) var isLoadingApps = false
    /// The selected TV's user profiles, from `refreshUserAccounts`.
    private(set) var userAccounts: [UserAccount] = []
    /// Bundle identifiers of the last few launched apps per TV, newest
    /// first, keyed by device id. Follows the pairing when a TV's id changes
    /// and goes with it when the pairing is forgotten.
    private(set) var recentAppIDsByDevice: [String: [String]] = [:]
    /// Bundle identifiers of the starred apps per TV, in the order they
    /// were starred, keyed by device id. Kept like the recents.
    private(set) var favoriteAppIDsByDevice: [String: [String]] = [:]
    private(set) var lastActionError: String?
    /// Shown when a mute never took effect (HDMI output, see `confirmMute`).
    nonisolated static let muteUnavailableMessage = "This audio output can't be muted."
    /// Non-nil while the Apple TV has a text field focused.
    private(set) var keyboardSession: TextInputArchive.Session?
    /// Our mirror of the text in the TV's focused field.
    private(set) var tvText = ""
    /// Whether the panel shows the TV text field. Set when the TV reports a
    /// focused field and cleared when it loses one; the footer's keyboard
    /// button toggles it by hand in between.
    private(set) var isTextFieldShown = false
    /// Software mute: the volume is set to zero and restored on unmute.
    private(set) var isMuted = false
    /// What the TV's current audio output lets us control, from `_iMC`
    /// events. Empty until the TV sends one after the session starts.
    private(set) var mediaControlFlags: MediaControlFlags = []
    /// Mute sets the volume level, which the Apple TV only owns for a HomePod,
    /// AirPlay or Bluetooth output. Over HDMI the volume buttons still work as
    /// CEC or IR presses, so only Mute is withheld.
    var canMute: Bool { mediaControlFlags.contains(.volume) }
    /// How many `_iMC` events the session has delivered. A real volume change
    /// is followed by one; a placeholder level is not (see `confirmMute`).
    @ObservationIgnored private var mediaControlUpdates = 0
    @ObservationIgnored private var muteConfirmationTask: Task<Void, Never>?
    /// How long a SetVolume gets to be echoed by an `_iMC` event; pyatv waits
    /// the same.
    static let muteConfirmationTimeout: Duration = .seconds(5)
    var screen: PanelScreen = .remote
    /// Whether the Apps picker popover is open. The panel stays the key
    /// window underneath a popover, so the clickpad's shortcuts stand down
    /// while this is set and Esc closes the picker before anything else.
    var isAppPickerPresented = false
    /// The device picker's popover while it is open. Kept here, not in the
    /// view, so hiding the panel can drop it and Esc can close it.
    var devicePickerPresentation: DevicePickerPresentation?
    /// Whether the Settings shortcut row is taking a chord (`ShortcutRow`).
    /// The panel's key monitor leaves every key alone while this is set.
    var isRecordingShortcut = false
    /// Bumped each time the panel opens. Showing the panel clears its first
    /// responder, so the clickpad (or the TV text field) takes keyboard focus
    /// again on every change of this, not only when it first appears.
    private(set) var panelAppearances = 0
    /// Bumped when the clickpad should take keyboard focus even though the
    /// TV text field is showing: Esc in the field gives the keys back to the
    /// remote without hiding the field.
    private(set) var padFocusRequests = 0
    /// Whether the panel is on screen. A session that drops while it is
    /// showing is reconnected once (`scheduleReconnect`); a drop while it is
    /// hidden waits for the next open, which connects anyway.
    private(set) var isPanelVisible = false

    @ObservationIgnored private var client: CompanionClient?
    @ObservationIgnored private var clientDeviceID: String?
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var pairingSession: CompanionPairingSession?
    @ObservationIgnored private var pairingDeviceID: String?
    @ObservationIgnored private var commandQueue: Task<Void, Never>?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    /// How long after a dropped session the panel waits before connecting
    /// again, so a TV that is tearing down (sleep, a restart) is not hit at
    /// once.
    static let reconnectDelay: Duration = .seconds(1)
    @ObservationIgnored private var volumeBeforeMute: Double = 0.5
    /// The pad's keys currently held down on the TV. A key-down sends the
    /// button's down and its key-up the up, so tvOS repeats a held arrow and
    /// long-presses a held Return as it does for the Siri Remote.
    @ObservationIgnored private var heldKeys: Set<HIDCommand> = []
    /// The finger on the TV's touch surface during a trackpad swipe, in
    /// touchpad units; nil between swipes.
    @ObservationIgnored private var touchPosition: CGPoint?
    /// Whether a hold event of the current swipe is already waiting in the
    /// command queue. Trackpads report at up to 120 Hz, so holds are
    /// coalesced: the queued one sends whatever position is current when it
    /// runs. The flag belongs to one swipe: a new press clears it and a
    /// previous swipe's hold leaves it alone when it drains.
    @ObservationIgnored private var touchHoldQueued = false
    /// Holds sent for the current swipe, for the release log line.
    @ObservationIgnored private var touchHolds = 0
    /// Bumped by each press. A queued hold reads the position when it runs,
    /// which may be after the next swipe has begun; it checks this first so
    /// it never sends another gesture's position.
    @ObservationIgnored private var touchGesture = 0
    /// Hides the menu bar panel; installed by `StatusItemController`. Used
    /// before presenting windows the panel would otherwise float above.
    @ObservationIgnored var dismissPanel: () -> Void = {}

    private static let selectedDeviceKey = "selectedDeviceID"
    private static let recentAppsKey = "recentAppIDsByDevice"
    private static let favoriteAppsKey = "favoriteAppIDsByDevice"
    private static let lastAddressesKey = "lastAddressByDevice"
    private static let recentAppLimit = 5

    #if DEMO
        /// Canned state for screenshots (`--demo`); see `DemoScenario`. Debug
        /// builds compile it in; release builds only with `--with-demo`.
        let demo: DemoScenario?
        var isDemo: Bool { demo != nil }

        init(demo: DemoScenario? = DemoScenario.current) {
            self.demo = demo
            if let demo {
                Log.remote.info("Demo mode: \(demo.rawValue, privacy: .public)")
                DemoScenario.overrideDefaults()
                let paired = demo.pairedDevices.map(DemoScenario.credentials(for:))
                credentialStore = CredentialStore(backend: DemoCredentialBackend(initial: paired))
                selectedDeviceID = demo.selectedDeviceID
                pairingState = demo.pairingState
                if demo.pairingState != .idle { pairingDeviceID = demo.selectedDeviceID }
                pairingNotice = demo.pairingNotice
                screen = demo.screen
                if let selected = demo.selectedDeviceID {
                    recentAppIDsByDevice = [selected: DemoScenario.recentAppIDs]
                    favoriteAppIDsByDevice = [selected: DemoScenario.favoriteAppIDs]
                }
            } else {
                credentialStore = CredentialStore()
                restoreSavedState()
            }
            browser.onUpdate = { [weak self] devices in
                self?.devicesDidChange(devices)
            }
        }
    #else
        /// Release builds have no demo mode.
        var isDemo: Bool { false }

        init() {
            credentialStore = CredentialStore()
            restoreSavedState()
            browser.onUpdate = { [weak self] devices in
                self?.devicesDidChange(devices)
            }
        }
    #endif

    /// The selection and per-TV app lists from the last launch.
    private func restoreSavedState() {
        selectedDeviceID = UserDefaults.standard.string(forKey: Self.selectedDeviceKey)
        recentAppIDsByDevice =
            UserDefaults.standard.dictionary(forKey: Self.recentAppsKey) as? [String: [String]] ?? [:]
        favoriteAppIDsByDevice =
            UserDefaults.standard.dictionary(forKey: Self.favoriteAppsKey) as? [String: [String]] ?? [:]
    }

    // MARK: - Devices

    /// Online devices merged with paired devices that are not currently visible, in picker order.
    var devices: [AppleTVDevice] {
        #if DEMO
            var result = demo?.onlineDevices ?? browser.devices
        #else
            var result = browser.devices
        #endif
        let onlineIDs = Set(result.map(\.id))
        for credentials in credentialStore.credentials where !onlineIDs.contains(credentials.deviceID) {
            result.append(AppleTVDevice(offline: credentials))
        }
        return Self.pickerOrder(result, isPaired: isPaired)
    }

    /// Usable TVs first, like the Wi‑Fi menu: paired and online, then paired but offline, then
    /// unpaired, by name within each group. The selected TV is not floated to the top (it already
    /// has the check mark) so the list does not jump when switching.
    nonisolated static func pickerOrder(_ devices: [AppleTVDevice], isPaired: (AppleTVDevice) -> Bool)
        -> [AppleTVDevice]
    {
        func rank(_ device: AppleTVDevice) -> Int {
            guard isPaired(device) else { return 2 }
            return device.isOnline ? 0 : 1
        }
        return devices.sorted { a, b in
            let (ra, rb) = (rank(a), rank(b))
            if ra != rb { return ra < rb }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
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
        if !isDemo { browser.start() }
        connectIfNeeded()
    }

    /// Re-issues the Bonjour query (the picker's ⌥-click Rescan). Also knocks
    /// on the selected TV's last known address, in case it is asleep behind a
    /// Bonjour sleep proxy that wakes it when one of its ports is touched.
    func rescan() {
        guard !isDemo else { return }
        if let selectedDeviceID, let host = lastAddressByDevice[selectedDeviceID] {
            PortKnocker.knock(host: host)
        }
        browser.restart()
    }

    /// The host each TV was last connected at, keyed by device id, so Rescan
    /// can knock on a TV that has dropped out of Bonjour.
    private var lastAddressByDevice: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: Self.lastAddressesKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastAddressesKey) }
    }

    private func rememberAddress(of endpoint: NWEndpoint?, for deviceID: String) {
        guard !isDemo, case .hostPort(let host, _)? = endpoint else { return }
        lastAddressByDevice[deviceID] = String(describing: host)
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
        userAccounts = []
        powerState = .unknown
        lastActionError = nil
        pairingNotice = nil
        connectIfNeeded()
    }

    func forgetPairing(for device: AppleTVDevice) {
        if device.id == clientDeviceID {
            disconnect()
        }
        credentialStore.remove(deviceID: device.id)
        if recentAppIDsByDevice.removeValue(forKey: device.id) != nil { rememberRecents() }
        if favoriteAppIDsByDevice.removeValue(forKey: device.id) != nil { rememberFavorites() }
        lastAddressByDevice[device.id] = nil
        pairingNotice = nil
        if selectedDeviceID == device.id, !device.isOnline {
            // The forgotten TV leaves the list, so move on to another one
            // now rather than sit on the Choose card until Bonjour next
            // reports something.
            selectedDeviceID = nil
            rememberSelection(nil)
            selectPreferredDeviceIfNeeded(online: devices.filter(\.isOnline))
            connectIfNeeded()
        }
    }

    /// Pair-verify found a TV that no longer knows our pairing: its identity
    /// changed (a factory reset) or it refused our identifier (Clicker was
    /// removed from Remotes and Devices). Retrying would fail the same way,
    /// so the stale credentials go and the pair card comes back with the
    /// error's explanation.
    private func dropStalePairing(for device: AppleTVDevice, reason: CompanionError) {
        Log.pairing.info(
            "Pairing with \(device.name, privacy: .public) is stale (\(String(describing: reason), privacy: .public)); dropping it"
        )
        credentialStore.remove(deviceID: device.id)
        if recentAppIDsByDevice.removeValue(forKey: device.id) != nil { rememberRecents() }
        if favoriteAppIDsByDevice.removeValue(forKey: device.id) != nil { rememberFavorites() }
        pairingNotice = reason.localizedDescription
        connectionState = .disconnected
    }

    private func devicesDidChange(_ devices: [AppleTVDevice]) {
        adoptCredentialsForRenamedIdentifiers(devices)
        for device in devices {
            credentialStore.updateName(device.name, model: device.model, for: device.id)
        }
        selectPreferredDeviceIfNeeded(online: devices)
        connectIfNeeded()
    }

    /// Picks a TV when none is selected or the selected one is gone: a
    /// paired one from `online` first, then any.
    private func selectPreferredDeviceIfNeeded(online: [AppleTVDevice]) {
        guard selectedDeviceID == nil || devices.first(where: { $0.id == selectedDeviceID }) == nil else { return }
        guard let preferred = online.first(where: isPaired) ?? online.first else { return }
        selectedDeviceID = preferred.id
        rememberSelection(preferred.id)
    }

    /// Earlier builds keyed credentials by the rotating `rpBA` address. When an
    /// unpaired device shows up whose name and model match a paired device
    /// that is not on the network, treat them as the same Apple TV.
    private func adoptCredentialsForRenamedIdentifiers(_ devices: [AppleTVDevice]) {
        let onlineIDs = Set(devices.map(\.id))
        for device in devices where credentialStore.credentials(for: device.id) == nil {
            let orphan = Self.legacyPairing(for: device, in: credentialStore.credentials, onlineIDs: onlineIDs)
            guard let orphan else { continue }
            credentialStore.rekey(from: orphan.deviceID, to: device.id)
            if let recents = recentAppIDsByDevice.removeValue(forKey: orphan.deviceID) {
                recentAppIDsByDevice[device.id] = recents
                rememberRecents()
            }
            if let favorites = favoriteAppIDsByDevice.removeValue(forKey: orphan.deviceID) {
                favoriteAppIDsByDevice[device.id] = favorites
                rememberFavorites()
            }
            if selectedDeviceID == orphan.deviceID {
                selectedDeviceID = device.id
                rememberSelection(device.id)
            }
        }
    }

    /// The pairing an earlier build saved under `device`'s old `rpBA` key, if any: same name and
    /// model, not on the network, and keyed by something other than an `rpMRtID` UUID. A
    /// UUID-keyed pairing belongs to another Apple TV, such as one with the same name in another
    /// home, and adopting it would hand that TV's keys to this one (pair-verify then fails and
    /// drops them, and the same happens in reverse back home).
    nonisolated static func legacyPairing(
        for device: AppleTVDevice, in credentials: [PairingCredentials], onlineIDs: Set<String>
    ) -> PairingCredentials? {
        credentials.first {
            UUID(uuidString: $0.deviceID) == nil
                && !onlineIDs.contains($0.deviceID)
                && $0.deviceName == device.name
                && ($0.deviceModel == nil || device.model == nil || $0.deviceModel == device.model)
        }
    }

    /// Keeps the selection for the next launch; demo runs leave it alone.
    private func rememberSelection(_ deviceID: String?) {
        guard !isDemo else { return }
        UserDefaults.standard.set(deviceID, forKey: Self.selectedDeviceKey)
    }

    // MARK: - Connection

    /// Called when the menu bar panel opens.
    func panelDidAppear() {
        if !isDemo { browser.start() }
        isPanelVisible = true
        lastActionError = nil
        panelAppearances += 1
        connectIfNeeded()
    }

    /// TCP connect limits. A connect on this network lands in about two
    /// seconds, and the attempt that follows a dropped session tends to get
    /// no answer at all, so the first try gives up early and the retry
    /// waits the full ten.
    static let firstConnectTimeout: Duration = .seconds(5)
    static let retryConnectTimeout: Duration = .seconds(10)

    func connectIfNeeded(isRetry: Bool = false) {
        #if DEMO
            if let demo {
                connectDemo(demo)
                return
            }
        #endif
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
                try await client.connect(timeout: isRetry ? Self.retryConnectTimeout : Self.firstConnectTimeout)
                guard let self, self.client === client else {
                    await client.disconnect()
                    return
                }
                self.connectionState = .connected
                let endpoint = await client.remoteEndpoint
                let sessionID = await client.sessionID
                let osVersion = await client.osVersion
                // A select during those hops tears this session down and
                // starts another; its details and events are not ours to
                // install then.
                guard self.client === client else { return }
                self.connectionInfo = ConnectionInfo(endpoint: endpoint, sessionID: sessionID, osVersion: osVersion)
                self.rememberAddress(of: endpoint, for: device.id)
                self.listenForEvents(from: client)
                if let state = try? await client.fetchPowerState() {
                    self.powerState = state
                }
                if let session = try? await client.startTextInput() {
                    self.adoptKeyboardSession(session)
                }
                // The session may have been torn down during the requests
                // above; a newer connect task would then own `connectTask`.
                guard self.client === client else { return }
                self.connectTask = nil
                self.refreshApps()
            } catch {
                guard let self, self.client === client else { return }
                Log.remote.error("Connect failed: \(String(describing: error), privacy: .public)")
                self.client = nil
                self.clientDeviceID = nil
                // A TV that just dropped another session often ignores the
                // very next connection; one quiet retry covers that. The task
                // stays in `connectTask` through the pause: `tearDownSession`
                // cancels it there, so a select or a Forget is not followed
                // by a stale attempt, and a queued command keeps waiting.
                if !isRetry, case CompanionError.timeout = error {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    self.connectTask = nil
                    self.connectIfNeeded(isRetry: true)
                    return
                }
                self.connectTask = nil
                if let reason = error as? CompanionError {
                    switch reason {
                    case .identityChanged, .pairingLost:
                        self.dropStalePairing(for: device, reason: reason)
                        return
                    default:
                        break
                    }
                }
                // The TV never answered: name it, since the protocol's wording
                // cannot. Other failures keep their more specific message.
                switch error {
                case CompanionError.connectionFailed, CompanionError.timeout:
                    self.connectionState = .failed(Self.connectFailedMessage(device.name))
                default:
                    self.connectionState = .failed(error.localizedDescription)
                }
            }
        }
    }

    func retryConnection() {
        disconnect()
        connectIfNeeded()
    }

    func disconnect() {
        if let client = tearDownSession() {
            Task { await client.disconnect() }
        }
    }

    /// `disconnect`, but waited for: the TV gets its `_sessionStop` before
    /// the app quits, instead of a dead TCP connection to notice later. A
    /// TV that does not answer within `limit` is not allowed to hold the
    /// quit.
    func shutdown(within limit: Duration) async {
        guard let client = tearDownSession() else { return }
        // The first child to finish wins; cancelling the other makes a
        // disconnect still waiting on the TV give up at once.
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await client.disconnect()
                return true
            }
            group.addTask {
                try? await Task.sleep(for: limit)
                return false
            }
            if await group.next() == false {
                Log.connection.info("Quit without waiting for the TV to acknowledge the session's end")
            }
            group.cancelAll()
        }
    }

    /// Whether a session is open or opening, for the quit handler.
    var hasSession: Bool { client != nil }

    /// Clears every piece of session state and hands back the client that
    /// still needs closing, if any.
    private func tearDownSession() -> CompanionClient? {
        reconnectTask?.cancel()
        reconnectTask = nil
        connectTask?.cancel()
        connectTask = nil
        eventTask?.cancel()
        eventTask = nil
        let client = client
        self.client = nil
        clientDeviceID = nil
        connectionState = .disconnected
        powerState = .unknown
        connectionInfo = nil
        keyboardSession = nil
        tvText = ""
        isTextFieldShown = false
        isMuted = false
        mediaControlFlags = []
        muteConfirmationTask?.cancel()
        muteConfirmationTask = nil
        // The session is gone, so a release could only trigger a reconnect;
        // the hold flag is the next press's to clear.
        touchPosition = nil
        heldKeys = []
        return client
    }

    /// One connection attempt a moment after the TV dropped the session
    /// while the panel was open; otherwise the panel sat on "Not connected"
    /// until a click. The attempt has its own retry, and a failure leaves
    /// the banner's Retry as before.
    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: Self.reconnectDelay)
            guard !Task.isCancelled, let self, self.isPanelVisible, self.connectionState == .disconnected else {
                return
            }
            Log.remote.info("Reconnecting after the session dropped")
            self.connectIfNeeded()
        }
    }

    /// Called when the menu bar panel closes.
    func panelDidDisappear() {
        isPanelVisible = false
        screen = .remote
        // A swipe in progress loses its end event with the panel (the pad
        // stays loaded, so the monitor never sees it disappear), so lift the
        // TV's finger here rather than leave it down until the next swipe.
        if let point = touchPosition {
            handleTrackpadSwipe(.touchUp(point))
        }
        // Likewise a held key's key-up goes nowhere once the panel is hidden.
        releaseHeldKeys()
        // The popovers go with the panel; their state must follow or the
        // clickpad stays unfocused (Apps) or the device list pops back up
        // the next time the panel opens.
        isAppPickerPresented = false
        devicePickerPresentation = nil
        isRecordingShortcut = false
    }

    /// Esc backs out one level: an open popover (Apps or the device list),
    /// then Settings, then an in-progress pairing. Returns false when there
    /// is nothing to back out of, so the panel closes.
    func handleEscape() -> Bool {
        if isAppPickerPresented {
            isAppPickerPresented = false
            return true
        }
        if devicePickerPresentation != nil {
            devicePickerPresentation = nil
            return true
        }
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
                        self.adoptKeyboardSession(session)
                    }
                case "_tiStopped":
                    self.keyboardSession = nil
                    self.tvText = ""
                    self.isTextFieldShown = false
                case "_iMC":
                    if let flags = MediaControlFlags(eventContent: event.content) {
                        self.mediaControlUpdates += 1
                        self.mediaControlFlags = flags
                        let names = flags.descriptions.joined(separator: ", ")
                        Log.remote.info("Media controls: \(names, privacy: .public)")
                        // An output change loses the level we would restore.
                        if !flags.contains(.volume) { self.isMuted = false }
                    }
                default:
                    break
                }
            }
            guard let self, self.client === client else { return }
            // The stream ends when the connection closes: drop everything
            // that belonged to the session (text field, mute, media flags),
            // not just the client, so the panel does not keep showing them.
            self.disconnect()
            if self.isPanelVisible { self.scheduleReconnect() }
        }
    }

    // MARK: - Actions

    func press(_ command: HIDCommand) {
        if command == .volumeUp || command == .volumeDown { isMuted = false }
        Log.remote.info("Press \(command.title, privacy: .public)")
        perform { try await $0.press(command) }
    }

    /// Sends a media-control command to the TV's current player.
    func mediaControl(_ command: CompanionClient.MediaControlCommand) {
        Log.remote.info("Media control \(String(describing: command), privacy: .public)")
        perform { try await $0.mediaControl(command) }
    }

    /// Skips the current item by `seconds`, backward when negative.
    func skip(by seconds: Double) {
        Log.remote.info("Skip by \(seconds, privacy: .public)s")
        perform { try await $0.skip(by: seconds) }
    }

    /// Swipes across the TV's touch surface; points are in touchpad units
    /// (0...1000 on each axis, origin top left).
    func swipe(from start: CGPoint, to end: CGPoint, duration: Duration = .milliseconds(200)) {
        Log.remote.info(
            "Swipe \(start.x, privacy: .public),\(start.y, privacy: .public) to \(end.x, privacy: .public),\(end.y, privacy: .public)"
        )
        perform { try await $0.swipe(from: start, to: end, duration: duration) }
    }

    /// A two-finger scroll over the clickpad, already translated into a touch
    /// on the TV's surface by `TrackpadSwipe`. Press and release go out as
    /// they come; holds are coalesced to one in flight at a time so a long
    /// swipe neither floods the TV nor holds up a click behind it.
    func handleTrackpadSwipe(_ action: TrackpadSwipe.Action) {
        switch action {
        case .touchDown(let point):
            // A press still outstanding means the previous swipe's end was
            // lost; lift it first so the TV never sees two fingers.
            if let previous = touchPosition {
                handleTrackpadSwipe(.touchUp(previous))
            }
            Log.remote.info("Touch down at \(Int(point.x), privacy: .public),\(Int(point.y), privacy: .public)")
            touchPosition = point
            touchHolds = 0
            touchGesture += 1
            touchHoldQueued = false
            perform { try await $0.touch(x: point.x, y: point.y, phase: .press) }
        case .touchMove(let point):
            // Moves and releases only mean something while a press is out;
            // after a disconnect or a release the TV has no finger to move.
            guard touchPosition != nil else { return }
            touchPosition = point
            guard !touchHoldQueued else { return }
            touchHoldQueued = true
            touchHolds += 1
            let gesture = touchGesture
            perform { [weak self] client in
                guard let self, self.touchGesture == gesture, let point = self.touchPosition else { return }
                try await client.touch(x: point.x, y: point.y, phase: .hold)
            } completion: { [weak self] in
                guard let self, self.touchGesture == gesture else { return }
                self.touchHoldQueued = false
            }
        case .touchUp(let point):
            guard touchPosition != nil else { return }
            Log.remote.info(
                "Touch up at \(Int(point.x), privacy: .public),\(Int(point.y), privacy: .public) after \(self.touchHolds, privacy: .public) holds"
            )
            touchPosition = nil
            perform { try await $0.touch(x: point.x, y: point.y, phase: .release) }
        }
    }

    /// Mutes by remembering the current volume and setting it to zero, since
    /// the Companion button set has no mute. Unmute restores the saved level.
    func toggleMute() {
        guard canMute else { return }
        if isMuted {
            Log.remote.info("Unmute")
            isMuted = false
            let restore = volumeBeforeMute
            perform { try await $0.setVolume(restore) }
        } else {
            Log.remote.info("Mute")
            isMuted = true
            let updatesBefore = mediaControlUpdates
            perform { [weak self] client in
                do {
                    let current = try await client.fetchVolume()
                    Log.remote.info("Volume before mute: \(current, privacy: .public)")
                    if current > 0 { self?.volumeBeforeMute = current }
                    try await client.setVolume(0)
                } catch {
                    // The TV's level is unchanged, so the segment must not
                    // stay tinted; only this action resets it, not every
                    // failed command.
                    self?.isMuted = false
                    throw error
                }
            } completion: { [weak self] in
                self?.confirmMute(updatesSince: updatesBefore)
            }
        }
    }

    /// Waits for the `_iMC` event a real volume change produces. tvOS 27 over
    /// HDMI advertises volume control, answers GetVolume with a constant 0.5
    /// and echoes SetVolume back, but changes nothing and sends no event, so
    /// after the timeout the mute is undone and withheld like an output that
    /// never claimed it. A later `_iMC` with the volume bit re-enables it.
    private func confirmMute(updatesSince: Int) {
        guard !isDemo, isMuted, lastActionError == nil else { return }
        muteConfirmationTask?.cancel()
        muteConfirmationTask = Task { [weak self] in
            try? await Task.sleep(for: Self.muteConfirmationTimeout)
            guard !Task.isCancelled, let self, self.isMuted, self.mediaControlUpdates == updatesSince else { return }
            self.abandonMute()
        }
    }

    /// Undoes a mute the TV only pretended to apply and disables Mute.
    func abandonMute() {
        Log.remote.info("No volume update after SetVolume; treating the level as a placeholder")
        isMuted = false
        mediaControlFlags.remove(.volume)
        let restore = volumeBeforeMute
        // The notice goes up after the restore, which would otherwise clear it.
        perform {
            try await $0.setVolume(restore)
        } completion: { [weak self] in
            self?.lastActionError = Self.muteUnavailableMessage
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

    /// A pad key went down. The Mac's key repeats never get here: tvOS
    /// repeats a held button itself, and a press per repeat would queue up
    /// behind the command queue and keep moving focus after the key is let go.
    func keyDown(_ command: HIDCommand) {
        guard heldKeys.insert(command).inserted else { return }
        buttonDown(command)
    }

    func keyUp(_ command: HIDCommand) {
        guard heldKeys.remove(command) != nil else { return }
        buttonUp(command)
    }

    /// Lets go of every held key. For when the pad stops receiving key-ups:
    /// the panel hid, or focus moved to the text field or the Apps picker.
    func releaseHeldKeys() {
        let held = heldKeys
        heldKeys = []
        for command in held { buttonUp(command) }
    }

    private func adoptKeyboardSession(_ session: TextInputArchive.Session) {
        keyboardSession = session
        tvText = session.currentText
        isTextFieldShown = true
    }

    /// The footer's keyboard button: hides or re-shows the text field while
    /// the TV has a field focused. Without a session there is nothing to type
    /// into, so the button is disabled and this does nothing.
    func toggleTextField() {
        guard keyboardSession != nil else { return }
        isTextFieldShown.toggle()
    }

    /// Hands keyboard focus to the clickpad (see `padFocusRequests`).
    func focusPad() {
        padFocusRequests += 1
    }

    /// Mirrors an edit in the panel's text field to the TV. Appending sends
    /// only the new characters; anything else replaces the field in one
    /// event, so the TV never shows an empty field in between.
    func updateTVText(_ newText: String) {
        guard let session = keyboardSession else { return }
        let previous = tvText
        tvText = newText
        guard newText != previous else { return }

        if newText.hasPrefix(previous) {
            let delta = String(newText.dropFirst(previous.count))
            guard !delta.isEmpty else { return }
            Log.remote.info("Insert \(delta.count) character(s) into TV field")
            perform { try await $0.insertText(delta, session: session) }
        } else if newText.isEmpty {
            Log.remote.info("Clear TV field")
            perform { try await $0.clearText(session: session) }
        } else {
            Log.remote.info("Replace TV field with \(newText.count) character(s)")
            perform { try await $0.replaceText(newText, session: session) }
        }
    }

    func clearTVText() {
        updateTVText("")
    }

    /// Sends Return to the TV's field as a newline insertion, the way a
    /// hardware keyboard's Return reaches a UIKit text field. tvOS 27 treats
    /// it as Done (the Search app ran the search and sent `_tiStopped`); the
    /// panel's text is left alone so typing can continue if a field ignores it.
    func submitTVText() {
        guard let session = keyboardSession else { return }
        Log.remote.info("Return to TV field")
        perform { try await $0.insertText("\n", session: session) }
    }

    func launch(_ app: AppleTVApp) {
        noteLaunch(app)
        perform { try await $0.launchApp(bundleIdentifier: app.bundleIdentifier) }
    }

    /// The current TV's recently launched apps, newest first; an app it no
    /// longer has is skipped.
    var recentApps: [AppleTVApp] {
        guard let selectedDeviceID, let ids = recentAppIDsByDevice[selectedDeviceID] else { return [] }
        return ids.compactMap { id in apps.first { $0.id == id } }
    }

    private func noteLaunch(_ app: AppleTVApp) {
        guard let selectedDeviceID else { return }
        var ids = recentAppIDsByDevice[selectedDeviceID] ?? []
        ids.removeAll { $0 == app.id }
        ids.insert(app.id, at: 0)
        if ids.count > Self.recentAppLimit { ids.removeLast(ids.count - Self.recentAppLimit) }
        recentAppIDsByDevice[selectedDeviceID] = ids
        rememberRecents()
    }

    /// Empties the current TV's Recent group.
    func clearRecents() {
        guard let selectedDeviceID, recentAppIDsByDevice.removeValue(forKey: selectedDeviceID) != nil else { return }
        rememberRecents()
    }

    private func rememberRecents() {
        guard !isDemo else { return }
        UserDefaults.standard.set(recentAppIDsByDevice, forKey: Self.recentAppsKey)
    }

    /// The current TV's starred apps, in the order they were starred; an
    /// app it no longer has is skipped.
    var favoriteApps: [AppleTVApp] {
        guard let selectedDeviceID, let ids = favoriteAppIDsByDevice[selectedDeviceID] else { return [] }
        return ids.compactMap { id in apps.first { $0.id == id } }
    }

    func isFavorite(_ app: AppleTVApp) -> Bool {
        guard let selectedDeviceID else { return false }
        return favoriteAppIDsByDevice[selectedDeviceID]?.contains(app.id) ?? false
    }

    /// Stars or unstars an app on the current TV.
    func toggleFavorite(_ app: AppleTVApp) {
        guard let selectedDeviceID else { return }
        var ids = favoriteAppIDsByDevice[selectedDeviceID] ?? []
        if let index = ids.firstIndex(of: app.id) {
            ids.remove(at: index)
        } else {
            ids.append(app.id)
        }
        favoriteAppIDsByDevice[selectedDeviceID] = ids.isEmpty ? nil : ids
        rememberFavorites()
    }

    private func rememberFavorites() {
        guard !isDemo else { return }
        UserDefaults.standard.set(favoriteAppIDsByDevice, forKey: Self.favoriteAppsKey)
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

    func refreshUserAccounts() {
        perform { [weak self] client in
            let accounts = try await client.fetchUserAccounts()
            self?.userAccounts = accounts
        }
    }

    func switchUserAccount(_ account: UserAccount) {
        Log.remote.info("Switch user to \(account.name, privacy: .public)")
        perform { try await $0.switchUserAccount(id: account.id) }
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
                self.lastActionError = error.localizedDescription
                switch error {
                case CompanionError.disconnected, CompanionError.notConnected:
                    self.disconnect()
                default:
                    break
                }
            }
        }
    }

    /// Returns a connected client, connecting first when necessary. Waits
    /// through every attempt in flight: a timed-out first attempt hands off
    /// to its retry before it finishes, so waiting on one task alone woke up
    /// mid-retry and dropped the command without a word. A failed attempt
    /// is not repeated per command: the banner's Retry, the next panel open
    /// and `scheduleReconnect` reconnect, and a queue of presses would
    /// otherwise run one full attempt each and replay once the TV answered.
    private func readyClient() async -> CompanionClient? {
        if connectTask == nil, case .failed = connectionState { return nil }
        connectIfNeeded()
        while let task = connectTask {
            await task.value
            // Every attempt clears its own slot; this only guards the loop
            // against one that returns early without doing so.
            if connectTask == task { connectTask = nil }
        }
        guard connectionState == .connected, let client else { return nil }
        return client
    }

    // MARK: - Pairing

    func beginPairing() {
        #if DEMO
            if isDemo {
                beginDemoPairing()
                return
            }
        #endif
        guard let device = selectedDevice, let endpoint = device.endpoint else { return }
        guard !device.pairingDisabled else {
            pairingState = .failed(CompanionError.pairingDisabled.localizedDescription)
            return
        }
        cancelPairing()
        disconnect()
        pairingNotice = nil
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
                // Close the connection even if nobody is waiting on it any
                // more; a pair-setup that failed after the TCP connect would
                // otherwise stay open until the TV drops it.
                await session.cancel()
                guard let self, self.pairingSession === session else { return }
                self.pairingState = .failed(error.localizedDescription)
                self.pairingSession = nil
            }
        }
    }

    func submitPIN(_ pin: String) {
        #if DEMO
            if isDemo {
                submitDemoPIN()
                return
            }
        #endif
        guard let session = pairingSession, let device = selectedDevice, device.id == pairingDeviceID else {
            Log.pairing.info("Ignoring PIN: no pairing in progress for the selected device")
            return
        }
        let digits = pin.filter(\.isNumber)
        guard digits.count == 4 else {
            pairingState = .failed("Enter the four-digit code shown on the Apple TV.")
            return
        }
        Log.pairing.info("Submitting PIN to \(device.name, privacy: .public)")
        pairingState = .finishing
        let clientName = IdentityStore.identity().name
        Task { [weak self] in
            do {
                let credentials = try await session.finish(
                    pin: digits, clientName: clientName, deviceID: device.id, deviceName: device.name,
                    deviceModel: device.model)
                guard let self, self.pairingSession === session else { return }
                do {
                    try self.credentialStore.save(credentials)
                } catch {
                    // The TV now trusts us but nothing survives a relaunch;
                    // say so instead of showing a check that lies.
                    Log.pairing.error("Paired but could not save: \(String(describing: error), privacy: .public)")
                    await session.cancel()
                    self.pairingSession = nil
                    self.pairingDeviceID = nil
                    self.pairingState = .failed(Self.pairingNotSavedMessage(error.localizedDescription))
                    return
                }
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
                self.pairingState = .failed(error.localizedDescription)
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

    /// The pair card's message when the TV accepted the pairing but the
    /// credentials could not be stored (`--demo savefailed`).
    nonisolated static func pairingNotSavedMessage(_ reason: String) -> String {
        "Paired, but the pairing couldn't be saved: \(reason)"
    }

    nonisolated static func connectFailedMessage(_ deviceName: String) -> String {
        "Couldn't connect to \(deviceName)."
    }
}

#if DEMO
    // MARK: - Demo

    extension RemoteController {
        /// Stands in for a connection in demo mode: a paired, online TV is ready
        /// at once, with the scenario's power state, apps and text field.
        private func connectDemo(_ demo: DemoScenario) {
            guard let device = selectedDevice, device.isOnline, isPaired(device) else { return }
            // Re-applied on every panel open, which clears the notice first.
            lastActionError = demo.actionError
            guard connectionState != .connected else { return }
            connectionState = demo.connectionState
            guard connectionState == .connected else { return }
            powerState = demo.powerState
            mediaControlFlags = demo.mediaControlFlags
            connectionInfo = ConnectionInfo(
                address: "192.168.1.42", port: 49153, sessionID: 0x5C1A_7E2B, osVersion: "26.0.1")
            apps = DemoScenario.apps
            if let session = demo.keyboardSession {
                adoptKeyboardSession(session)
            }
        }

        /// Demo pairing: the TV "shows a code" after a second.
        private func beginDemoPairing() {
            guard let device = selectedDevice else { return }
            pairingDeviceID = device.id
            pairingState = .starting
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.pairingState == .starting, self.pairingDeviceID == device.id else {
                    return
                }
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
                try? self.credentialStore.save(DemoScenario.credentials(for: device))
                self.pairingDeviceID = nil
                self.pairingState = .succeeded
                self.connectIfNeeded()
                try? await Task.sleep(for: .seconds(1.2))
                if self.pairingState == .succeeded { self.pairingState = .idle }
            }
        }
    }
#endif
