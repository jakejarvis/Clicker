import SwiftUI

/// The remote itself: a directional pad plus two rows of buttons. Every button
/// sends a HID "down" when pressed and "up" when released so holds work (Siri
/// in particular), and arrow/return/escape keys drive it from the keyboard.
struct RemotePadView: View {
    let controller: RemoteController

    var body: some View {
        VStack(spacing: 14) {
            DirectionalPad(controller: controller)
            HStack(spacing: 12) {
                RemoteButton(command: .menu, controller: controller)
                RemoteButton(command: .home, controller: controller)
                RemoteButton(command: .playPause, controller: controller)
            }
            HStack(spacing: 12) {
                RemoteButton(command: .volumeDown, controller: controller)
                RemoteButton(command: .volumeUp, controller: controller)
                RemoteButton(command: .siri, controller: controller, tint: .purple)
            }
            Text("Arrow keys, Return, Esc, Space, H, +/−")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .remoteKeyboardShortcuts(controller: controller)
    }
}

private struct DirectionalPad: View {
    let controller: RemoteController

    private let diameter: CGFloat = 176
    private let offset: CGFloat = 62

    var body: some View {
        ZStack {
            Circle()
                .fill(.quaternary)
                .frame(width: diameter, height: diameter)

            arrow(.up).offset(y: -offset)
            arrow(.down).offset(y: offset)
            arrow(.left).offset(x: -offset)
            arrow(.right).offset(x: offset)

            HoldButton(controller: controller, command: .select) {
                Circle()
                    .fill(.background)
                    .overlay(Circle().strokeBorder(.separator, lineWidth: 1))
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
            }
            .help("Select (Return)")
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Directional pad")
    }

    private func arrow(_ command: HIDCommand) -> some View {
        HoldButton(controller: controller, command: command) {
            Image(systemName: command.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .help(command.title)
    }
}

private struct RemoteButton: View {
    let command: HIDCommand
    let controller: RemoteController
    var tint: Color?

    var body: some View {
        HoldButton(controller: controller, command: command) {
            Image(systemName: command.systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint ?? .primary)
                .frame(width: 56, height: 40)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .help(command == .siri ? "Hold for Siri" : command.title)
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
        .buttonStyle(PressReportingButtonStyle { pressed in
            if pressed {
                controller.buttonDown(command)
            } else {
                controller.buttonUp(command)
            }
        })
        .accessibilityLabel(command.title)
        .accessibilityAddTraits(.isButton)
    }
}

private struct PressReportingButtonStyle: ButtonStyle {
    let onPressChanged: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                onPressChanged(pressed)
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
                DispatchQueue.main.async { isFocused = true }
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
        case .escape, .delete: command = .menu
        case .space: command = .playPause
        default:
            switch press.characters.lowercased() {
            case "h", "t": command = .home
            case "p": command = .playPause
            case "+", "=": command = .volumeUp
            case "-", "_": command = .volumeDown
            case "m": command = .menu
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
