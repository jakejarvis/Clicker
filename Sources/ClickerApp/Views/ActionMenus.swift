import ClickerCompanion
import SwiftUI

/// Apps button at the top left of the clickpad. Opens `AppPickerView` in a
/// popover: a searchable list with recents, which a system `Menu` cannot do.
/// The popover is centered on the button, so its arrow points at it and the
/// list hangs past the panel's left edge, like any popover from a corner.
struct AppsMenu: View {
    @Bindable var controller: RemoteController

    var body: some View {
        Button {
            controller.isAppPickerPresented.toggle()
        } label: {
            CornerMenuGlyph(systemImage: "square.grid.2x2")
        }
        .buttonStyle(SurfaceButtonStyle(shape: Circle()))
        .fixedSize()
        .disabled(controller.connectionState != .connected)
        .help("Open an app on the Apple TV")
        .accessibilityLabel("Apps")
        .accessibilityHint("Opens the list of apps")
        .popover(isPresented: $controller.isAppPickerPresented, arrowEdge: .bottom) {
            AppPickerView(controller: controller)
                .popoverAppearance()
        }
    }
}

/// Power menu at the top right of the clickpad, where it sits on the Siri Remote. Opens
/// the wake/sleep menu rather than toggling, since the TV does not report
/// power reliably enough to make a single tap safe.
struct PowerMenu: View {
    let controller: RemoteController

    var body: some View {
        Menu {
            item(.wake)
            item(.sleep)
            Divider()
            item(.screensaver)
            item(.pageDown)
            item(.guide)
        } label: {
            CornerMenuGlyph(systemImage: "power")
        }
        .cornerMenuStyle()
        .disabled(controller.connectionState != .connected)
        .help(controller.powerState.powerTooltip)
        .accessibilityLabel("Power")
    }

    /// Title and glyph come from the command, so the menu and the enum
    /// cannot drift apart.
    private func item(_ command: HIDCommand) -> some View {
        Button(command.title, systemImage: command.systemImage) { controller.press(command) }
    }
}

/// Glyph for the round menus at the clickpad's top corners.
private struct CornerMenuGlyph: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(RemoteMetrics.glyphFont)
            .foregroundStyle(.primary)
            .frame(width: RemoteMetrics.cornerButtonDiameter, height: RemoteMetrics.cornerButtonDiameter)
    }
}

extension View {
    /// Round glass menu button. `.menuStyle(.button)` with a plain button
    /// style is required: `.borderlessButton` ignores the label frame.
    fileprivate func cornerMenuStyle() -> some View {
        menuStyle(.button)
            .buttonStyle(SurfaceButtonStyle(shape: Circle()))
            .menuIndicator(.hidden)
            .fixedSize()
    }
}

/// The footer menu (three dots): app-level actions that are not about the TV.
/// Mirrors the status item's right-click menu.
struct AppMenu: View {
    let controller: RemoteController
    let updates: UpdateController

    var body: some View {
        Menu {
            Button("Settings…") { controller.showSettings() }
                .keyboardShortcut(",")
            if updates.isEnabled {
                Button(updates.pendingUpdateVersion.map { "Update to \($0)…" } ?? "Check for Updates…") {
                    updates.checkForUpdates()
                }
                .disabled(!updates.canCheckForUpdates)
            }
            Button("About Clicker") {
                controller.dismissPanel()
                AboutWindow.present()
            }
            Divider()
            Button("Quit Clicker") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 28, height: 24)
        }
        .menuIndicator(.hidden)
        .help("Menu")
        .accessibilityLabel("Clicker menu")
    }
}
