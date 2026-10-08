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

    // MARK: - Volume (media control)

    /// Media-control commands sent as `_mcc`; only a few are useful here.
    enum MediaControlCommand: Int64 {
        case getVolume = 5
        case setVolume = 6
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
