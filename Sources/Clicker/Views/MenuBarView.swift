import SwiftUI

/// Root of the menu bar panel: device picker on top, the remote or pairing
/// flow in the middle, apps/power/settings along the bottom.
struct MenuBarView: View {
    let controller: RemoteController

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            Divider()
            content
                .frame(maxWidth: .infinity)
                .padding(16)
            Divider()
            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: 320)
        .onAppear { controller.panelDidAppear() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            DevicePickerView(controller: controller)
            Spacer(minLength: 0)
            ConnectionStatusView(controller: controller)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let device = controller.selectedDevice {
            if !controller.isPaired(device) {
                PairingView(controller: controller, device: device)
            } else if !device.isOnline {
                StatusMessageView(
                    systemImage: "wifi.slash",
                    title: "\(device.name) is offline",
                    message: "It is not advertising on this network right now."
                )
            } else {
                VStack(spacing: 12) {
                    RemotePadView(controller: controller)
                    connectionBanner
                }
            }
        } else if controller.devices.isEmpty {
            StatusMessageView(
                systemImage: "antenna.radiowaves.left.and.right",
                title: "Looking for Apple TVs",
                message: controller.browser.errorMessage
                    ?? "Make sure this Mac and the Apple TV are on the same network.",
                showsProgress: true
            )
        } else {
            StatusMessageView(
                systemImage: "appletv",
                title: "Choose an Apple TV",
                message: "Pick a device from the menu above."
            )
        }
    }

    @ViewBuilder
    private var connectionBanner: some View {
        switch controller.connectionState {
        case .failed(let message):
            InlineNoticeView(message: message, actionTitle: "Retry") {
                controller.retryConnection()
            }
        case .disconnected:
            InlineNoticeView(message: "Not connected.", actionTitle: "Connect") {
                controller.retryConnection()
            }
        case .connecting, .connected:
            if let error = controller.lastActionError {
                InlineNoticeView(message: error, actionTitle: nil, action: nil)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            AppsMenu(controller: controller)
            PowerMenu(controller: controller)
            Spacer()
            SettingsButton()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power.circle")
            }
            .help("Quit Clicker")
        }
        .buttonStyle(.borderless)
        .menuStyle(.borderlessButton)
        .disabled(false)
    }
}

private struct ConnectionStatusView: View {
    let controller: RemoteController

    var body: some View {
        HStack(spacing: 6) {
            if controller.connectionState.isBusy {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help(help)
    }

    private var color: Color {
        switch controller.connectionState {
        case .connected: return .green
        case .connecting: return .yellow
        case .failed: return .red
        case .disconnected: return .gray
        }
    }

    private var title: String {
        switch controller.connectionState {
        case .connected:
            switch controller.powerState.isOn {
            case .some(true): return "On"
            case .some(false): return "Asleep"
            case .none: return "Connected"
            }
        case .connecting: return "Connecting"
        case .failed: return "Error"
        case .disconnected: return "Offline"
        }
    }

    private var help: String {
        if case .failed(let message) = controller.connectionState { return message }
        return "Apple TV is \(controller.powerState.title.lowercased())"
    }
}

private struct SettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        } label: {
            Image(systemName: "gearshape")
        }
        .help("Settings")
    }
}

struct StatusMessageView: View {
    let systemImage: String
    let title: String
    let message: String
    var showsProgress = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct InlineNoticeView: View {
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
