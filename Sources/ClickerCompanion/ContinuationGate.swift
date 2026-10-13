import Foundation

/// Resumes a continuation at most once from arbitrary queues.
///
/// A result that arrives before the continuation is stored is kept and
/// delivered by `store`, so a cancellation handler that runs ahead of the
/// operation it guards (as `withTaskCancellationHandler` does for a task
/// that is already cancelled) is never lost.
final class ContinuationGate<T: Sendable>: @unchecked Sendable {
    private enum State {
        case open(CheckedContinuation<T, Error>?)
        case decided(Result<T, Error>)
        case finished
    }

    private let lock = NSLock()
    private var state = State.open(nil)

    init() {}

    /// Stores the continuation, or resumes it at once when a result is
    /// already in. Returns false in that case: the outcome is settled, so
    /// the caller should not start the work it was going to wait for.
    @discardableResult
    func store(_ continuation: CheckedContinuation<T, Error>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .open:
            state = .open(continuation)
            return true
        case .decided(let result):
            state = .finished
            continuation.resume(with: result)
            return false
        case .finished:
            continuation.resume(throwing: CancellationError())
            return false
        }
    }

    /// Settles the gate with `result`. Returns true for the first call only.
    @discardableResult
    func resume(_ result: Result<T, Error>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .open(let continuation?):
            state = .finished
            continuation.resume(with: result)
            return true
        case .open(nil):
            state = .decided(result)
            return true
        case .decided, .finished:
            return false
        }
    }
}
