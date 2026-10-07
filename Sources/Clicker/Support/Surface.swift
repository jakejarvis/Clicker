import SwiftUI

/// Interactive surfaces use Liquid Glass on macOS 26 and system materials on
/// macOS 15, so the rest of the UI never branches on OS version.
extension View {
    func surface<S: InsettableShape>(_ shape: S, interactive: Bool = true, tint: Color? = nil) -> some View {
        modifier(SurfaceModifier(shape: shape, interactive: interactive, tint: tint))
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

private struct SurfaceModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let tint: Color?

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            let glass: Glass = .regular.tint(tint).interactive(interactive)
            content.glassEffect(glass, in: shape)
        } else {
            content
                .background(fallbackFill, in: shape)
                .overlay(shape.strokeBorder(fallbackStroke, lineWidth: 1))
        }
    }

    private var fallbackFill: AnyShapeStyle {
        if let tint { return AnyShapeStyle(tint.opacity(0.18)) }
        return AnyShapeStyle(.quaternary)
    }

    private var fallbackStroke: Color {
        tint?.opacity(0.35) ?? .clear
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
