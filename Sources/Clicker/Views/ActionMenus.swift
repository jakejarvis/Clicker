import SwiftUI

/// Footer menu listing the apps installed on the Apple TV.
struct AppsMenu: View {
    let controller: RemoteController

    var body: some View {
        Menu {
            if controller.apps.isEmpty {
                Text(controller.isLoadingApps ? "Loading…" : "No apps loaded")
            } else {
                ForEach(controller.apps) { app in
                    Button(app.name) { controller.launch(app) }
                }
            }
            Divider()
            Button("Refresh") { controller.refreshApps() }
                .disabled(controller.isLoadingApps)
        } label: {
            Label("Apps", systemImage: "square.grid.2x2")
                .padding(.horizontal, 4)
                .frame(height: 24)
        }
        .disabled(controller.connectionState != .connected)
        .help("Open an app on the Apple TV")
    }
}

/// Round power button beside the clickpad, where it sits on the Siri Remote. Opens
/// the wake/sleep menu rather than toggling, since the TV does not report
/// power reliably enough to make a single tap safe.
struct PowerMenu: View {
    let controller: RemoteController

    var body: some View {
        Menu {
            Button("Wake", systemImage: "sun.max") { controller.press(.wake) }
            Button("Sleep", systemImage: "moon") { controller.press(.sleep) }
            Divider()
            Button("Screen Saver", systemImage: "sparkles.tv") { controller.press(.screensaver) }
            Button("Control Center", systemImage: "switch.2") { controller.press(.pageDown) }
            Button("Guide", systemImage: "list.bullet.rectangle") { controller.press(.guide) }
        } label: {
            Image(systemName: "power")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: RemoteMetrics.powerButtonDiameter, height: RemoteMetrics.powerButtonDiameter)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(PressFeedbackStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .surface(Circle())
        .disabled(controller.connectionState != .connected)
        .help("Power · Apple TV is \(controller.powerState.title.lowercased())")
        .accessibilityLabel("Power")
    }
}

/// The gear menu in the footer: app-level actions that are not about the TV.
/// Mirrors the status item's right-click menu.
struct AppMenu: View {
    let controller: RemoteController
    let updates: UpdateController

    var body: some View {
        Menu {
            Button("Settings…") {
                withAnimation(.snappy(duration: 0.3)) { controller.screen = .settings }
            }
            .keyboardShortcut(",")
            if updates.isEnabled {
                Button(updates.pendingUpdateVersion.map { "Update to \($0)…" } ?? "Check for Updates…") {
                    updates.checkForUpdates()
                }
                .disabled(!updates.canCheckForUpdates)
            }
            Button("About Clicker") {
                controller.dismissPanel()
                AboutPanel.present()
            }
            Divider()
            Button("Quit Clicker") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: "gearshape")
                .frame(width: 28, height: 24)
        }
        .menuIndicator(.hidden)
        .help("Settings, About and Quit")
        .accessibilityLabel("Clicker menu")
    }
}
