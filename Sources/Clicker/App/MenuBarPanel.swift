import AppKit

/// A borderless, non-activating panel that can still become key, so keystrokes
/// reach the remote the moment it opens without activating the app.
final class MenuBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Dimensions shared by the panel and the SwiftUI content inside it.
enum PanelMetrics {
    static let width: CGFloat = 264
    /// One radius for the panel and the controls inside it.
    static let cornerRadius: CGFloat = 14
    static let innerCornerRadius: CGFloat = 10
    static let horizontalPadding: CGFloat = 14
    /// Height of the device picker.
    static let headerControlHeight: CGFloat = 46
}

/// Pure panel geometry, separate from the window so it can be unit tested.
enum PanelGeometry {
    static let topGap: CGFloat = 5
    static let screenMargin: CGFloat = 8
    static let minimumHeight: CGFloat = 120

    /// Centers the panel under the status item, kept inside the screen.
    static func topLeft(below buttonRect: NSRect, width: CGFloat, visibleFrame: NSRect?) -> NSPoint {
        var x = buttonRect.midX - width / 2
        if let visibleFrame {
            x = min(max(x, visibleFrame.minX + screenMargin), visibleFrame.maxX - width - screenMargin)
        }
        return NSPoint(x: x.rounded(), y: buttonRect.minY - topGap)
    }

    static func maximumHeight(topLeft: NSPoint, visibleFrame: NSRect) -> CGFloat {
        max(minimumHeight, topLeft.y - visibleFrame.minY - screenMargin)
    }

    static func clampedHeight(_ height: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(height, minimumHeight), maximum)
    }

    /// Whole-point frame anchored at the top-left so height changes grow downward.
    static func frame(topLeft: NSPoint, width: CGFloat, height: CGFloat) -> NSRect {
        let top = topLeft.y.rounded(.down)
        let height = height.rounded()
        return NSRect(x: topLeft.x, y: top - height, width: width, height: height)
    }
}

/// The panel's background: Liquid Glass on macOS 26, behind-window vibrancy
/// before that, both clipped to the shared corner radius.
final class PanelBackdropView: NSView {
    init(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let backdrop: NSView
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            backdrop = glass
        } else {
            let vibrancy = NSVisualEffectView()
            vibrancy.material = .popover
            vibrancy.blendingMode = .behindWindow
            vibrancy.state = .active
            vibrancy.wantsLayer = true
            vibrancy.maskImage = Self.roundedMask(cornerRadius: cornerRadius)
            backdrop = vibrancy
        }
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Stretchable rounded mask so behind-window blur keeps crisp corners.
    private static func roundedMask(cornerRadius: CGFloat) -> NSImage {
        let side = cornerRadius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }
}
