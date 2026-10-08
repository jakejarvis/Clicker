import SwiftUI

/// Apps menu at the top left of the clickpad, listing the apps installed on
/// the Apple TV.
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
            CornerMenuGlyph(systemImage: "square.grid.2x2")
        }
        .cornerMenuStyle()
        .disabled(controller.connectionState != .connected)
        .help("Open an app on the Apple TV")
        .accessibilityLabel("Apps")
    }
}

/// Power menu at the top right of the clickpad, where it sits on the Siri Remote. Opens
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
            CornerMenuGlyph(systemImage: "power")
        }
        .cornerMenuStyle()
        .disabled(controller.connectionState != .connected)
        .help("Power · Apple TV is \(controller.powerState.title.lowercased())")
        .accessibilityLabel("Power")
    }
}

/// Glyph for the round menus at the clickpad's top corners.
private struct CornerMenuGlyph: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: RemoteMetrics.cornerButtonDiameter, height: RemoteMetrics.cornerButtonDiameter)
            .contentShape(Circle())
    }
}

extension View {
    /// Round glass menu button. `.menuStyle(.button)` with a plain button
    /// style is required: `.borderlessButton` ignores the label frame.
    fileprivate func cornerMenuStyle() -> some View {
        menuStyle(.button)
            .buttonStyle(PressFeedbackStyle())
            .menuIndicator(.hidden)
            .fixedSize()
            .surface(Circle())
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
