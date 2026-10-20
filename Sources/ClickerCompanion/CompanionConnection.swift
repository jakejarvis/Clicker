import CryptoKit
import Foundation
import Network

package struct CompanionEvent: Sendable {
    package let name: String
    package let content: OPACKValue

    package init(name: String, content: OPACKValue) {
        self.name = name
        self.content = content
    }
}

/// A framed, optionally encrypted TCP connection to a Companion service.
///
/// Handles the four-byte frame header, session encryption once pair-verify has
/// completed, and matching responses to requests: authentication frames are
/// matched by frame type, regular OPACK responses by transaction id (`_x`).
///
/// Every wait honors task cancellation: a cancelled caller gets
/// `CancellationError` at once instead of waiting out its timeout.
package actor CompanionConnection {
    /// What a waiting caller is waiting for.
    private enum PendingReply: Hashable {
        case authentication(CompanionFrameType)
        case transaction(Int64)
    }

    private let endpoint: NWEndpoint
    private let queue = DispatchQueue(label: "com.jakejarvis.Clicker.companion-connection")
    private var connection: NWConnection?
    private var cipher: SessionCipher?
    private var receiveTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var pendingReplies: [PendingReply: CheckedContinuation<OPACKValue, Error>] = [:]
    /// The TCP connect in flight, so `close()` can end it rather than leave
    /// the caller waiting out the timeout.
    private var connectGate: ContinuationGate<Void>?
    private var nextTransactionID = Int64.random(in: 0...0xFFFF)
    private var isClosed = false
    private let eventContinuation: AsyncStream<CompanionEvent>.Continuation

    /// Unsolicited events pushed by the Apple TV (power state changes, etc).
    package nonisolated let events: AsyncStream<CompanionEvent>

    /// How often an empty NoOp frame goes out on an idle session. The session
    /// stays open after the panel closes, and without this nothing crosses the
    /// link between the last button press and the next one.
    package static let keepAliveInterval: Duration = .seconds(30)

    package init(endpoint: NWEndpoint) {
        self.endpoint = endpoint
        let (stream, continuation) = AsyncStream<CompanionEvent>.makeStream()
        events = stream
        eventContinuation = continuation
    }

    package var isConnected: Bool {
        connection != nil && !isClosed
    }

    /// The resolved address the TCP connection ended up on, once ready.
    package var remoteEndpoint: NWEndpoint? {
        connection?.currentPath?.remoteEndpoint
    }

    // MARK: - Lifecycle

    package func connect(timeout: Duration = .seconds(10)) async throws {
        guard connection == nil, !isClosed else {
            if isClosed { throw CompanionError.disconnected }
            return
        }

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection

        // The state handler, the timeout, a cancelled caller and `close()`
        // all race to finish the connect; the gate lets only the first through.
        let gate = ContinuationGate<Void>()
        connectGate = gate
        let timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            if gate.resume(.failure(CompanionError.timeout)) { connection.cancel() }
        }
        defer {
            timeoutTask.cancel()
            connectGate = nil
        }
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    // False when a cancellation (or `close()`) already settled
                    // the gate: the continuation is resumed, so do not start.
                    guard gate.store(continuation) else { return }
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            gate.resume(.success(()))
                        case .failed(let error):
                            gate.resume(.failure(CompanionError.connectionFailed(error)))
                            connection.cancel()
                        case .cancelled:
                            gate.resume(.failure(CompanionError.disconnected))
                        case .waiting(let error):
                            Log.connection.info(
                                "Waiting for connection: \(error.localizedDescription, privacy: .public)")
                        default:
                            break
                        }
                    }
                    connection.start(queue: queue)
                }
            } onCancel: {
                if gate.resume(.failure(CancellationError())) { connection.cancel() }
            }
        } catch {
            // A failed connect leaves the actor closed, like a dropped
            // session, rather than holding a dead connection that reads as
            // connected and makes the next `connect()` a silent no-op.
            handleDisconnect(error)
            throw error
        }

        // `close()` may have run while the connect was suspended.
        guard !isClosed, self.connection === connection else { throw CompanionError.disconnected }

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                Task { await self?.handleDisconnect(CompanionError.connectionFailed(error)) }
            case .cancelled:
                Task { await self?.handleDisconnect(CompanionError.disconnected) }
            default:
                break
            }
        }

        receiveTask = Task { await self.receiveLoop(on: connection) }
        keepAliveTask = Task { await self.keepAliveLoop() }
        Log.connection.info("Connected to \(String(describing: self.endpoint), privacy: .public)")
    }

    package func close() {
        handleDisconnect(CompanionError.disconnected)
    }

    package func enableEncryption(outputKey: SymmetricKey, inputKey: SymmetricKey) {
        cipher = SessionCipher(outputKey: outputKey, inputKey: inputKey)
    }

    // MARK: - Sending

    /// Sends an OPACK dictionary, adding a transaction id when missing.
    package func send(_ frameType: CompanionFrameType, _ message: [String: OPACKValue]) throws {
        var message = message
        if message["_x"] == nil {
            message["_x"] = .int(takeTransactionID())
        }
        try sendFrame(frameType, payload: OPACK.encode(.dictionary(message)))
    }

    /// Sends a pair-setup or pair-verify frame and waits for the device's reply.
    package func exchangeAuthentication(
        _ frameType: CompanionFrameType,
        _ message: [String: OPACKValue],
        timeout: Duration = .seconds(30)
    ) async throws -> OPACKValue {
        precondition(frameType.isAuthentication)
        var message = message
        message["_x"] = .int(takeTransactionID())
        let payload = OPACK.encode(.dictionary(message))
        return try await awaitReply(.authentication(frameType.responseType), timeout: timeout) {
            try sendFrame(frameType, payload: payload)
        }
    }

    /// Sends a request-style OPACK message and waits for the matching response.
    package func exchange(
        _ frameType: CompanionFrameType,
        _ message: [String: OPACKValue],
        timeout: Duration = .seconds(5)
    ) async throws -> OPACKValue {
        let transactionID = takeTransactionID()
        var message = message
        message["_x"] = .int(transactionID)
        let payload = OPACK.encode(.dictionary(message))
        return try await awaitReply(.transaction(transactionID), timeout: timeout) {
            try sendFrame(frameType, payload: payload)
        }
    }

    /// Registers a waiter for `key`, runs `send`, and waits for the reply, the
    /// timeout, a disconnect or the caller's cancellation, whichever comes
    /// first. A reply carrying `_em` is thrown as `remoteError`.
    private func awaitReply(
        _ key: PendingReply,
        timeout: Duration,
        send: () throws -> Void
    ) async throws -> OPACKValue {
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            await self?.failReply(key, with: CompanionError.timeout)
        }
        defer { timeoutTask.cancel() }

        let response = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<OPACKValue, Error>) in
                // Checked here, on the actor, so a cancellation that landed
                // before the waiter was registered is not missed: the
                // handler's hop below can only run after this closure.
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                failReply(key, with: CompanionError.unexpectedResponse("superseded exchange"))
                pendingReplies[key] = continuation
                do {
                    try send()
                } catch {
                    pendingReplies[key] = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            Task { await self.failReply(key, with: CancellationError()) }
        }
        try Self.checkRemoteError(response)
        return response
    }

    private func failReply(_ key: PendingReply, with error: Error) {
        pendingReplies.removeValue(forKey: key)?.resume(throwing: error)
    }

    private func sendFrame(_ frameType: CompanionFrameType, payload: Data) throws {
        guard let connection, !isClosed else { throw CompanionError.notConnected }

        var body = payload
        let encrypts = cipher != nil && !payload.isEmpty
        let length = payload.count + (encrypts ? 16 : 0)
        let header = Data([
            frameType.rawValue,
            UInt8((length >> 16) & 0xFF),
            UInt8((length >> 8) & 0xFF),
            UInt8(length & 0xFF),
        ])
        if encrypts, let sealed = try cipher?.encrypt(payload, aad: header) {
            body = sealed
        }

        connection.send(
            content: header + body,
            completion: .contentProcessed { error in
                if let error {
                    Log.connection.error("Send failed: \(error.localizedDescription, privacy: .public)")
                }
            })
    }

    /// Sends a NoOp frame every `keepAliveInterval` until the connection
    /// closes. The frame is a bare header with no payload, so it is never
    /// encrypted and the TV has nothing to answer.
    private func keepAliveLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.keepAliveInterval)
            guard !Task.isCancelled, !isClosed else { return }
            do {
                try sendFrame(.noOp, payload: Data())
                Log.connection.debug("Sent keep-alive")
            } catch {
                return
            }
        }
    }

    private func takeTransactionID() -> Int64 {
        defer { nextTransactionID = (nextTransactionID + 1) & 0xFFFF_FFFF }
        return nextTransactionID
    }

    private static func checkRemoteError(_ response: OPACKValue) throws {
        if let message = response["_em"]?.stringValue {
            throw CompanionError.remoteError(message)
        }
    }

    // MARK: - Receiving

    private func receiveLoop(on connection: NWConnection) async {
        do {
            while !Task.isCancelled {
                let header = [UInt8](try await receive(exactly: 4, from: connection))
                let length = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
                var payload = length > 0 ? try await receive(exactly: length, from: connection) : Data()
                if !payload.isEmpty, let opened = try cipher?.decrypt(payload, aad: Data(header)) {
                    payload = opened
                }
                dispatch(frameType: CompanionFrameType(rawValue: header[0]) ?? .unknown, payload: payload)
            }
        } catch {
            handleDisconnect(error)
        }
    }

    private func receive(exactly count: Int, from connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { content, _, _, error in
                if let error {
                    continuation.resume(throwing: CompanionError.connectionFailed(error))
                    return
                }
                guard let content, content.count == count else {
                    continuation.resume(throwing: CompanionError.disconnected)
                    return
                }
                continuation.resume(returning: content)
            }
        }
    }

    private func dispatch(frameType: CompanionFrameType, payload: Data) {
        guard frameType.isAuthentication || frameType.isOPACK else {
            Log.connection.debug("Ignoring frame type \(frameType.rawValue)")
            return
        }

        let message: OPACKValue
        do {
            message = try OPACK.decode(payload)
        } catch {
            Log.connection.error("Failed to decode OPACK frame: \(String(describing: error), privacy: .public)")
            return
        }

        if frameType.isAuthentication {
            if let continuation = pendingReplies.removeValue(forKey: .authentication(frameType)) {
                continuation.resume(returning: message)
            } else {
                Log.connection.warning("Unexpected authentication frame \(frameType.rawValue)")
            }
            return
        }

        guard let rawType = message["_t"]?.intValue, let type = CompanionMessageType(rawValue: rawType) else {
            Log.connection.debug("OPACK frame without message type: \(message.description, privacy: .public)")
            return
        }

        switch type {
        case .event:
            if let name = message["_i"]?.stringValue {
                eventContinuation.yield(CompanionEvent(name: name, content: message["_c"] ?? .null))
            }
        case .response:
            if let transactionID = message["_x"]?.intValue,
                let continuation = pendingReplies.removeValue(forKey: .transaction(transactionID))
            {
                continuation.resume(returning: message)
            } else {
                Log.connection.debug("Response without a waiting request: \(message.description, privacy: .public)")
            }
        case .request:
            Log.connection.debug("Ignoring request from device: \(message.description, privacy: .public)")
        }
    }

    private func handleDisconnect(_ error: Error) {
        guard !isClosed else { return }
        isClosed = true
        Log.connection.info("Connection closed: \(String(describing: error), privacy: .public)")

        receiveTask?.cancel()
        receiveTask = nil
        keepAliveTask?.cancel()
        keepAliveTask = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        cipher = nil

        connectGate?.resume(.failure(error))
        for continuation in pendingReplies.values { continuation.resume(throwing: error) }
        pendingReplies.removeAll()
        eventContinuation.finish()
    }
}
