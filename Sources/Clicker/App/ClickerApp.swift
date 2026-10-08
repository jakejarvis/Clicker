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

    func applicationDidFinishLaunching(_ notification: Notification) {
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
