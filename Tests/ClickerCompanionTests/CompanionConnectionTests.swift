import Foundation
import Network
import Testing

@testable import ClickerCompanion

/// Runs a connection against a loopback listener that accepts and never
/// answers, so every wait ends by cancellation, timeout or close.
@Suite struct CompanionConnectionTests {
    /// A TCP listener on 127.0.0.1 that keeps every connection open and
    /// silent, and reports each chunk of bytes it receives.
    private final class SilentServer: Sendable {
        let listener: NWListener
        let endpoint: NWEndpoint
        /// Yields once per chunk received. A request reaches the wire only
        /// after `exchange` has registered its waiter, so a chunk here means
        /// a reply is pending.
        let received: AsyncStream<Void>

        init() async throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            let listener = try NWListener(using: parameters)
            let (received, receivedContinuation) = AsyncStream<Void>.makeStream()
            self.received = received
            listener.newConnectionHandler = { connection in
                @Sendable func readNext() {
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                        if data?.isEmpty == false { receivedContinuation.yield() }
                        if error == nil, !isComplete { readNext() }
                    }
                }
                connection.start(queue: .global())
                readNext()
            }
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
        await server.received.first { _ in true }
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
        await server.received.first { _ in true }
        await connection.close()

        await #expect(throws: CompanionError.self) { try await request.value }
        #expect(await !connection.isConnected)
    }

    @Test func aConnectCancelledBeforeItStartsNeverConnects() async throws {
        let server = try await SilentServer()
        let connection = CompanionConnection(endpoint: server.endpoint)

        // A loopback connect lands at once, so without the early check the
        // connect would succeed despite the cancellation.
        let connect = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await connection.connect(timeout: .seconds(30))
        }
        await #expect(throws: CancellationError.self) { try await connect.value }
        // A failed connect closes the connection rather than leaving it
        // looking connected.
        #expect(await !connection.isConnected)
        await #expect(throws: CompanionError.self) { try await connection.connect() }
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
