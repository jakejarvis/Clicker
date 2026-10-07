import AppKit
import SwiftUI

/// Clicker lives only in the menu bar: no Dock icon and no main window. The
/// `LSUIElement` key in Info.plist plus the `.accessory` activation policy
/// below make that explicit and intentional.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `--regular` shows a Dock icon, which makes the process visible to
        // tooling that only lists regular apps (useful during development).
        let policy: NSApplication.ActivationPolicy =
            CommandLine.arguments.contains("--regular") ? .regular : .accessory
        NSApp.setActivationPolicy(policy)
    }
}

@main
struct ClickerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var controller = RemoteController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(controller: controller)
        } label: {
            Image(systemName: controller.menuBarSymbolName)
                .accessibilityLabel("Clicker")
                .onAppear { controller.start() }
        }
        .menuBarExtraStyle(.window)
    }
}
