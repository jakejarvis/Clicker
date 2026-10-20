import AppKit
import SwiftUI

/// Gives a SwiftUI popover's window the plain counterpart of its vibrant
/// appearance on macOS 26 and later.
///
/// SwiftUI still sets popover windows to the vibrant appearance that the
/// pre-glass popover material blended, but a glass popover blends nothing, so
/// AppKit draws vibrant colors in it as they are: an overlay scroller's track
/// comes out solid near-black (`#141414`) and its knob opaque gray, where the
/// plain appearance draws them translucent white. macOS 15 keeps the vibrant
/// appearance, which its popover material does blend.
struct PlainPopoverAppearance: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowAppearanceView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowAppearanceView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            let plain = window.effectiveAppearance.bestMatch(from: [
                .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
            ])
            window.appearance = plain.flatMap(NSAppearance.init(named:))
        }
    }
}

extension View {
    /// See `PlainPopoverAppearance`. Apply to a popover's root content. The
    /// popover window is never key, and with the plain appearance `.selection`
    /// would fall back to its gray inactive fill, so the content is told it
    /// is active as the vibrant appearance implied.
    @ViewBuilder
    func plainPopoverAppearance() -> some View {
        if #available(macOS 26, *) {
            background(PlainPopoverAppearance())
                .environment(\.controlActiveState, .key)
        } else {
            self
        }
    }
}
