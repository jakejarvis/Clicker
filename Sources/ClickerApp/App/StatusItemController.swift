import AppKit
import KeyboardShortcuts
import SwiftUI

/// Owns the menu bar status item and the panel that hosts the remote.
///
/// Deliberately not `MenuBarExtra`: its window is system chrome with no control
/// over corner radius, size animation or key status. A plain `NSStatusItem`
/// plus a key-capable `NSPanel` gives all three.
final class StatusItemController: NSObject {
    private let controller: RemoteController
    private let updates: UpdateController
    private let statusItem: NSStatusItem
    private let panel: MenuBarPanel
    private let hosting: NSHostingController<MenuBarView>
    private lazy var outsideClickMonitor = PanelOutsideClickMonitor(
        panel: panel,
        statusItem: statusItem,
        onDismiss: { [weak self] in self?.hidePanel() }
    )
    private var keyMonitor: Any?
    /// Where the panel hangs from while it is open; nil while hidden, so a
    /// height pushed for a hidden panel goes nowhere.
    private var anchorTopLeft: NSPoint?
    private var anchorScreen: NSScreen?
    private var anchorAlignment = PanelAlignment.right
    private var defaultsObserver: NSObjectProtocol?
    private var shadowSettleTask: Task<Void, Never>?

    init(controller: RemoteController, updates: UpdateController) {
        self.controller = controller
        self.updates = updates
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        hosting = NSHostingController(rootView: MenuBarView(controller: controller, updates: updates))
        // No intrinsic size: with one, autolayout grows the window to fit the
        // content the moment a taller screen mounts (its compression resistance
        // outranks the window's own size), ahead of the animated frames.
        hosting.sizingOptions = []
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
        installHotKey()
        updateStatusImage()
        updates.onWillPresent = { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.hidePanel()
        }
        controller.dismissPanel = { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.hidePanel()
        }
        // The content's height, one frame at a time (see PanelHeightBridge).
        PanelHeightBridge.apply = { [weak self] height in
            self?.applyHeight(height)
        }
        // Settings changes the alignment while the panel is open, so move it
        // there at once rather than on the next open.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.followAlignmentChange() }
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

        // A plain container owns the backdrop; the hosting controller is its
        // child so SwiftUI gets a proper view controller hierarchy.
        let rootViewController = NSViewController()
        rootViewController.view = container
        rootViewController.addChild(hosting)
        panel.contentViewController = rootViewController
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusButtonClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Clicker"
    }

    /// Filled glyph while connected, outlined otherwise; re-armed on each
    /// change. A pending update shows in the panel's footer, not here.
    private func updateStatusImage() {
        let iconName = withObservationTracking {
            controller.menuBarIconName
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.updateStatusImage() }
        }
        guard let glyph = Self.statusIcon(named: iconName) else { return }
        statusItem.button?.image = Self.statusImage(glyph)
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

