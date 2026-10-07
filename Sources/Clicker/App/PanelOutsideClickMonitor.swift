import AppKit

/// Dismisses the panel on clicks outside it, while leaving clicks on the status
/// item (which toggles), inside the panel, and in menus or popovers alone.
@MainActor
final class PanelOutsideClickMonitor {
    private let panel: NSPanel
    private let statusItem: NSStatusItem
    private let onDismiss: () -> Void
    private var monitors: [Any] = []

    init(panel: NSPanel, statusItem: NSStatusItem, onDismiss: @escaping () -> Void) {
        self.panel = panel
        self.statusItem = statusItem
        self.onDismiss = onDismiss
    }

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let windowID = event.window.map(ObjectIdentifier.init)
            let windowTypeName = event.window.map { String(describing: type(of: $0)) }
            let point = NSEvent.mouseLocation
            MainActor.assumeIsolated {
                self?.handleClick(windowID: windowID, windowTypeName: windowTypeName, screenPoint: point)
            }
            return event
        }) {
            monitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            let point = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                self?.handleClick(windowID: nil, windowTypeName: nil, screenPoint: point)
            }
        }) {
            monitors.append(global)
        }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
    }

    private func handleClick(windowID: ObjectIdentifier?, windowTypeName: String?, screenPoint: NSPoint) {
        if panel.frame.contains(screenPoint) { return }
        if windowID == ObjectIdentifier(panel) { return }
        if let buttonWindow = statusItem.button?.window, windowID == ObjectIdentifier(buttonWindow) { return }
        if isOnStatusButton(screenPoint) { return }
        if let name = windowTypeName?.lowercased(), name.contains("menu") || name.contains("popover") { return }
        onDismiss()
    }

    /// The status button is a little shorter than the menu bar, so treat the
    /// whole column up to the top of the screen as the button.
    private func isOnStatusButton(_ point: NSPoint) -> Bool {
        guard let button = statusItem.button, let window = button.window else { return false }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let top = max(frame.maxY, window.screen?.frame.maxY ?? frame.maxY)
        return point.x >= frame.minX && point.x <= frame.maxX && point.y >= frame.minY && point.y <= top
    }
}
