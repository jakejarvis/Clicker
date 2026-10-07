import SwiftUI

/// Root of the menu bar panel, laid out in remote proportions: device cards
/// on top, the clickpad and buttons in the middle, apps/power/settings below.
struct MenuBarView: View {
    let controller: RemoteController

    static let panelWidth: CGFloat = 264

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                DevicePickerMenu(controller: controller)
                header
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 14)

            content
                .frame(maxWidth: .infinity)
                .padding(14)
                .animation(.snappy(duration: 0.25), value: controller.keyboardSession == nil)

            Divider()
                .padding(.horizontal, 14)

            footer
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(width: Self.panelWidth)
        .onAppear { controller.panelDidAppear() }
    }

    @ViewBuilder
    private var header: some View {
        if let device = controller.selectedDevice {
            HStack(spacing: 4) {
                Text(device.modelDisplayName)
                    .truncationMode(.tail)
                Text("·")
                Text(controller.selectedStateDescription)
                    .layoutPriority(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.leading, 30)
        } else if controller.devices.isEmpty {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Looking for Apple TVs…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
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
                VStack(spacing: 14) {
                    if controller.keyboardSession != nil {
                        TVTextFieldView(controller: controller)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    RemotePadView(controller: controller)
                    connectionBanner
                }
            }
        } else if controller.devices.isEmpty {
            StatusMessageView(
                systemImage: "antenna.radiowaves.left.and.right",
                title: "No Apple TVs yet",
                message: controller.browser.errorMessage
                    ?? "Make sure this Mac and the Apple TV are on the same network."
            )
        } else {
            StatusMessageView(
                systemImage: "appletv",
                title: "Choose an Apple TV",
                message: "Select one of the devices above."
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
        HStack(spacing: 2) {
            AppsMenu(controller: controller)
            PowerMenu(controller: controller)
            Spacer()
            SettingsButton()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power.circle")
                    .frame(width: 28, height: 24)
            }
            .help("Quit Clicker")
        }
        .buttonStyle(.borderless)
        .menuStyle(.borderlessButton)
        .foregroundStyle(.secondary)
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
                .frame(width: 28, height: 24)
        }
        .help("Settings")
    }
}

struct StatusMessageView: View {
    let systemImage: String
    let title: String
    let message: String

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
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
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
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
