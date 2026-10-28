import AppKit
import SwiftUI

/// The About window: `AboutView` in a small titled window with only a close
/// button. One window for the app's lifetime, brought forward if already open.
///
/// Clicker is an accessory app and is not active while the window opens, so
/// it activates first; otherwise the window opens behind the frontmost app.
/// Callers hide the menu bar panel beforehand, since it floats at pop-up
/// menu level and would cover the window.
package final class AboutWindow: NSWindow {
    private static var shared: AboutWindow?

    package static func present() {
        let window = shared ?? AboutWindow()
        shared = window
        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    private init() {
        let hosting = NSHostingView(rootView: AboutView())
        // No title bar inset: the content sizes itself up to the window's top
        // edge, and the fitting size is then the window's size.
        hosting.safeAreaRegions = []
        super.init(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = String(localized: "About Clicker")
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        // Translucent like the menu bar panel: the desktop blurs through a
        // behind-window material, with the SwiftUI content on top.
        isOpaque = false
        backgroundColor = .clear
        let backdrop = NSVisualEffectView()
        backdrop.material = .popover
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        hosting.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: backdrop.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor),
        ])
        contentView = backdrop
    }

    /// Hands focus back to the app that was in front before About opened,
    /// so Clicker's menu bar doesn't linger with nothing of it on screen.
    /// Only when nothing else of Clicker's is up (a Sparkle window), and
    /// not under `--regular`, where Clicker is an ordinary app.
    package override func close() {
        super.close()
        let othersVisible = NSApp.windows.contains { $0 !== self && $0.isVisible && $0.canBecomeMain }
        if NSApp.activationPolicy() == .accessory, !othersVisible {
            NSApp.hide(nil)
        }
    }

    /// Esc closes, like the standard About panel.
    package override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }

    /// ⌘W closes too; an accessory app has no File menu to supply it.
    package override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == [.command], event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
