import Foundation
import Network

/// High-level remote control session with one Apple TV: connects, verifies the
/// pairing, registers the session the way the iOS Remote does, and exposes
/// button, app and power commands.
actor CompanionClient {
    let credentials: PairingCredentials
    let identity: ClientIdentity
    private let connection: CompanionConnection
    private(set) var sessionID: UInt64 = 0
    /// The TV's half of the `_systemInfo` exchange, kept for the details view.
    private(set) var deviceSystemInfo: [String: OPACKValue] = [:]

    /// The tvOS version the TV reported in its `_systemInfo` reply (`_osV`).
    var osVersion: String? { deviceSystemInfo["_osV"]?.stringValue }

    nonisolated var events: AsyncStream<CompanionEvent> { connection.events }

    init(endpoint: NWEndpoint, credentials: PairingCredentials, identity: ClientIdentity) {
        self.credentials = credentials
        self.identity = identity
        self.connection = CompanionConnection(endpoint: endpoint)
    }

    var isConnected: Bool {
        get async { await connection.isConnected }
    }

    var remoteEndpoint: NWEndpoint? {
        get async { await connection.remoteEndpoint }
    }

    func connect() async throws {
        do {
            try await connection.connect()
            try await CompanionPairing.verify(on: connection, credentials: credentials)
            try await sendSystemInfo()
            try await startSession()
            // Newer tvOS wants a TV Remote Client session before answering some
            // requests; older versions do not implement it, so failure is fine.
            _ = try? await request("TVRCSessionStart", ["ProtocolVersionKey": "1.2"])
            // `_iMC` carries the media-control flags (`_mcF`); the TV sends one
            // on subscription and again whenever its audio output changes.
            try await subscribe(to: ["TVSystemStatus", "SystemStatus", "_iMC"])
        } catch {
            // A failed pair-verify or session setup would otherwise leave the
            // TCP connection open (its receive loop keeps it alive) until the
            // TV drops it.
            await connection.close()
            throw error
        }
    }

    func disconnect() async {
        _ = try? await request("_tiStop", [:], timeout: 1)
        if touchStartedAt != nil {
            _ = try? await request("_touchStop", ["_i": 1], timeout: 1)
        }
        if sessionID != 0 {
            _ = try? await request(
                "_sessionStop",
                ["_srvT": "com.apple.tvremoteservices", "_sid": .int(Int64(bitPattern: sessionID))],
                timeout: 1
            )
        }
        await connection.close()
    }

    // MARK: - Buttons

    func press(_ command: HIDCommand) async throws {
        try await buttonDown(command)
        try await buttonUp(command)
    }

    func buttonDown(_ command: HIDCommand) async throws {
        _ = try await request("_hidC", ["_hBtS": 1, "_hidC": .int(command.rawValue)])
    }

    func buttonUp(_ command: HIDCommand) async throws {
        _ = try await request("_hidC", ["_hBtS": 2, "_hidC": .int(command.rawValue)])
    }

    // MARK: - Media control

    /// Media-control commands sent as `_mcc`, numbered as in pyatv. They act on
    /// the TV's current player; `MediaControlFlags` says which it accepts.
    /// Caption settings (12, 13) are listed for completeness only: pyatv never
    /// sends them, so their payload is unknown.
    enum MediaControlCommand: Int64, Sendable {
        case play = 1
        case pause = 2
        case nextTrack = 3
        case previousTrack = 4
        case getVolume = 5
        case setVolume = 6
        case skipBy = 7
        case fastForwardBegin = 8
        case fastForwardEnd = 9
        case rewindBegin = 10
        case rewindEnd = 11
        case getCaptionSettings = 12
        case setCaptionSettings = 13
    }

    /// Sends a media-control command that takes no arguments (play, pause,
    /// next/previous track, and the begin/end halves of fast forward and rewind).
    func mediaControl(_ command: MediaControlCommand) async throws {
        _ = try await request("_mcc", ["_mcc": .int(command.rawValue)])
    }

    /// Skips the current item by `seconds`, backward when negative. Sent as a
    /// double: pyatv notes that negative OPACK integers are rejected.
    func skip(by seconds: Double) async throws {
        _ = try await request(
            "_mcc",
            [
                "_mcc": .int(MediaControlCommand.skipBy.rawValue),
                "_skpS": .double(seconds),
            ])
    }

    /// Current output volume in 0...1. Only meaningful while the TV's media
    /// control flags include `.volume`; over plain HDMI the request fails or
    /// comes back without a level.
    func fetchVolume() async throws -> Double {
        let response = try await request("_mcc", ["_mcc": .int(MediaControlCommand.getVolume.rawValue)])
        guard let volume = response["_c"]?["_vol"]?.doubleValue else {
            throw CompanionError.unexpectedResponse("volume missing")
        }
        return volume
    }

    func setVolume(_ volume: Double) async throws {
        let response = try await request(
            "_mcc",
            [
                "_mcc": .int(MediaControlCommand.setVolume.rawValue),
                "_vol": .double(min(max(volume, 0), 1)),
            ])
        Log.remote.info(
            "SetVolume \(volume, privacy: .public) reply: \(String(describing: response), privacy: .public)")
    }

    // MARK: - Apps

    func fetchApps() async throws -> [AppleTVApp] {
        let response = try await request("FetchLaunchableApplicationsEvent", [:], timeout: 10)
        guard let content = response["_c"]?.stringKeyedDictionary else {
            throw CompanionError.unexpectedResponse("app list missing content")
        }
        return content.compactMap { bundleIdentifier, value in
            guard let name = value.stringValue else { return nil }
            return AppleTVApp(bundleIdentifier: bundleIdentifier, name: name)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func launchApp(bundleIdentifier: String) async throws {
        _ = try await request("_launchApp", ["_bundleID": .string(bundleIdentifier)])
    }

    // MARK: - User accounts

    /// The tvOS user profiles that can be switched to, by name.
    func fetchUserAccounts() async throws -> [UserAccount] {
        let response = try await request("FetchUserAccountsEvent", [:])
        guard let content = response["_c"]?.stringKeyedDictionary else {
            throw CompanionError.unexpectedResponse("account list missing content")
        }
        return content.compactMap { identifier, value in
            guard let name = value.stringValue else { return nil }
            return UserAccount(id: identifier, name: name)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func switchUserAccount(id: String) async throws {
        _ = try await request("SwitchUserAccountEvent", ["SwitchAccountID": .string(id)])
    }

    // MARK: - Touch

    /// Side of the virtual touchpad in the TV's units; coordinates run 0...1000.
    static let touchpadSize = 1000.0
    /// pyatv's spacing between the hold events of a swipe.
    static let touchInterval: Duration = .milliseconds(16)

    /// Set by `_touchStart`; touch events carry nanoseconds since then.
    private var touchStartedAt: ContinuousClock.Instant?

    /// Sends one touch event at `x`, `y` (0...1000), opening the touch
    /// session on first use. pyatv opens it on every connect; doing it lazily
    /// keeps sessions that never touch the same as before.
    func touch(x: Double, y: Double, phase: TouchPhase) async throws {
        let startedAt = try await startTouchIfNeeded()
        let elapsed = ContinuousClock.now - startedAt
        let nanoseconds = elapsed.components.seconds * 1_000_000_000 + elapsed.components.attoseconds / 1_000_000_000
        let size = Self.touchpadSize
        try await sendEvent(
            "_hidT",
            [
                "_ns": .int(nanoseconds),
                "_tFg": 1,
                "_cx": .int(Int64(min(max(x, 0), size))),
                "_cy": .int(Int64(min(max(y, 0), size))),
                "_tPh": .int(phase.rawValue),
            ])
    }

    /// Drags a finger from `start` to `end` (touchpad units) over `duration`,
    /// as pyatv's `swipe` does: a press, hold events every 16 ms, a release.
    /// tvOS reads a 600-unit drag over 200 ms as a flick with momentum: on
    /// the Home Screen it moved focus two or three tiles, not one.
    func swipe(from start: CGPoint, to end: CGPoint, duration: Duration) async throws {
        let clock = ContinuousClock()
        let startedAt = clock.now
        try await touch(x: start.x, y: start.y, phase: .press)
        while true {
            let progress = (clock.now - startedAt) / duration
            guard progress < 1 else { break }
            let x = start.x + (end.x - start.x) * progress
            let y = start.y + (end.y - start.y) * progress
            try await touch(x: x, y: y, phase: .hold)
            try await Task.sleep(for: Self.touchInterval)
        }
        try await touch(x: end.x, y: end.y, phase: .release)
    }

    private func startTouchIfNeeded() async throws -> ContinuousClock.Instant {
        if let touchStartedAt { return touchStartedAt }
        _ = try await request(
            "_touchStart",
            ["_height": .double(Self.touchpadSize), "_tFl": 0, "_width": .double(Self.touchpadSize)])
        let now = ContinuousClock.now
        touchStartedAt = now
        return now
    }

    // MARK: - Text input

    /// Opens a text-input session. Returns the TV's current field when a
    /// keyboard is on screen, `nil` otherwise; the TV then pushes
    /// `_tiStarted` / `_tiStopped` events as focus changes.
    func startTextInput() async throws -> TextInputArchive.Session? {
        let response = try await request("_tiStart", [:])
        guard let payload = response["_c"]?["_tiD"]?.dataValue else { return nil }
        return TextInputArchive.session(from: payload)
    }

    func stopTextInput() async throws {
        _ = try await request("_tiStop", [:])
    }

    func insertText(_ text: String, session: TextInputArchive.Session) async throws {
        try await sendEvent(
            "_tiC",
            [
                "_tiV": 1,
                "_tiD": .data(TextInputArchive.insertTextPayload(sessionUUID: session.sessionUUID, text: text)),
            ])
    }

    func clearText(session: TextInputArchive.Session) async throws {
        try await sendEvent(
            "_tiC",
            [
                "_tiV": 1,
                "_tiD": .data(TextInputArchive.clearTextPayload(sessionUUID: session.sessionUUID)),
            ])
    }

    /// Replaces the field's contents in one event; see `TextInputArchive.replaceTextPayload`.
    func replaceText(_ text: String, session: TextInputArchive.Session) async throws {
        try await sendEvent(
            "_tiC",
            [
                "_tiV": 1,
                "_tiD": .data(TextInputArchive.replaceTextPayload(sessionUUID: session.sessionUUID, text: text)),
            ])
    }

    // MARK: - Power

    /// Not implemented on recent tvOS; callers should fall back to pushed events.
    func fetchPowerState() async throws -> PowerState {
        let response = try await request("FetchAttentionState", [:])
        guard let state = response["_c"]?["state"]?.intValue else {
            throw CompanionError.unexpectedResponse("attention state missing")
        }
        return PowerState(rawValue: state) ?? .unknown
    }

    // MARK: - Session setup

    /// Introduces this client; the TV answers with its own description, which
    /// includes its OS version under `_osV`.
    private func sendSystemInfo() async throws {
        let response = try await request(
            "_systemInfo",
            [
                "_bf": 0,
                "_cf": 512,
                "_clFl": 128,
                "_i": .string(identity.deviceID.replacingOccurrences(of: ":", with: "").lowercased()),
                "_idsID": .data(Data(credentials.clientIdentifier.utf8)),
                "_pubID": .string(identity.deviceID),
                "_sf": 256,
                "_sv": "170.18",
                "model": "iPhone14,3",
                "name": .string(identity.name),
            ])
        deviceSystemInfo = response["_c"]?.stringKeyedDictionary ?? [:]
        let keys = deviceSystemInfo.keys.sorted().joined(separator: " ")
        let version = osVersion ?? "?"
        Log.connection.info("System info reply: \(keys, privacy: .public); tvOS \(version, privacy: .public)")
    }

    private func startSession() async throws {
        let localID = UInt32.random(in: 0...UInt32.max)
        let response = try await request(
            "_sessionStart",
            ["_srvT": "com.apple.tvremoteservices", "_sid": .int(Int64(localID))]
        )
        guard let remoteID = response["_c"]?["_sid"]?.intValue else {
            throw CompanionError.unexpectedResponse("session start missing _sid")
        }
        sessionID = (UInt64(UInt32(truncatingIfNeeded: remoteID)) << 32) | UInt64(localID)
    }

    private func subscribe(to eventNames: [String]) async throws {
        try await sendEvent("_interest", ["_regEvents": .array(eventNames.map(OPACKValue.string))])
    }

    // MARK: - Messaging

    private func request(
        _ identifier: String,
        _ content: [String: OPACKValue],
        timeout: TimeInterval = 5
    ) async throws -> OPACKValue {
        try await connection.exchange(
            .encryptedOPACK,
            [
                "_i": .string(identifier),
                "_t": .int(CompanionMessageType.request.rawValue),
                "_c": .dictionary(content),
            ], timeout: timeout)
    }

    private func sendEvent(_ identifier: String, _ content: [String: OPACKValue]) async throws {
        try await connection.send(
            .encryptedOPACK,
            [
                "_i": .string(identifier),
                "_t": .int(CompanionMessageType.event.rawValue),
                "_c": .dictionary(content),
            ])
    }
}
