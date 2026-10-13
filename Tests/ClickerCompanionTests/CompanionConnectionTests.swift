import Foundation
import Network
import Testing

@testable import ClickerCompanion

/// Runs a connection against a loopback listener that accepts and never
/// answers, so every wait ends by cancellation, timeout or close.
@Suite struct CompanionConnectionTests {
    /// A TCP listener on 127.0.0.1 that keeps every connection open and silent.
    private final class SilentServer: Sendable {
        let listener: NWListener
        let endpoint: NWEndpoint

        init() async throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { $0.start(queue: .global()) }
            let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { continuation in
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        listener.stateUpdateHandler = nil
                        continuation.resume(returning: listener.port!)
                    case .failed(let error):
                        listener.stateUpdateHandler = nil
                        continuation.resume(throwing: error)
                    default:
                        break
                    }
                }
                listener.start(queue: .global())
            }
            self.listener = listener
            endpoint = .hostPort(host: "127.0.0.1", port: port)
        }

        deinit { listener.cancel() }
    }

    private static let request: [String: OPACKValue] = ["_i": "_systemInfo", "_t": 2, "_c": [:]]

    @Test func cancellingARequestEndsItAtOnce() async throws {
        let server = try await SilentServer()
        let connection = CompanionConnection(endpoint: server.endpoint)
        try await connection.connect()

        let clock = ContinuousClock()
        let started = clock.now
        let request = Task { try await connection.exchange(.encryptedOPACK, Self.request, timeout: .seconds(30)) }
        try await Task.sleep(for: .milliseconds(100))
        request.cancel()

        await #expect(throws: CancellationError.self) { try await request.value }
        #expect(clock.now - started < .seconds(5))
        #expect(await connection.isConnected)
        await connection.close()
    }

    @Test func aRequestCancelledBeforeItStartsNeverWaits() async throws {
        let server = try await SilentServer()
        let connection = CompanionConnection(endpoint: server.endpoint)
        try await connection.connect()

        let request = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await connection.exchange(.encryptedOPACK, Self.request, timeout: .seconds(30))
        }
        await #expect(throws: CancellationError.self) { try await request.value }
        await connection.close()
    }

    @Test func closingFailsWaitingRequests() async throws {
        let server = try await SilentServer()
        let connection = CompanionConnection(endpoint: server.endpoint)
        try await connection.connect()

        let request = Task { try await connection.exchange(.encryptedOPACK, Self.request, timeout: .seconds(30)) }
        try await Task.sleep(for: .milliseconds(100))
        await connection.close()

        await #expect(throws: CompanionError.self) { try await request.value }
        #expect(await !connection.isConnected)
    }

    @Test func aSilentPeerTimesOut() async throws {
        let server = try await SilentServer()
        let connection = CompanionConnection(endpoint: server.endpoint)
        try await connection.connect()

        await #expect(throws: CompanionError.self) {
            try await connection.exchange(.encryptedOPACK, Self.request, timeout: .milliseconds(200))
        }
        await connection.close()
    }
}
