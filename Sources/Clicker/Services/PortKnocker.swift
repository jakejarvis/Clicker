import Foundation
import Network

/// Opens short TCP connections to the ports an Apple TV advertises. A TV
/// sleeping behind a Bonjour sleep proxy is woken when any of its services is
/// contacted, which these connections emulate (the same trick as pyatv's
/// knock module). Nothing is sent; each connection is dropped after half a
/// second whether or not it opened.
enum PortKnocker {
    /// DAAP, AirPlay, and the ports Companion and AirPlay sessions usually
    /// land on.
    static let ports: [UInt16] = [3689, 7000, 32498, 49152, 49153]
    static let timeout: DispatchTimeInterval = .milliseconds(500)

    private static let queue = DispatchQueue(label: "com.jakejarvis.Clicker.knock")

    static func knock(host: String) {
        Log.discovery.info("Knocking on \(host, privacy: .public)")
        for port in ports {
            guard let port = NWEndpoint.Port(rawValue: port) else { continue }
            let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed, .waiting:
                    connection.cancel()
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { connection.cancel() }
        }
    }
}
