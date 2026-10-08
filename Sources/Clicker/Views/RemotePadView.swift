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
                ClickpadView(controller: controller)
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
                .frame(width: diameter, height: diameter)

            directionButton(.up).offset(y: -markOffset)
            directionButton(.down).offset(y: markOffset)
            directionButton(.left).offset(x: -markOffset)
            directionButton(.right).offset(x: markOffset)

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

    private func directionButton(_ command: HIDCommand) -> some View {
        HoldButton(controller: controller, command: command) {
            Image(systemName: command.systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
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
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: {}) {
            label()
        }
        .buttonStyle(
            RemotePressStyle { pressed in
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
    var onPressChanged: ((Bool) -> Void)?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                onPressChanged?(pressed)
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
