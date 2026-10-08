import SwiftUI

/// The remote itself: a clickpad ring with a large Select in the middle, a
/// navigation row and a media row below it, and one audio bar (mute, volume
/// down, volume up) along the bottom. Every button sends HID "down" on press
/// and "up" on release so holds work (Siri in particular).
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
                VStack(spacing: 10) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        HoldRemoteButton(command: .menu, controller: controller)
                        HoldRemoteButton(command: .home, controller: controller)
                        HoldRemoteButton(command: .playPause, controller: controller)
                        HoldRemoteButton(command: .siri, controller: controller)
                    }
                    AudioBar(controller: controller)
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
        // One ring of glass with Select in its hole, like the volume rocker. The
        // container spacing stays under the 3pt channel so the two do not merge.
        SurfaceContainer(spacing: 1) {
            ZStack {
                ClickpadRingView(controller: controller)

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

/// The four directions as one control: a glass ring that works out the
/// quadrant from the pointer itself, so hover, press and the highlight all
/// come from the same `ClickpadGeometry.direction(at:)`. A press sends HID
/// down for the quadrant it started in and up on release, wherever the
/// pointer went in between.
private struct ClickpadRingView: View {
    let controller: RemoteController
    @State private var hovered: ClickpadGeometry.Direction?
    @State private var pressed: ClickpadGeometry.Direction?

    var body: some View {
        let highlight = pressed ?? hovered
        let center = CGPoint(x: ClickpadGeometry.outerRadius, y: ClickpadGeometry.outerRadius)

        ZStack {
            if let highlight {
                ClickpadQuadrant(direction: highlight)
                    .fill(
                        .primary.opacity(
                            pressed == nil ? SurfaceHighlight.hovered.opacity : SurfaceHighlight.pressed.opacity))
            }
            ForEach(ClickpadGeometry.Direction.allCases, id: \.self) { direction in
                Image(systemName: direction.command.systemImage)
                    .font(RemoteMetrics.glyphFont)
                    .foregroundStyle(.primary)
                    .offset(
                        x: direction.unit.x * ClickpadGeometry.arrowRadius,
                        y: direction.unit.y * ClickpadGeometry.arrowRadius)
            }
        }
        .frame(width: ClickpadGeometry.diameter, height: ClickpadGeometry.diameter)
        .contentShape(ClickpadRing())
        .surface(ClickpadRing())
        .animation(.easeOut(duration: 0.1), value: highlight)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): hovered = ClickpadGeometry.direction(at: location, center: center)
            case .ended: hovered = nil
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard pressed == nil,
                        let direction = ClickpadGeometry.direction(at: value.startLocation, center: center)
                    else { return }
                    pressed = direction
                    controller.buttonDown(direction.command)
                }
                .onEnded { _ in
                    guard let direction = pressed else { return }
                    pressed = nil
                    controller.buttonUp(direction.command)
                }
        )
        .help(hovered?.command.title ?? "")
        .accessibilityChildren {
            ForEach(ClickpadGeometry.Direction.allCases, id: \.self) { direction in
                Button(direction.command.title) { controller.press(direction.command) }
            }
        }
    }
}

extension ClickpadGeometry.Direction {
    fileprivate var command: HIDCommand {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        }
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

/// One capsule, three segments, in the order of the Mac's own media keys:
/// mute, volume down, volume up. Each segment highlights on its own and the
/// bar does not shrink, since pressing one segment should not move the rest.
private struct AudioBar: View {
    let controller: RemoteController

    var body: some View {
        HStack(spacing: 0) {
            MuteSegment(controller: controller)

            AudioBarDivider()

            HoldButton(controller: controller, command: .volumeDown, shape: Rectangle(), glass: false, pressScale: 1) {
                RemoteGlyph(systemImage: "speaker.minus")
            }
            .help("Volume Down (−)")

            AudioBarDivider()

            HoldButton(controller: controller, command: .volumeUp, shape: Rectangle(), glass: false, pressScale: 1) {
                RemoteGlyph(systemImage: "speaker.plus")
            }
            .help("Volume Up (+)")
        }
        .clipShape(Capsule())
        .surface(Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Audio")
    }
}

private struct AudioBarDivider: View {
    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 1, height: RemoteMetrics.buttonHeight * 0.5)
    }
}

/// Toggles software mute (volume to zero and back). While muted the glyph
/// and its own segment turn orange; the rest of the bar stays untinted so
/// the tint reads as a state of mute, not of volume.
private struct MuteSegment: View {
    let controller: RemoteController

    var body: some View {
        Button {
            controller.toggleMute()
        } label: {
            RemoteGlyph(systemImage: "speaker.slash", tint: controller.isMuted ? AnyShapeStyle(.orange) : nil)
                .background(Color.orange.opacity(controller.isMuted ? 0.18 : 0))
        }
        .buttonStyle(SurfaceButtonStyle(shape: Rectangle(), glass: false, pressScale: 1))
        .focusable(false)
        .focusEffectDisabled()
        .help(controller.isMuted ? "Unmute (M)" : "Mute (M)")
        .accessibilityLabel(controller.isMuted ? "Unmute" : "Mute")
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
