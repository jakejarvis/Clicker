import SwiftUI

/// Interactive surfaces use Liquid Glass on macOS 26 and system materials on
/// macOS 15, so the rest of the UI never branches on OS version.
extension View {
    func surface<S: InsettableShape>(
        _ shape: S, interactive: Bool = true, tint: Color? = nil, highlight: SurfaceHighlight = .none
    ) -> some View {
        modifier(SurfaceModifier(shape: shape, interactive: interactive, tint: tint, highlight: highlight))
    }

    /// Prominent call to action (Pair, Try Again).
    @ViewBuilder
    func prominentActionStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}

/// Pointer state a surface reflects: a wash of the primary color over the
/// material, so it brightens in dark mode and darkens in light mode like
/// system buttons do.
enum SurfaceHighlight {
    case none, hovered, pressed

    var opacity: Double {
        switch self {
        case .none: return 0
        case .hovered: return 0.1
        case .pressed: return 0.18
        }
    }
}

private struct SurfaceModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let tint: Color?
    let highlight: SurfaceHighlight

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let highlighted = content.background(shape.fill(.primary.opacity(highlight.opacity)))
        if #available(macOS 26, *) {
            let glass: Glass = .regular.tint(glassTint).interactive(interactive)
            highlighted.glassEffect(glass, in: shape)
        } else {
            highlighted
                .background(fallbackFill, in: shape)
                .overlay(shape.strokeBorder(fallbackStroke, lineWidth: 1))
        }
    }

    /// Untinted glass over a dark panel is nearly the panel's own shade, so
    /// dark mode gets a faint white wash to lift controls off the backdrop.
    private var glassTint: Color? {
        if let tint { return tint }
        return colorScheme == .dark ? Color.white.opacity(0.12) : nil
    }

    private var fallbackFill: AnyShapeStyle {
        if let tint { return AnyShapeStyle(tint.opacity(0.18)) }
        return AnyShapeStyle(.quaternary)
    }

    private var fallbackStroke: Color {
        tint?.opacity(0.35) ?? .clear
    }
}

/// Button style for the panel's controls. The surface is part of the button,
/// so hover and press highlight the whole shape, the whole control shrinks
/// while held, and a disabled control keeps its shape but fades its label.
/// With `glass` off only the highlight is drawn, for buttons that sit inside
/// another surface (volume rocker halves) or on the panel itself (footer).
struct SurfaceButtonStyle<S: InsettableShape>: ButtonStyle {
    var shape: S
    var tint: Color? = nil
    var glass = true
    var pressScale: CGFloat = 0.96
    /// Called with `true` on press and `false` on release.
    var onPressChanged: ((Bool) -> Void)? = nil

    func makeBody(configuration: Configuration) -> some View {
        SurfaceButtonBody(configuration: configuration, style: self)
    }
}

private struct SurfaceButtonBody<S: InsettableShape>: View {
    let configuration: ButtonStyleConfiguration
    let style: SurfaceButtonStyle<S>

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    private var highlight: SurfaceHighlight {
        guard isEnabled else { return .none }
        if configuration.isPressed { return .pressed }
        return isHovered ? .hovered : .none
    }

    private var isPressed: Bool { isEnabled && configuration.isPressed }

    var body: some View {
        let label = configuration.label
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(style.shape)
        Group {
            if style.glass {
                label.surface(style.shape, tint: style.tint, highlight: highlight)
            } else {
                label.background(style.shape.fill(.primary.opacity(highlight.opacity)))
            }
        }
        .scaleEffect(isPressed ? style.pressScale : 1)
        .animation(.easeOut(duration: 0.1), value: isPressed)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .onChange(of: configuration.isPressed) { _, pressed in
            style.onPressChanged?(pressed)
        }
    }
}

extension View {
    /// Quiet, non-interactive container for grouped content (settings cards).
    /// Flat so it reads as a tray, not as another glass button.
    func card() -> some View {
        let shape = RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
        return background(.quaternary.opacity(0.55), in: shape)
            .overlay(shape.strokeBorder(.separator.opacity(0.6), lineWidth: 1))
    }
}

/// Groups glass surfaces so neighbouring shapes blend; a no-op on macOS 15.
struct SurfaceContainer<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}
