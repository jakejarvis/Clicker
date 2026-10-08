import os

enum Log {
    static let subsystem = "com.jakejarvis.Clicker"
    static let connection = Logger(subsystem: subsystem, category: "connection")
    static let pairing = Logger(subsystem: subsystem, category: "pairing")
    static let discovery = Logger(subsystem: subsystem, category: "discovery")
    static let remote = Logger(subsystem: subsystem, category: "remote")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let updates = Logger(subsystem: subsystem, category: "updates")
}
