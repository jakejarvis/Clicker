import SwiftUI

/// The remote itself: a clickpad ring with a large Select in the middle and
/// two columns of buttons below, laid out like the Siri Remote. Every button
/// sends HID "down" on press and "up" on release so holds work (Siri in
/// particular).
struct RemotePadView: View {
    let controller: RemoteController

    var body: some View {
        SurfaceContainer(spacing: 10) {
            VStack(spacing: 16) {
                // Power floats at the top right of the clickpad, where it sits
                // on the Siri Remote. Sized so it clears the ring.
                ZStack(alignment: .topTrailing) {
                    ClickpadView(controller: controller)
                        .frame(maxWidth: .infinity)
                    PowerMenu(controller: controller)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    HoldRemoteButton(command: .menu, controller: controller)
                    HoldRemoteButton(command: .home, controller: controller)
                    HoldRemoteButton(command: .playPause, controller: controller)
                    MuteButton(controller: controller)
                    HoldRemoteButton(command: .siri, controller: controller, tint: .purple)
                    VolumeRocker(controller: controller)
                }
            }
        }
        .remoteKeyboardShortcuts(controller: controller)
    }
}

enum RemoteMetrics {
    static let buttonHeight: CGFloat = 44
    static let powerButtonDiameter: CGFloat = 32
}

private struct ClickpadView: View {
    let controller: RemoteController

    private let diameter: CGFloat = 192
    private let centerDiameter: CGFloat = 84
    private let markOffset: CGFloat = 74

    var body: some View {
        ZStack {
            Circle()
                .fill(.quaternary)
                .overlay(Circle().strokeBorder(.separator.opacity(0.6), lineWidth: 1))
                .frame(width: diameter, height: diameter)

            DirectionButton(controller: controller, command: .up).offset(y: -markOffset)
            DirectionButton(controller: controller, command: .down).offset(y: markOffset)
            DirectionButton(controller: controller, command: .left).offset(x: -markOffset)
            DirectionButton(controller: controller, command: .right).offset(x: markOffset)

            HoldButton(controller: controller, command: .select) {
                Circle()
                    .fill(.clear)
                    .frame(width: centerDiameter, height: centerDiameter)
                    .contentShape(Circle())
            }
            .surface(Circle())
            .help("Select (Return)")
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clickpad")
    }

}

/// One direction on the clickpad. The arrow sits directly on the ring; hover
/// and press feedback are on the glyph only.
private struct DirectionButton: View {
    let controller: RemoteController
    let command: HIDCommand
    @State private var isHovered = false

    var body: some View {
        HoldButton(controller: controller, command: command, feedback: .glyph(isHovered: isHovered)) {
            Image(systemName: command.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help(command.title)
    }
}

/// Capsule button that sends press and release separately.
private struct HoldRemoteButton: View {
    let command: HIDCommand
    let controller: RemoteController
    var tint: Color?

    var body: some View {
        HoldButton(controller: controller, command: command) {
            RemoteGlyph(systemImage: command.systemImage, tint: tint)
                .contentShape(Capsule())
        }
        .surface(Capsule())
        .help(command == .siri ? "Hold for Siri" : command.title)
    }
}

/// Toggles software mute (volume to zero and back).
private struct MuteButton: View {
    let controller: RemoteController

    var body: some View {
        Button {
            controller.toggleMute()
        } label: {
            RemoteGlyph(
                systemImage: controller.isMuted ? "speaker.slash.fill" : "speaker.slash",
                tint: controller.isMuted ? .orange : nil
            )
            .contentShape(Capsule())
        }
        .buttonStyle(RemotePressStyle())
        .surface(Capsule(), tint: controller.isMuted ? .orange : nil)
        .help(controller.isMuted ? "Unmute (M)" : "Mute (M)")
        .accessibilityLabel(controller.isMuted ? "Unmute" : "Mute")
    }
}

/// One capsule, two halves: volume down on the left, volume up on the right.
private struct VolumeRocker: View {
    let controller: RemoteController

    var body: some View {
        HStack(spacing: 0) {
            HoldButton(controller: controller, command: .volumeDown) {
                Image(systemName: "minus")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: RemoteMetrics.buttonHeight)
                    .contentShape(Rectangle())
            }
            .help("Volume Down (−)")

            Rectangle()
                .fill(.separator)
                .frame(width: 1, height: RemoteMetrics.buttonHeight * 0.5)

            HoldButton(controller: controller, command: .volumeUp) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: RemoteMetrics.buttonHeight)
                    .contentShape(Rectangle())
            }
            .help("Volume Up (+)")
        }
        .surface(Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Volume")
    }
}

private struct RemoteGlyph: View {
    let systemImage: String
    var tint: Color?

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(tint ?? .primary)
            .frame(maxWidth: .infinity)
            .frame(height: RemoteMetrics.buttonHeight)
    }
}

/// A button that reports press and release separately.
private struct HoldButton<Label: View>: View {
    let controller: RemoteController
    let command: HIDCommand
    var feedback: RemotePressStyle.Feedback = .dim
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: {}) {
            label()
        }
        .buttonStyle(
            RemotePressStyle(feedback: feedback) { pressed in
                if pressed {
                    controller.buttonDown(command)
                } else {
                    controller.buttonUp(command)
                }
            }
        )
        .accessibilityLabel(command.title)
    }
}

private struct RemotePressStyle: ButtonStyle {
    enum Feedback {
        /// Glass buttons: shrink and dim slightly while held.
        case dim
        /// Glyphs drawn directly on a surface: grow a little on hover, shrink
        /// and dim while held. No shape, so nothing fights the ring.
        case glyph(isHovered: Bool)
    }

    var feedback: Feedback = .dim
    var onPressChanged: ((Bool) -> Void)?

    func makeBody(configuration: Configuration) -> some View {
        styled(configuration)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                onPressChanged?(pressed)
            }
    }

    @ViewBuilder
    private func styled(_ configuration: Configuration) -> some View {
        switch feedback {
        case .dim:
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .opacity(configuration.isPressed ? 0.75 : 1)
        case .glyph(let isHovered):
            let scale: CGFloat = configuration.isPressed ? 0.85 : (isHovered ? 1.15 : 1)
            configuration.label
                .scaleEffect(scale)
                .opacity(configuration.isPressed ? 0.6 : 1)
        }
    }
}

// MARK: - Keyboard

private struct RemoteKeyboardShortcuts: ViewModifier {
    let controller: RemoteController
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .onAppear {
                if controller.keyboardSession == nil {
                    DispatchQueue.main.async { isFocused = true }
                }
            }
            .onChange(of: controller.keyboardSession == nil) { _, keyboardHidden in
                if keyboardHidden { isFocused = true }
            }
            .onKeyPress(phases: .down) { press in
                handle(press)
            }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }

        let command: HIDCommand?
        switch press.key {
        case .upArrow: command = .up
        case .downArrow: command = .down
        case .leftArrow: command = .left
        case .rightArrow: command = .right
        case .return: command = .select
        case .delete: command = .menu
        case .space: command = .playPause
        default:
            switch press.characters.lowercased() {
            case "h", "t": command = .home
            case "p": command = .playPause
            case "+", "=": command = .volumeUp
            case "-", "_": command = .volumeDown
            case "m":
                controller.toggleMute()
                return .handled
            default: command = nil
            }
        }

        guard let command else { return .ignored }
        controller.press(command)
        return .handled
    }
}

extension View {
    func remoteKeyboardShortcuts(controller: RemoteController) -> some View {
        modifier(RemoteKeyboardShortcuts(controller: controller))
    }
}
