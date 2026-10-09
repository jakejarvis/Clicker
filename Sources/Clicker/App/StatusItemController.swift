import AppKit
import SwiftUI

/// Owns the menu bar status item and the panel that hosts the remote.
///
/// Deliberately not `MenuBarExtra`: its window is system chrome with no control
/// over corner radius, size animation or key status. A plain `NSStatusItem`
/// plus a key-capable `NSPanel` gives all three.
@MainActor
final class StatusItemController: NSObject {
    private let controller: RemoteController
    private let updates: UpdateController
    private let statusItem: NSStatusItem
    private let panel: MenuBarPanel
    private let hosting: NSHostingController<MenuBarView>
    private let rootViewController = PanelRootViewController()
    private lazy var outsideClickMonitor = PanelOutsideClickMonitor(
        panel: panel,
        statusItem: statusItem,
        onDismiss: { [weak self] in self?.hidePanel() }
    )
    private var keyMonitor: Any?
    private var anchorTopLeft: NSPoint?
    private var anchorScreen: NSScreen?

    init(controller: RemoteController, updates: UpdateController) {
        self.controller = controller
        self.updates = updates
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        hosting = NSHostingController(rootView: MenuBarView(controller: controller, updates: updates))
        hosting.sizingOptions = [.preferredContentSize]
        panel = MenuBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: PanelMetrics.width, height: 480),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        configurePanel()
        configureStatusItem()
        installKeyMonitor()
        updateStatusImage()
        updates.onWillPresent = { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.hidePanel()
        }
        controller.dismissPanel = { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.hidePanel()
        }
    }

    // MARK: - Configuration

    private func configurePanel() {
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // The window server derives the shadow from the window's alpha; without
        // this clip the glass leaves the corners opaque and the shadow square.
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = PanelMetrics.cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        let backdrop = PanelBackdropView(cornerRadius: PanelMetrics.cornerRadius)
        let host = hosting.view
        host.translatesAutoresizingMaskIntoConstraints = false
        host.wantsLayer = true
        host.layerContentsRedrawPolicy = .duringViewResize
        host.layer?.cornerRadius = PanelMetrics.cornerRadius
        host.layer?.cornerCurve = .continuous
        host.layer?.masksToBounds = true

        container.addSubview(backdrop)
        container.addSubview(host, positioned: .above, relativeTo: backdrop)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: container.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        rootViewController.view = container
        rootViewController.addChild(hosting)
        rootViewController.onPreferredHeightChange = { [weak self] height in
            self?.applyHeight(height, animated: true)
        }
        panel.contentViewController = rootViewController
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusButtonClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Clicker"
    }

    /// Filled glyph while connected, outlined otherwise, with a dot while an
    /// update is waiting; re-armed on each change.
    private func updateStatusImage() {
        let (iconName, hasUpdate) = withObservationTracking {
            (controller.menuBarIconName, updates.pendingUpdateVersion != nil)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.updateStatusImage() }
        }
        guard let glyph = Self.statusIcon(named: iconName) else { return }
        statusItem.button?.image = Self.statusImage(glyph, badged: hasUpdate)
    }

    /// PDF glyphs from Resources/StatusIcon (see script/make_status_icons.swift),
    /// loaded once each: an `NSImage` caches its rasterization, so re-reading
    /// the PDF on every connection change would rasterize it again. Falls back
    /// to an SF Symbol when run outside the app bundle.
    private static var statusIcons: [String: NSImage] = [:]

    private static func statusIcon(named name: String) -> NSImage? {
        if let cached = statusIcons[name] { return cached }
        let image: NSImage?
        if let url = Bundle.main.url(forResource: name, withExtension: "pdf", subdirectory: "StatusIcon"),
            let pdf = NSImage(contentsOf: url)
        {
            pdf.accessibilityDescription = "Clicker"
            image = pdf
        } else {
            let symbol = name == "Connected" ? "appletvremote.gen4.fill" : "appletvremote.gen4"
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Clicker")
        }
        statusIcons[name] = image
        return image
    }

    /// The glyph centered with side padding (the remote is narrow, so it would
    /// otherwise sit cramped next to wider items), plus a small dot at its
    /// top-right corner while an update is waiting, cut out of the glyph so it
    /// reads on its own. The dot sits inside the padding, so the width holds.
    private static func statusImage(_ glyph: NSImage, badged: Bool) -> NSImage {
        let padding: CGFloat = 4
        let diameter: CGFloat = 6
        let size = NSSize(width: glyph.size.width + padding * 2, height: glyph.size.height)
        let glyphRect = NSRect(origin: NSPoint(x: padding, y: 0), size: glyph.size)
        let image = NSImage(size: size, flipped: false) { _ in
            glyph.draw(in: glyphRect)
            guard badged else { return true }
            let dot = NSRect(
                x: glyphRect.maxX - diameter / 2, y: size.height - diameter,
                width: diameter, height: diameter)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = badged ? "Clicker, update available" : "Clicker"
        return image
    }

    // MARK: - Keyboard

    /// Esc, ⌘, and ⌘Q ride a local monitor: SwiftUI shortcuts are unreliable
    /// in a panel that is key without the app being active.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let windowID = event.window.map(ObjectIdentifier.init)
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.panel.isVisible, windowID == ObjectIdentifier(self.panel) else { return false }
                switch (keyCode, modifiers) {
                case (53, []):  // Escape
                    if self.panel.firstResponder is NSText { return false }
                    if self.controller.handleEscape() { return true }
                    self.hidePanel()
                    return true
                case (43, [.command]):  // ⌘,
                    withAnimation(.snappy(duration: 0.3)) { self.controller.screen = .settings }
                    return true
                case (12, [.command]):  // ⌘Q
                    NSApp.terminate(nil)
                    return true
                default:
                    return false
                }
            }
            return consumed ? nil : event
        }
    }

    // MARK: - Show / hide

    @objc private func statusButtonClicked() {
        let event = NSApp.currentEvent
        let isContextClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isContextClick {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func showContextMenu() {
        if panel.isVisible { hidePanel() }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        if updates.isEnabled {
            let title = updates.pendingUpdateVersion.map { "Update to \($0)…" } ?? "Check for Updates…"
            let check = NSMenuItem(title: title, action: #selector(checkForUpdates), keyEquivalent: "")
            check.target = self
            check.isEnabled = updates.canCheckForUpdates
            menu.addItem(check)
        }
        let about = NSMenuItem(title: "About Clicker", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Clicker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func checkForUpdates() {
        updates.checkForUpdates()
    }

    @objc private func showAbout() {
        AboutPanel.present()
    }

    @objc private func openSettings() {
        controller.screen = .settings
        if !panel.isVisible { showPanel() }
    }

    func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = NSScreen.screens.first { $0.frame.intersects(buttonRect) } ?? NSScreen.main
        anchorScreen = screen
        anchorTopLeft = PanelGeometry.topLeft(
            below: buttonRect, width: PanelMetrics.width, visibleFrame: screen?.visibleFrame)

        controller.panelDidAppear()
        let fitting = hosting.sizeThatFits(in: NSSize(width: PanelMetrics.width, height: .greatestFiniteMagnitude))
        applyHeight(fitting.height, animated: false)
        hosting.view.layoutSubtreeIfNeeded()

        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(nil)
        button.highlight(true)
        outsideClickMonitor.start()
    }

    private func hidePanel() {
        panel.orderOut(nil)
        outsideClickMonitor.stop()
        statusItem.button?.highlight(false)
        controller.panelDidDisappear()
    }

    private func applyHeight(_ rawHeight: CGFloat, animated: Bool) {
        guard rawHeight > 1, let anchorTopLeft else { return }
        let visibleFrame = (anchorScreen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maximum = PanelGeometry.maximumHeight(topLeft: anchorTopLeft, visibleFrame: visibleFrame)
        let height = PanelGeometry.clampedHeight(rawHeight, maximum: maximum)
        let frame = PanelGeometry.frame(topLeft: anchorTopLeft, width: PanelMetrics.width, height: height)
        guard abs(panel.frame.height - frame.height) > 0.5 || panel.frame.origin != frame.origin else { return }

        if animated, panel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self] in
                // NSAnimationContext calls back on the main thread.
                MainActor.assumeIsolated { self?.panel.invalidateShadow() }
            }
        } else {
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
        }
    }
}

/// Container for the hosting controller that forwards SwiftUI's preferred
/// content size so the panel can follow the content's height.
private final class PanelRootViewController: NSViewController {
    var onPreferredHeightChange: ((CGFloat) -> Void)?

    override func loadView() {
        view = NSView()
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        onPreferredHeightChange?(viewController.preferredContentSize.height)
    }
}
