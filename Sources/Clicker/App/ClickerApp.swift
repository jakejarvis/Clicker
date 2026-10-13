import AppKit
import SwiftUI

/// Clicker lives only in the menu bar: no Dock icon and no main window. The
/// status item and its panel are AppKit-owned (see `StatusItemController`),
/// which gives a real key window for keyboard input and full control over the
/// panel's shape, placement and size. `LSUIElement` in Info.plist plus the
/// `.accessory` activation policy make the no-Dock behavior explicit.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: RemoteController?
    private var updates: UpdateController?
    private var statusItemController: StatusItemController?

    /// Set once the panel has been opened for the user on the very first
    /// launch. A menu bar app that starts with no window gives a new user
    /// nothing to look at, so the first launch opens the panel itself,
    /// where the Looking for Apple TVs card and the pair card live.
    private static let firstLaunchKey = "hasCompletedFirstLaunch"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Every tooltip in the panel is a short hint (row info glyphs, clickpad
        // quadrants, footer buttons), and AppKit's default delay of about a
        // second makes them feel absent. The registration domain is not
        // persisted, so nothing is written to the user's defaults.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 300])

        // `--regular` shows a Dock icon, which makes the process visible to
        // tooling that only lists regular apps (useful during development).
        let policy: NSApplication.ActivationPolicy =
            CommandLine.arguments.contains("--regular") ? .regular : .accessory
        NSApp.setActivationPolicy(policy)

        let controller = RemoteController()
        self.controller = controller
        // Held here for the app's lifetime: Sparkle keeps its delegates weakly.
        let updates = UpdateController(launchPolicy: policy)
        self.updates = updates
        statusItemController = StatusItemController(controller: controller, updates: updates)
        controller.start()
        updates.start()

        #if DEMO
            if let demo = controller.demo {
                if let version = demo.pendingUpdateVersion { updates.previewPendingUpdate(version) }
                // Demo runs open the panel themselves so a screenshot needs no click.
                openPanelShortly()
                return
            }
        #endif
        if !UserDefaults.standard.bool(forKey: Self.firstLaunchKey) {
            openPanelShortly(recordingFirstLaunch: true)
        }
    }

    /// Launching Clicker again while it runs (a double-click in Applications,
    /// the Dock icon under `--regular`) shows the panel; a menu bar app that
    /// does nothing there looks like it failed to start.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        statusItemController?.openPanelIfHidden()
        return false
    }

    /// Quits only after the live session has been told, so the TV gets a
    /// `_sessionStop` instead of a dead TCP connection. A TV that does not
    /// answer is not allowed to hold the quit past a second.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller, controller.hasSession else { return .terminateNow }
        Task {
            await controller.shutdown(within: .seconds(1))
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Opens the panel once the status item has been laid out. The Local
    /// Network prompt may land at the same moment on a first launch; a click
    /// on it closes the panel, which has still shown where the icon is.
    /// The first-launch flag is recorded only once the panel is actually up,
    /// so a launch where the status item was not ready gets another go.
    private func openPanelShortly(recordingFirstLaunch: Bool = false) {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.statusItemController?.openPanelIfHidden() == true else { return }
            if recordingFirstLaunch { UserDefaults.standard.set(true, forKey: Self.firstLaunchKey) }
        }
    }
}

@main
struct ClickerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // SwiftUI needs one scene; an empty Settings scene never opens a window
        // on its own and keeps the app window-free.
        Settings {
            EmptyView()
        }
    }
}
