import ClickerCompanion
import Foundation
import Network

/// A live Companion session with one Apple TV: everything `RemoteController`
/// asks of `CompanionClient`. The demo build and the tests stand in for it.
package nonisolated protocol RemoteSession: AnyObject, Sendable {
    /// Events the TV pushes; the stream ends when the connection closes.
    var events: AsyncStream<CompanionEvent> { get }
    var remoteEndpoint: NWEndpoint? { get async }
    var sessionID: UInt64 { get async }
    var osVersion: String? { get async }

    func connect(timeout: Duration) async throws
    func disconnect() async

    func press(_ command: HIDCommand) async throws
    func buttonDown(_ command: HIDCommand) async throws
    func buttonUp(_ command: HIDCommand) async throws
    func mediaControl(_ command: CompanionClient.MediaControlCommand) async throws
    func skip(by seconds: Double) async throws
    func touch(x: Double, y: Double, phase: TouchPhase) async throws
    func swipe(from start: CGPoint, to end: CGPoint, duration: Duration) async throws

    func fetchVolume() async throws -> Double
    func setVolume(_ volume: Double) async throws
    func fetchPowerState() async throws -> PowerState

    func fetchApps() async throws -> [AppleTVApp]
    func launchApp(bundleIdentifier: String) async throws
    func fetchUserAccounts() async throws -> [UserAccount]
    func switchUserAccount(id: String) async throws

    func startTextInput() async throws -> TextInputArchive.Session?
    func insertText(_ text: String, session: TextInputArchive.Session) async throws
    func clearText(session: TextInputArchive.Session) async throws
    func replaceText(_ text: String, session: TextInputArchive.Session) async throws
}

extension CompanionClient: RemoteSession {}
