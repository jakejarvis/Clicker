import Foundation

/// Button identifiers for the Companion `_hidC` command.
enum HIDCommand: Int64, CaseIterable, Sendable {
    case up = 1
    case down = 2
    case left = 3
    case right = 4
    case menu = 5
    case select = 6
    case home = 7
    case volumeUp = 8
    case volumeDown = 9
    case siri = 10
    case screensaver = 11
    case sleep = 12
    case wake = 13
    case playPause = 14
    case channelIncrement = 15
    case channelDecrement = 16
    case guide = 17
    case pageUp = 18
    case pageDown = 19

    var title: String {
        switch self {
        case .up: return "Up"
        case .down: return "Down"
        case .left: return "Left"
        case .right: return "Right"
        case .menu: return "Back"
        case .select: return "Select"
        case .home: return "TV"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .siri: return "Siri"
        case .screensaver: return "Screen Saver"
        case .sleep: return "Sleep"
        case .wake: return "Wake"
        case .playPause: return "Play/Pause"
        case .channelIncrement: return "Channel Up"
        case .channelDecrement: return "Channel Down"
        case .guide: return "Guide"
        case .pageUp: return "Page Up"
        case .pageDown: return "Control Center"
        }
    }

    var systemImage: String {
        switch self {
        case .up: return "chevron.up"
        case .down: return "chevron.down"
        case .left: return "chevron.left"
        case .right: return "chevron.right"
        case .menu: return "chevron.backward"
        case .select: return "circle.fill"
        case .home: return "tv"
        case .volumeUp: return "speaker.wave.3"
        case .volumeDown: return "speaker.wave.1"
        case .siri:
            // The Siri orb glyph arrived with the 2025 symbol catalog.
            if #available(macOS 26, *) { return "siri" }
            return "mic"
        case .screensaver: return "sparkles.tv"
        case .sleep: return "moon.fill"
        case .wake: return "sun.max.fill"
        case .playPause: return "playpause"
        case .channelIncrement: return "plus.rectangle"
        case .channelDecrement: return "minus.rectangle"
        case .guide: return "list.bullet.rectangle"
        case .pageUp: return "arrow.up.to.line"
        case .pageDown: return "switch.2"
        }
    }
}

struct AppleTVApp: Identifiable, Hashable, Sendable {
    let bundleIdentifier: String
    let name: String

    var id: String { bundleIdentifier }
}

/// Mirrors the `state` field of `TVSystemStatus` events.
enum PowerState: Int64, Sendable {
    case unknown = 0
    case asleep = 1
    case screensaver = 2
    case awake = 3
    case idle = 4

    var title: String {
        switch self {
        case .unknown: return "Unknown"
        case .asleep: return "Asleep"
        case .screensaver: return "Screen Saver"
        case .awake: return "Awake"
        case .idle: return "Idle"
        }
    }

    var isOn: Bool? {
        switch self {
        case .unknown: return nil
        case .asleep: return false
        case .screensaver, .awake, .idle: return true
        }
    }
}

/// How this Mac introduces itself to the Apple TV.
struct ClientIdentity: Sendable {
    /// Shown on the Apple TV under Remotes and Devices.
    var name: String
    /// MAC-style identifier sent in `_systemInfo`; generated once per install.
    var deviceID: String
}
