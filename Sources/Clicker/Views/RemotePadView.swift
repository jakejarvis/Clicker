import SwiftUI

/// The remote itself: a clickpad ring with a large Select in the middle and
/// two columns of buttons below, laid out like the Siri Remote. Every button
/// sends HID "down" on press and "up" on release so holds work (Siri in
/// particular).
struct RemotePadView: View {
    let controller: RemoteController
    /// False while the remote is ghosted behind an overlay card: no keyboard
    /// focus, so the card's own fields can take it.
    var isInteractive = true

    @ViewBuilder
    var body: some View {
        if isInteractive {
            pad.remoteKeyboardShortcuts(controller: controller)
        } else {
            pad
        }
    }

    private var pad: some View {
        SurfaceContainer(spacing: 10) {
            VStack(spacing: 16) {
                // Apps and Power float at the clickpad's top corners (Power is
                // there on the Siri Remote). Sized so they clear the ring.
                ClickpadView(controller: controller)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topLeading) { AppsMenu(controller: controller) }
                    .overlay(alignment: .topTrailing) { PowerMenu(controller: controller) }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    HoldRemoteButton(command: .menu, controller: controller)
                    HoldRemoteButton(command: .home, controller: controller)
                    HoldRemoteButton(command: .playPause, controller: controller)
                    MuteButton(controller: controller)
                    // The orb is an outline, so it needs extra size and weight
                    // to sit evenly next to the filled glyphs around it.
                    HoldRemoteButton(
                        command: .siri, controller: controller, tint: RemoteMetrics.siriTint, size: 18,
                        weight: .semibold)
                    VolumeRocker(controller: controller)
                }
            }
        }
    }
}

enum RemoteMetrics {
    static let buttonHeight: CGFloat = 44
    static let cornerButtonDiameter: CGFloat = 32

    /// Siri's orb colors. SF Symbols has no colored Siri glyph, so the
    /// gradient is painted through the symbol instead.
    static let siriTint = AnyShapeStyle(
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.36, blue: 0.62),
                Color(red: 0.62, green: 0.36, blue: 0.98),
                Color(red: 0.25, green: 0.65, blue: 1.0),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing))
}

private struct ClickpadView: View {
    let controller: RemoteController

    var body: some View {
        // Its own glass container with a tight spacing: the sectors and Select
        // are 6pt apart and must stay distinct instead of blending.
        SurfaceContainer(spacing: 3) {
            ZStack {
                ForEach(ClickpadGeometry.Direction.allCases, id: \.self) { direction in
                    DirectionButton(controller: controller, direction: direction)
                }

                HoldButton(controller: controller, command: .select) {
                    Circle()
                        .fill(.clear)
                        .frame(width: ClickpadGeometry.selectDiameter, height: ClickpadGeometry.selectDiameter)
                        .contentShape(Circle())
                }
                .surface(Circle())
                .help("Select (Return)")
            }
            .frame(width: ClickpadGeometry.diameter, height: ClickpadGeometry.diameter)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clickpad")
    }
}

/// One sector of the clickpad: a glass annular sector with an arrow at the
/// middle of the band. The button is framed to the sector's bounding box so
/// tooltips, press scaling and accessibility frames match what is drawn.
private struct DirectionButton: View {
    let controller: RemoteController
    let direction: ClickpadGeometry.Direction

    private var command: HIDCommand {
        switch direction {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        }
    }

    var body: some View {
        let shape = ClickpadSegment(direction: direction)
        let bounds = ClickpadGeometry.bounds(for: direction)
        let arrow = CGPoint(
            x: direction.unit.x * ClickpadGeometry.arrowRadius - bounds.midX,
            y: direction.unit.y * ClickpadGeometry.arrowRadius - bounds.midY)

        HoldButton(controller: controller, command: command, feedback: .dim(scale: 0.97)) {
            Image(systemName: command.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .offset(x: arrow.x, y: arrow.y)
                .frame(width: bounds.width, height: bounds.height)
                .contentShape(shape)
        }
        .surface(shape)
        .offset(x: bounds.midX, y: bounds.midY)
        .help(command.title)
    }
}

/// Capsule button that sends press and release separately.
private struct HoldRemoteButton: View {
    let command: HIDCommand
    let controller: RemoteController
    var tint: AnyShapeStyle?
    var size: CGFloat = 16
    var weight: Font.Weight = .medium

    var body: some View {
        HoldButton(controller: controller, command: command) {
            RemoteGlyph(systemImage: command.systemImage, tint: tint, size: size, weight: weight)
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
                tint: controller.isMuted ? AnyShapeStyle(.orange) : nil
            )
            .contentShape(Capsule())
        }
        .buttonStyle(RemotePressStyle())
        .focusable(false)
        .focusEffectDisabled()
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
    var tint: AnyShapeStyle?
    var size: CGFloat = 16
    var weight: Font.Weight = .medium

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(tint ?? AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity)
            .frame(height: RemoteMetrics.buttonHeight)
    }
}

/// A button that reports press and release separately.
private struct HoldButton<Label: View>: View {
    let controller: RemoteController
    let command: HIDCommand
    var feedback: RemotePressStyle.Feedback = .dim()
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
        // Keyboard input goes through the pad's shortcuts, not focus, and a
        // focus ring traced around a sector looks broken.
        .focusable(false)
        .focusEffectDisabled()
        .accessibilityLabel(command.title)
    }
}

private struct RemotePressStyle: ButtonStyle {
    enum Feedback {
        /// Shrink to `scale` and dim slightly while held.
        case dim(scale: CGFloat = 0.94)
    }

    var feedback: Feedback = .dim()
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
        case .dim(let scale):
            configuration.label
                .scaleEffect(configuration.isPressed ? scale : 1)
                .opacity(configuration.isPressed ? 0.75 : 1)
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
