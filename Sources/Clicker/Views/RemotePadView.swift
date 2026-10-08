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
                // Apps and Power sit above the clickpad's top corners (Power
                // is there on the Siri Remote), with the ring's top edge
                // level with their centers.
                ClickpadView(controller: controller)
                    .padding(.top, RemoteMetrics.clickpadTopInset)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topLeading) { AppsMenu(controller: controller) }
                    .overlay(alignment: .topTrailing) { PowerMenu(controller: controller) }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    HoldRemoteButton(command: .menu, controller: controller)
                    HoldRemoteButton(command: .home, controller: controller)
                    HoldRemoteButton(command: .playPause, controller: controller)
                    MuteButton(controller: controller)
                    HoldRemoteButton(command: .siri, controller: controller)
                    VolumeRocker(controller: controller)
                }
            }
        }
    }
}

enum RemoteMetrics {
    static let buttonHeight: CGFloat = 44
    static let cornerButtonDiameter: CGFloat = 32
    /// The clickpad starts this far below the corner buttons' top edge, so
    /// the ring's top is level with their centers.
    static let clickpadTopInset: CGFloat = cornerButtonDiameter / 2

    /// One font for every glyph on the remote, with outline symbols
    /// throughout, so strokes read the same width from button to button.
    static let glyphFont: Font = .system(size: 16, weight: .medium)
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

                HoldButton(controller: controller, command: .select, shape: Circle()) {
                    Circle()
                        .fill(.clear)
                        .frame(width: ClickpadGeometry.selectDiameter, height: ClickpadGeometry.selectDiameter)
                }
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

        HoldButton(controller: controller, command: command, shape: shape, pressScale: 0.97) {
            Image(systemName: command.systemImage)
                .font(RemoteMetrics.glyphFont)
                .foregroundStyle(.primary)
                .offset(x: arrow.x, y: arrow.y)
                .frame(width: bounds.width, height: bounds.height)
        }
        .offset(x: bounds.midX, y: bounds.midY)
        .help(command.title)
    }
}

/// Capsule button that sends press and release separately.
private struct HoldRemoteButton: View {
    let command: HIDCommand
    let controller: RemoteController

    var body: some View {
        HoldButton(controller: controller, command: command, shape: Capsule()) {
            RemoteGlyph(systemImage: command.systemImage)
        }
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
            RemoteGlyph(systemImage: "speaker.slash", tint: controller.isMuted ? AnyShapeStyle(.orange) : nil)
        }
        .buttonStyle(SurfaceButtonStyle(shape: Capsule(), tint: controller.isMuted ? .orange : nil))
        .focusable(false)
        .focusEffectDisabled()
        .help(controller.isMuted ? "Unmute (M)" : "Mute (M)")
        .accessibilityLabel(controller.isMuted ? "Unmute" : "Mute")
    }
}

/// One capsule, two halves: volume down on the left, volume up on the right.
private struct VolumeRocker: View {
    let controller: RemoteController

    var body: some View {
        // One capsule of glass; each half highlights on its own and the
        // rocker does not shrink, since pressing half a capsule should not
        // move the other half.
        HStack(spacing: 0) {
            HoldButton(controller: controller, command: .volumeDown, shape: Rectangle(), glass: false, pressScale: 1) {
                RemoteGlyph(systemImage: "minus")
            }
            .help("Volume Down (−)")

            Rectangle()
                .fill(.separator)
                .frame(width: 1, height: RemoteMetrics.buttonHeight * 0.5)

            HoldButton(controller: controller, command: .volumeUp, shape: Rectangle(), glass: false, pressScale: 1) {
                RemoteGlyph(systemImage: "plus")
            }
            .help("Volume Up (+)")
        }
        .clipShape(Capsule())
        .surface(Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Volume")
    }
}

private struct RemoteGlyph: View {
    let systemImage: String
    var tint: AnyShapeStyle?

    var body: some View {
        Image(systemName: systemImage)
            .font(RemoteMetrics.glyphFont)
            .foregroundStyle(tint ?? AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity)
            .frame(height: RemoteMetrics.buttonHeight)
    }
}

/// A glass button that reports press and release separately.
private struct HoldButton<Shape: InsettableShape, Label: View>: View {
    let controller: RemoteController
    let command: HIDCommand
    let shape: Shape
    var glass = true
    var pressScale: CGFloat = 0.96
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: {}) {
            label()
        }
        .buttonStyle(
            SurfaceButtonStyle(shape: shape, glass: glass, pressScale: pressScale) { pressed in
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
            // The panel stays key under the Apps popover, so without this the
            // pad would swallow the keys meant for its search field.
            .onChange(of: controller.isAppPickerPresented) { _, pickerOpen in
                isFocused = !pickerOpen
            }
            .onKeyPress(phases: .down) { press in
                handle(press)
            }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
        guard !controller.isAppPickerPresented else { return .ignored }

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
