import ClickerApp
import ClickerCompanion
import Foundation
import Network

/// A made-up TV's side of a Companion session. Commands are accepted and go
/// nowhere; what the TV reports comes from its `DemoTV`.
actor DemoSession: RemoteSession {
    nonisolated let events: AsyncStream<CompanionEvent>
    private nonisolated let eventSink: AsyncStream<CompanionEvent>.Continuation
    private let tv: DemoTV
    private var mediaControls: MediaControlFlags
    private var volume = 0.5

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

    /// A button as it reached the TV.
    enum Button: Equatable, Sendable {
        case press(HIDCommand)
        case down(HIDCommand)
        case up(HIDCommand)
    }

    /// Every button sent to this session, answered or not, for the tests.
    private(set) var buttons: [Button] = []

    func press(_ command: HIDCommand) async throws {
        buttons.append(.press(command))
        try await answerInput()
    }

    func buttonDown(_ command: HIDCommand) async throws {
        buttons.append(.down(command))
        try await answerInput()
    }

    func buttonUp(_ command: HIDCommand) async throws {
        buttons.append(.up(command))
        try await answerInput()
    }

    func mediaControl(_ command: CompanionClient.MediaControlCommand) async throws {}
    func skip(by seconds: Double) async throws {}
    func touch(x: Double, y: Double, phase: TouchPhase) async throws { try await answerInput() }
    func swipe(from start: CGPoint, to end: CGPoint, duration: Duration) async throws { try await answerInput() }

    /// Waits out the request as `CompanionClient` would for a TV that has
    /// stopped answering (`DemoTV.inputTimeout`).
    private func answerInput() async throws {
        guard let timeout = tv.inputTimeout else { return }
        try await Task.sleep(for: timeout)
        throw CompanionError.timeout
    }

    func fetchVolume() async throws -> Double { volume }

    func setVolume(_ volume: Double) async throws {
        // HDMI answers and changes nothing.
        guard tv.echoesVolume else { return }
        self.volume = volume
        sendMediaControls()
    }

    func fetchPowerState() async throws -> PowerState { tv.power }

    func fetchApps() async throws -> [AppleTVApp] { DemoScenario.apps }
    func launchApp(bundleIdentifier: String) async throws {}
    func fetchUserAccounts() async throws -> [UserAccount] { DemoScenario.userAccounts }
    func switchUserAccount(id: String) async throws {}

    func startTextInput() async throws -> TextInputArchive.Session? {
        tv.focusedText.map { TextInputArchive.Session(sessionUUID: UUID(), currentText: $0) }
    }

    func insertText(_ text: String, session: TextInputArchive.Session) async throws {}
    func clearText(session: TextInputArchive.Session) async throws {}
    func replaceText(_ text: String, session: TextInputArchive.Session) async throws {}

    private func sendMediaControls() {
        eventSink.yield(CompanionEvent(name: "_iMC", content: ["_mcF": .int(mediaControls.rawValue)]))
    }
}
