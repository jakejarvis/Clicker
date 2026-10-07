import AppKit
import SwiftUI

/// Clicker lives only in the menu bar: no Dock icon and no main window. The
/// `LSUIElement` key in Info.plist plus the `.accessory` activation policy
/// below make that explicit and intentional.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
            Image(systemName: "appletv.fill")
                .accessibilityLabel("Clicker")
                .onAppear { controller.start() }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(controller: controller)
        }
    }
}
