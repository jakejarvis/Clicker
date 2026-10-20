import ClickerCompanion

// How the app names and draws the protocol's commands and states; the
// Companion module only knows their wire values.

extension HIDCommand {
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
        // Three speakers differing only in their badge; the wave glyphs read
        // as levels and the three-wave one is wider.
        case .volumeUp: return "speaker.plus"
        case .volumeDown: return "speaker.minus"
        case .siri:
            // The Siri orb glyph arrived with the 2025 symbol catalog.
            if #available(macOS 26, *) { return "siri" }
            return "mic"
        case .screensaver: return "sparkles.tv"
        case .sleep: return "moon"
        case .wake: return "sun.max"
        case .playPause: return "playpause"
        case .channelIncrement: return "plus.rectangle"
        case .channelDecrement: return "minus.rectangle"
        case .guide: return "list.bullet.rectangle"
        case .pageUp: return "arrow.up.to.line"
        case .pageDown: return "switch.2"
        }
    }
}

extension PowerState {
    var title: String {
        switch self {
        case .unknown: return "Unknown"
        case .asleep: return "Asleep"
        case .screensaver: return "Screen Saver"
        case .awake: return "Awake"
        case .idle: return "Idle"
        }
    }

    /// Tooltip for the Power control: the title plus a readable state.
    var powerTooltip: String {
        switch self {
        case .unknown: return "Power"
        case .asleep: return "Power · Asleep"
        case .screensaver: return "Power · Screen saver on"
        case .awake: return "Power · Awake"
        case .idle: return "Power · Idle"
        }
    }
}
