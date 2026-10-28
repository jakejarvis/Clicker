import ClickerCompanion

// How the app names and draws the protocol's commands and states; the
// Companion module only knows their wire values.

extension HIDCommand {
    var title: String {
        switch self {
        case .up: return String(localized: "Up")
        case .down: return String(localized: "Down")
        case .left: return String(localized: "Left")
        case .right: return String(localized: "Right")
        case .menu: return String(localized: "Back", comment: "Remote button: the Siri Remote's Back button")
        case .select: return String(localized: "Select", comment: "Remote button: the clickpad's center")
        case .home: return String(localized: "TV", comment: "Remote button: the Siri Remote's TV (Home) button")
        case .volumeUp: return String(localized: "Volume Up")
        case .volumeDown: return String(localized: "Volume Down")
        case .siri: return "Siri"
        case .screensaver: return String(localized: "Screen Saver")
        case .sleep: return String(localized: "Sleep", comment: "Power menu: put the Apple TV to sleep")
        case .wake: return String(localized: "Wake", comment: "Power menu: wake the Apple TV")
        case .playPause: return String(localized: "Play/Pause")
        case .channelIncrement: return String(localized: "Channel Up")
        case .channelDecrement: return String(localized: "Channel Down")
        case .guide: return String(localized: "Guide", comment: "Power menu: the TV program guide")
        case .pageUp: return String(localized: "Page Up")
        case .pageDown: return String(localized: "Control Center", comment: "Power menu: tvOS Control Center")
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
        case .unknown: return String(localized: "Unknown", comment: "The Apple TV's power state")
        case .asleep: return String(localized: "Asleep", comment: "The Apple TV's state: asleep")
        case .screensaver: return String(localized: "Screen Saver")
        case .awake: return String(localized: "Awake", comment: "The Apple TV's power state")
        case .idle: return String(localized: "Idle", comment: "The Apple TV's power state")
        }
    }

    /// Tooltip for the Power control: the title plus a readable state.
    var powerTooltip: String {
        switch self {
        case .unknown: return String(localized: "Power")
        case .asleep: return String(localized: "Power · Asleep")
        case .screensaver: return String(localized: "Power · Screen saver on")
        case .awake: return String(localized: "Power · Awake")
        case .idle: return String(localized: "Power · Idle")
        }
    }
}
