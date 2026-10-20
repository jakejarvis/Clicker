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
struct PopoverAppearance: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowAppearanceView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowAppearanceView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // The app's appearance, not the window's: once set, the window's
            // own would only echo back what an earlier presentation pinned.
            let plain = NSApp.effectiveAppearance.bestMatch(from: [
                .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
            ])
            window.appearance = plain.flatMap(NSAppearance.init(named:))
        }
    }
}

extension View {
    /// See `PopoverAppearance`. Apply to a popover's root content.
    @ViewBuilder
    func popoverAppearance() -> some View {
        if #available(macOS 26, *) {
            background(PopoverAppearance())
        } else {
            self
        }
    }
}
