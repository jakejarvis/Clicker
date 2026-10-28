import AppKit
import SwiftUI

/// Clicker lives only in the menu bar: no Dock icon and no main window. The
/// status item and its panel are AppKit-owned (see `StatusItemController`),
/// which gives a real key window for keyboard input and full control over the
/// panel's shape, placement and size. `LSUIElement` in Info.plist plus the
/// `.accessory` activation policy make the no-Dock behavior explicit.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by `ClickerApp.run(in:)` before the app starts.
    fileprivate static var environment = AppEnvironment.live

    private var controller: RemoteController?
    private var updates: UpdateController?
    private var statusItemController: StatusItemController?

    /// Set once the panel has been opened for the user on the very first
    /// launch. A menu bar app that starts with no window gives a new user
    /// nothing to look at, so the first launch opens the panel itself,
    /// where the Looking for Apple TVs card and the pair card live.
    private static let firstLaunchKey = "hasCompletedFirstLaunch"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `--regular` shows a Dock icon, which makes the process visible to
        // tooling that only lists regular apps (useful during development).
        let policy: NSApplication.ActivationPolicy =
            CommandLine.arguments.contains("--regular") ? .regular : .accessory
        NSApp.setActivationPolicy(policy)

        let environment = Self.environment
        let controller = RemoteController(dependencies: environment.makeDependencies())
        self.controller = controller
        // Held here for the app's lifetime: Sparkle keeps its delegates weakly.
        let updates = UpdateController(launchPolicy: policy)
        self.updates = updates
        let statusItemController = StatusItemController(controller: controller, updates: updates)
        self.statusItemController = statusItemController
        // Shortcuts actions reach the app through these (docs/intents.md).
        IntentHost.controller = controller
        IntentHost.openPanel = { [weak statusItemController] in statusItemController?.openPanelIfHidden() }
        controller.start()
        updates.start()
        environment.didLaunch(controller, updates)

        if environment.opensPanelAtLaunch {
            openPanelShortly()
        } else if !UserDefaults.standard.bool(forKey: Self.firstLaunchKey) {
            openPanelShortly(recordingFirstLaunch: true)
        }
    }

    /// The app menu's Settings…, which only shows while Clicker is active
    /// (the About window open, or `--regular`).
    fileprivate func openSettings() {
        statusItemController?.openSettings()
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

/// The app's SwiftUI entry point. The Clicker and ClickerDemo executables
/// each call `run(in:)` with their environment.
package struct ClickerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    package init() {}

    package static func run(in environment: AppEnvironment) {
        AppDelegate.environment = environment
        main()
    }

    package var body: some Scene {
        // SwiftUI needs one scene; an empty Settings scene never opens a window
        // on its own and keeps the app window-free.
        Settings {
            EmptyView()
        }
        // While Clicker is active its menu bar shows, and its stock items
        // would open that empty Settings window, the standard About panel
        // and a "Help isn't available" alert (there is no help book). They
        // go where the status item's menu sends them, and Help links out.
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Clicker") { AboutWindow.present() }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appDelegate.openSettings() }
                    .keyboardShortcut(",")
            }
            CommandGroup(replacing: .help) {
                Button("Clicker Help") { NSWorkspace.shared.open(AboutLinks.help) }
                Button("Report an Issue…") { NSWorkspace.shared.open(AboutLinks.issues) }
            }
        }
    }
}
