import Foundation
import Network

struct CompanionEvent: Sendable {
    let name: String
    let content: OPACKValue
}

/// A framed, optionally encrypted TCP connection to a Companion service.
///
/// Handles the four-byte frame header, session encryption once pair-verify has
/// completed, and matching responses to requests: authentication frames are
/// matched by frame type, regular OPACK responses by transaction id (`_x`).
actor CompanionConnection {
    private let endpoint: NWEndpoint
    private let queue = DispatchQueue(label: "com.jakejarvis.Clicker.companion-connection")
    private var connection: NWConnection?
    private var cipher: SessionCipher?
    private var receiveTask: Task<Void, Never>?
    private var pendingAuthentication: [CompanionFrameType: CheckedContinuation<OPACKValue, Error>] = [:]
    private var pendingResponses: [Int64: CheckedContinuation<OPACKValue, Error>] = [:]
    private var nextTransactionID = Int64.random(in: 0...0xFFFF)
    private var isClosed = false
    private let eventContinuation: AsyncStream<CompanionEvent>.Continuation

    /// Unsolicited events pushed by the Apple TV (power state changes, etc).
    nonisolated let events: AsyncStream<CompanionEvent>

    init(endpoint: NWEndpoint) {
        self.endpoint = endpoint
        let (stream, continuation) = AsyncStream<CompanionEvent>.makeStream()
        events = stream
        eventContinuation = continuation
    }

    var isConnected: Bool {
        connection != nil && !isClosed
    }

    /// The resolved address the TCP connection ended up on, once ready.
    var remoteEndpoint: NWEndpoint? {
        connection?.currentPath?.remoteEndpoint
    }

    // MARK: - Lifecycle

    func connect(timeout: TimeInterval = 10) async throws {
        guard connection == nil, !isClosed else {
            if isClosed { throw CompanionError.disconnected }
            return
        }

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection

        let gate = ContinuationGate<Void>()
        let queue = self.queue
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            gate.store(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.resume(.success(()))
                case .failed(let error):
                    gate.resume(.failure(CompanionError.connectionFailed(error.localizedDescription)))
                    connection.cancel()
                case .cancelled:
                    gate.resume(.failure(CompanionError.disconnected))
                case .waiting(let error):
                    Log.connection.info("Waiting for connection: \(error.localizedDescription, privacy: .public)")
                default:
                    break
                }
            }
            queue.asyncAfter(deadline: .now() + timeout) {
                if gate.resume(.failure(CompanionError.timeout)) {
                    connection.cancel()
                }
            }
            connection.start(queue: queue)
        }

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                Task { await self?.handleDisconnect(CompanionError.connectionFailed(error.localizedDescription)) }
            case .cancelled:
                Task { await self?.handleDisconnect(CompanionError.disconnected) }
            default:
                break
            }
        }

        receiveTask = Task { await self.receiveLoop(on: connection) }
        Log.connection.info("Connected to \(String(describing: self.endpoint), privacy: .public)")
    }

    func close() {
        handleDisconnect(CompanionError.disconnected)
    }

    func enableEncryption(outputKey: SymmetricKeyBox, inputKey: SymmetricKeyBox) {
        cipher = SessionCipher(outputKey: outputKey.key, inputKey: inputKey.key)
    }

    // MARK: - Sending

    /// Sends an OPACK dictionary, adding a transaction id when missing.
    func send(_ frameType: CompanionFrameType, _ message: [String: OPACKValue]) throws {
        var message = message
        if message["_x"] == nil {
            message["_x"] = .int(takeTransactionID())
        }
        try sendFrame(frameType, payload: OPACK.encode(.dictionary(message)))
    }

    /// Sends a pair-setup or pair-verify frame and waits for the device's reply.
    func exchangeAuthentication(
        _ frameType: CompanionFrameType,
        _ message: [String: OPACKValue],
        timeout: TimeInterval = 30
    ) async throws -> OPACKValue {
        precondition(frameType.isAuthentication)
        let key = frameType.responseType
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            await self?.timeOutAuthentication(key)
        }
        defer { timeoutTask.cancel() }

        var message = message
        message["_x"] = .int(takeTransactionID())

        let response: OPACKValue = try await withCheckedThrowingContinuation { continuation in
            if let previous = pendingAuthentication.removeValue(forKey: key) {
                previous.resume(throwing: CompanionError.unexpectedResponse("superseded authentication exchange"))
            }
            pendingAuthentication[key] = continuation
            do {
                try sendFrame(frameType, payload: OPACK.encode(.dictionary(message)))
            } catch {
                pendingAuthentication[key] = nil
                continuation.resume(throwing: error)
            }
        }
        try Self.checkRemoteError(response)
        return response
    }

    /// Sends a request-style OPACK message and waits for the matching response.
    func exchange(
        _ frameType: CompanionFrameType,
        _ message: [String: OPACKValue],
        timeout: TimeInterval = 5
    ) async throws -> OPACKValue {
        let transactionID = takeTransactionID()
        var message = message
        message["_x"] = .int(transactionID)

        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            await self?.timeOutResponse(transactionID)
        }
        defer { timeoutTask.cancel() }

        let response: OPACKValue = try await withCheckedThrowingContinuation { continuation in
            pendingResponses[transactionID] = continuation
            do {
                try sendFrame(frameType, payload: OPACK.encode(.dictionary(message)))
            } catch {
                pendingResponses[transactionID] = nil
                continuation.resume(throwing: error)
            }
        }
        try Self.checkRemoteError(response)
        return response
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
        if encrypts {
            body = try cipher!.encrypt(payload, aad: header)
        }

        connection.send(
            content: header + body,
            completion: .contentProcessed { error in
                if let error {
                    Log.connection.error("Send failed: \(error.localizedDescription, privacy: .public)")
                }
            })
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
                if cipher != nil, !payload.isEmpty {
                    payload = try cipher!.decrypt(payload, aad: Data(header))
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
                    continuation.resume(throwing: CompanionError.connectionFailed(error.localizedDescription))
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
            if let continuation = pendingAuthentication.removeValue(forKey: frameType) {
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
                let continuation = pendingResponses.removeValue(forKey: transactionID)
            {
                continuation.resume(returning: message)
            } else {
                Log.connection.debug("Response without a waiting request: \(message.description, privacy: .public)")
            }
        case .request:
            Log.connection.debug("Ignoring request from device: \(message.description, privacy: .public)")
        }
    }

    private func timeOutAuthentication(_ key: CompanionFrameType) {
        pendingAuthentication.removeValue(forKey: key)?.resume(throwing: CompanionError.timeout)
    }

    private func timeOutResponse(_ transactionID: Int64) {
        pendingResponses.removeValue(forKey: transactionID)?.resume(throwing: CompanionError.timeout)
    }

    private func handleDisconnect(_ error: Error) {
        guard !isClosed else { return }
        isClosed = true
        Log.connection.info("Connection closed: \(String(describing: error), privacy: .public)")

        receiveTask?.cancel()
        receiveTask = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        cipher = nil

        for continuation in pendingAuthentication.values { continuation.resume(throwing: error) }
        pendingAuthentication.removeAll()
        for continuation in pendingResponses.values { continuation.resume(throwing: error) }
        pendingResponses.removeAll()
        eventContinuation.finish()
    }
}

/// Resumes a continuation at most once from arbitrary queues.
private final class ContinuationGate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    func store(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        defer { lock.unlock() }
        self.continuation = continuation
    }

    @discardableResult
    func resume(_ result: Result<T, Error>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let continuation else { return false }
        self.continuation = nil
        continuation.resume(with: result)
        return true
    }
}
