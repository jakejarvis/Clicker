import ClickerCompanion
import Foundation
import Network
import os

/// Whether macOS lets Clicker reach devices on the local network (System
/// Settings › Privacy & Security › Local Network).
///
/// The connection to a TV can't tell. Its Bonjour endpoint resolves to
/// addresses whose paths come out "Local network prohibited", but those are
/// the connection's internal child flows: the connection itself stays
/// `.preparing` until the connect timeout cancels it. So this opens a UDP
/// connection to the network's gateway, a local address evaluated the same
/// way, where a denial is the connection's own path's `unsatisfiedReason`.
/// Nothing is sent: the probe is cancelled as soon as its path is known.
package nonisolated enum LocalNetworkAccess {
    package enum Status: Sendable, Equatable {
        case allowed
        case denied
        /// No gateway, or no answer in time. Treated as allowed: the connect
        /// goes ahead and fails on its own if it must.
        case unknown
    }

    static let timeout: DispatchTimeInterval = .seconds(1)

    private static let queue = DispatchQueue(label: "com.jakejarvis.Clicker.local-network")

    static func check() async -> Status {
        guard let gateway = await gateway() else {
            Log.connection.info("Local network access: unknown (no gateway)")
            return .unknown
        }
        let status = await probe(gateway)
        Log.connection.info("Local network access: \(String(describing: status), privacy: .public)")
        return status
    }

    /// The current path's first gateway, from the monitor's initial update.
    private static func gateway() async -> NWEndpoint.Host? {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let pending = OSAllocatedUnfairLock<CheckedContinuation<NWEndpoint.Host?, Never>?>(
                initialState: continuation)
            monitor.pathUpdateHandler = { path in
                guard let continuation = pending.withLock({ $0.take() }) else { return }
                monitor.cancel()
                let host = path.gateways.lazy.compactMap { endpoint -> NWEndpoint.Host? in
                    if case .hostPort(let host, _) = endpoint { host } else { nil }
                }.first
                continuation.resume(returning: host)
            }
            monitor.start(queue: queue)
        }
    }

    private static func probe(_ host: NWEndpoint.Host) async -> Status {
        let connection = NWConnection(host: host, port: 9, using: .udp)
        return await withCheckedContinuation { continuation in
            let pending = OSAllocatedUnfairLock<CheckedContinuation<Status, Never>?>(initialState: continuation)
            let finish: @Sendable (Status) -> Void = { status in
                guard let continuation = pending.withLock({ $0.take() }) else { return }
                connection.cancel()
                continuation.resume(returning: status)
            }
            // The verdict is in the path, evaluated before the connection
            // reports `.preparing` (allowed) or `.waiting` (denied). Waiting
            // for `.ready` would not do: the UDP flow to the gateway was seen
            // stalling in its connect for over a second with the path long
            // satisfied.
            connection.stateUpdateHandler = { state in
                switch state {
                case .preparing, .ready, .waiting, .failed:
                    guard let path = connection.currentPath else { return }
                    if path.status == .satisfied {
                        finish(.allowed)
                    } else {
                        finish(path.unsatisfiedReason == .localNetworkDenied ? .denied : .unknown)
                    }
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(.unknown) }
        }
    }
}
