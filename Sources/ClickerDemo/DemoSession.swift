import ClickerApp
import ClickerCompanion
import Foundation
import Network

/// A made-up TV's side of a Companion session. Commands are accepted and go
/// nowhere but the record below, for tests; what the TV reports comes from
/// its `DemoTV`.
actor DemoSession: RemoteSession {
    nonisolated let events: AsyncStream<CompanionEvent>
    private nonisolated let eventSink: AsyncStream<CompanionEvent>.Continuation
    private let tv: DemoTV
    private var mediaControls: MediaControlFlags
    private var volume = 0.5
    /// What reached the "TV", in order.
    private(set) var presses: [HIDCommand] = []
    private(set) var launchedBundleIDs: [String] = []
    private(set) var insertedText: [String] = []

    init(tv: DemoTV) {
        self.tv = tv
        mediaControls = tv.mediaControls
        (events, eventSink) = AsyncStream.makeStream()
    }

    var remoteEndpoint: NWEndpoint? { tv.endpoint }
    var sessionID: UInt64 { 0x5C1A_7E2B }
    var osVersion: String? { "26.0.1" }

    func connect(timeout: Duration) async throws {
        if !tv.answersConnect { try await Task.sleep(for: .seconds(86_400)) }
        if let error = tv.connectError { throw error }
        // A real TV reports its output's controls right after the session
        // starts.
        sendMediaControls()
    }

    func disconnect() async {
        eventSink.finish()
    }

    /// The TV closes the session, as when it goes to sleep or restarts.
    nonisolated func drop() {
        eventSink.finish()
    }

    func press(_ command: HIDCommand) async throws { presses.append(command) }
    func buttonDown(_ command: HIDCommand) async throws {}
    func buttonUp(_ command: HIDCommand) async throws {}
    func mediaControl(_ command: CompanionClient.MediaControlCommand) async throws {}
    func skip(by seconds: Double) async throws {}
    func touch(x: Double, y: Double, phase: TouchPhase) async throws {}
    func swipe(from start: CGPoint, to end: CGPoint, duration: Duration) async throws {}

    func fetchVolume() async throws -> Double { volume }

    func setVolume(_ volume: Double) async throws {
        // HDMI answers and changes nothing.
        guard tv.echoesVolume else { return }
        self.volume = volume
        sendMediaControls()
    }

    func fetchPowerState() async throws -> PowerState { tv.power }

    func fetchApps() async throws -> [AppleTVApp] { DemoScenario.apps }
    func launchApp(bundleIdentifier: String) async throws { launchedBundleIDs.append(bundleIdentifier) }
    func fetchUserAccounts() async throws -> [UserAccount] { DemoScenario.userAccounts }
    func switchUserAccount(id: String) async throws {}

    func startTextInput() async throws -> TextInputArchive.Session? {
        tv.focusedText.map { TextInputArchive.Session(sessionUUID: UUID(), currentText: $0) }
    }

    func insertText(_ text: String, session: TextInputArchive.Session) async throws { insertedText.append(text) }
    func clearText(session: TextInputArchive.Session) async throws {}
    func replaceText(_ text: String, session: TextInputArchive.Session) async throws {}

    private func sendMediaControls() {
        eventSink.yield(CompanionEvent(name: "_iMC", content: ["_mcF": .int(mediaControls.rawValue)]))
    }
}
