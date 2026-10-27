import AppIntents
import ClickerCompanion

/// The buttons a Shortcuts action can press: every `HIDCommand` but Sleep
/// and Wake, which have actions of their own. The titles and symbols repeat
/// `HIDCommand.title` and `systemImage` as literals because the system reads
/// them from the build, not by running the app; a test keeps them in step.
nonisolated enum RemoteButton: String, AppEnum, CaseIterable {
    case up, down, left, right, select, menu, home, playPause
    case volumeUp, volumeDown, siri, screensaver
    case channelUp, channelDown, guide, pageUp, controlCenter

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Remote Button"

    static let caseDisplayRepresentations: [RemoteButton: DisplayRepresentation] = [
        .up: DisplayRepresentation(title: "Up", image: .init(systemName: "chevron.up")),
        .down: DisplayRepresentation(title: "Down", image: .init(systemName: "chevron.down")),
        .left: DisplayRepresentation(title: "Left", image: .init(systemName: "chevron.left")),
        .right: DisplayRepresentation(title: "Right", image: .init(systemName: "chevron.right")),
        .select: DisplayRepresentation(title: "Select", image: .init(systemName: "circle.fill")),
        .menu: DisplayRepresentation(title: "Back", image: .init(systemName: "chevron.backward")),
        .home: DisplayRepresentation(title: "TV", image: .init(systemName: "tv")),
        .playPause: DisplayRepresentation(title: "Play/Pause", image: .init(systemName: "playpause")),
        .volumeUp: DisplayRepresentation(title: "Volume Up", image: .init(systemName: "speaker.plus")),
        .volumeDown: DisplayRepresentation(title: "Volume Down", image: .init(systemName: "speaker.minus")),
        .siri: DisplayRepresentation(title: "Siri", image: .init(systemName: "mic")),
        .screensaver: DisplayRepresentation(title: "Screen Saver", image: .init(systemName: "sparkles.tv")),
        .channelUp: DisplayRepresentation(title: "Channel Up", image: .init(systemName: "plus.rectangle")),
        .channelDown: DisplayRepresentation(title: "Channel Down", image: .init(systemName: "minus.rectangle")),
        .guide: DisplayRepresentation(title: "Guide", image: .init(systemName: "list.bullet.rectangle")),
        .pageUp: DisplayRepresentation(title: "Page Up", image: .init(systemName: "arrow.up.to.line")),
        .controlCenter: DisplayRepresentation(title: "Control Center", image: .init(systemName: "switch.2")),
    ]

    var command: HIDCommand {
        switch self {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .select: .select
        case .menu: .menu
        case .home: .home
        case .playPause: .playPause
        case .volumeUp: .volumeUp
        case .volumeDown: .volumeDown
        case .siri: .siri
        case .screensaver: .screensaver
        case .channelUp: .channelIncrement
        case .channelDown: .channelDecrement
        case .guide: .guide
        case .pageUp: .pageUp
        case .controlCenter: .pageDown
        }
    }
}
