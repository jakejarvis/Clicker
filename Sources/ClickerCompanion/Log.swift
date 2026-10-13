import os

package enum Log {
    package static let subsystem = "com.jakejarvis.Clicker"
    package static let connection = Logger(subsystem: subsystem, category: "connection")
    package static let pairing = Logger(subsystem: subsystem, category: "pairing")
    package static let discovery = Logger(subsystem: subsystem, category: "discovery")
    package static let remote = Logger(subsystem: subsystem, category: "remote")
    package static let storage = Logger(subsystem: subsystem, category: "storage")
    package static let updates = Logger(subsystem: subsystem, category: "updates")
}