    /// The glyph centered with side padding: the remote is narrow, so it
    /// would otherwise sit cramped next to wider items.
    private static func statusImage(_ glyph: NSImage) -> NSImage {
        let padding: CGFloat = 4
        let size = NSSize(width: glyph.size.width + padding * 2, height: glyph.size.height)
        let image = NSImage(size: size, flipped: false) { _ in
            glyph.draw(in: NSRect(origin: NSPoint(x: padding, y: 0), size: glyph.size))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Clicker"
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
                // The Settings shortcut row takes every key while recording,
                // so a chord recorded there must not also act here.
                if self.controller.isRecordingShortcut { return false }
                switch (keyCode, modifiers) {
                case (53, []):  // Escape
                    if self.panel.firstResponder is NSText { return false }
                    if self.controller.handleEscape() { return true }
                    self.hidePanel()
                    return true
                case (43, [.command]):  // ⌘,
                    self.controller.showSettings()
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

    /// The global shortcut goes through the same path as a click on the
    /// status item, so the panel opens without activating Clicker and the
    /// clickpad takes keyboard focus the same way. Carbon calls on the main
    /// thread.
    private func installHotKey() {
        KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
            MainActor.assumeIsolated { self?.togglePanel() }
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
        let settings = NSMenuItem(
            title: String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        if updates.isEnabled {
            let check = NSMenuItem(
                title: updates.checkForUpdatesTitle, action: #selector(checkForUpdates), keyEquivalent: "")
            check.target = self
            check.isEnabled = updates.canCheckForUpdates
            menu.addItem(check)
        }
        let about = NSMenuItem(
            title: String(localized: "About Clicker"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: String(localized: "Quit Clicker"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        )
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func checkForUpdates() {
        updates.checkForUpdates()
    }

    @objc private func showAbout() {
        AboutWindow.present()
    }

    /// Settings is a screen in the panel, so this opens the panel on it.
    @objc func openSettings() {
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

    /// Opens the panel unless it is already up (first launch, demo runs).
    /// Returns whether the panel is showing afterwards; `showPanel` does
    /// nothing while the status item has no window yet.
    @discardableResult
    func openPanelIfHidden() -> Bool {
        if !panel.isVisible { showPanel() }
        return panel.isVisible
    }

    private func showPanel() {
        guard let button = statusItem.button, updateAnchor() else { return }
        // Closing the About window hides the app to give focus back, and a
        // hidden app's windows stay off screen even when ordered front.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        PanelHeightBridge.invalidate()

        controller.panelDidAppear()
        // Open at the content's own height so the first frame needs no resize.
        // A zero proposal asks for the smallest height, which is the natural one
        // here; an unbounded one is answered unbounded, since the root view
        // fills whatever height it is offered.
        let fitting = hosting.sizeThatFits(in: NSSize(width: PanelMetrics.width, height: 0))
        applyHeight(fitting.height)
        hosting.view.layoutSubtreeIfNeeded()
        panel.invalidateShadow()

        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(nil)
        button.highlight(true)
        outsideClickMonitor.start()
    }

    /// Places the anchor under the status item on the side Settings asks
    /// for. False while the status item has no window yet.
    private func updateAnchor() -> Bool {
        guard let button = statusItem.button, let buttonWindow = button.window else { return false }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = NSScreen.screens.first { $0.frame.intersects(buttonRect) } ?? NSScreen.main
        anchorScreen = screen
        anchorAlignment = PanelAlignment.current
        anchorTopLeft = PanelGeometry.topLeft(
            below: buttonRect, width: PanelMetrics.width, alignment: anchorAlignment,
            visibleFrame: screen?.visibleFrame)
        return true
    }

    private func followAlignmentChange() {
        guard panel.isVisible, PanelAlignment.current != anchorAlignment, updateAnchor() else { return }
        applyHeight(panel.frame.height)
    }

    private func hidePanel() {
        panel.orderOut(nil)
        outsideClickMonitor.stop()
        statusItem.button?.highlight(false)
        anchorTopLeft = nil
        anchorScreen = nil
        shadowSettleTask?.cancel()
        PanelHeightBridge.invalidate()
        controller.panelDidDisappear()
    }

    /// Sets one frame for the content's height, anchored at the top-left and
    /// clamped to the screen. Never animated here: during a screen switch
    /// SwiftUI calls this once per frame with its own interpolated height, so
    /// the window and the content move on one curve.
    private func applyHeight(_ rawHeight: CGFloat) {
        guard rawHeight > 1, let anchorTopLeft else { return }
        let visibleFrame = (anchorScreen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maximum = PanelGeometry.maximumHeight(topLeft: anchorTopLeft, visibleFrame: visibleFrame)
        let height = PanelGeometry.clampedHeight(rawHeight, maximum: maximum)
        let frame = PanelGeometry.frame(topLeft: anchorTopLeft, width: PanelMetrics.width, height: height)
        guard abs(panel.frame.height - frame.height) > 0.5 || panel.frame.origin != frame.origin else { return }
        panel.setFrame(frame, display: true)
        scheduleShadowSettle()
    }

    /// Rebuilding the window shadow on every interpolated frame competes with
    /// the content animation, so it is refreshed once the frames stop.
    private func scheduleShadowSettle() {
        shadowSettleTask?.cancel()
        shadowSettleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self, self.panel.isVisible else { return }
            self.panel.invalidateShadow()
        }
    }
}
