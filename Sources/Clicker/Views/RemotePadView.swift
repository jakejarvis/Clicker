import SwiftUI

/// The remote itself: a clickpad ring with a large Select in the middle and
/// two columns of buttons below. Every button sends HID "down" on press and
/// "up" on release so holds work (Siri in particular).
struct RemotePadView: View {
    let controller: RemoteController

    var body: some View {
        SurfaceContainer(spacing: 10) {
            VStack(spacing: 16) {
                ClickpadView(controller: controller)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    RemoteButton(command: .menu, controller: controller)
                    RemoteButton(command: .home, controller: controller)
                    RemoteButton(command: .playPause, controller: controller)
                    RemoteButton(command: .siri, controller: controller, tint: .purple)
                    RemoteButton(command: .volumeDown, controller: controller)
                    RemoteButton(command: .volumeUp, controller: controller)
                }
            }
        }
        .remoteKeyboardShortcuts(controller: controller)
    }
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

private struct RemoteButton: View {
    let command: HIDCommand
    let controller: RemoteController
    var tint: Color?

    var body: some View {
        HoldButton(controller: controller, command: command) {
            Image(systemName: command.systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint ?? .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Capsule())
        }
        .surface(Capsule())
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
    }
}

private struct PressReportingButtonStyle: ButtonStyle {
    let onPressChanged: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
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
