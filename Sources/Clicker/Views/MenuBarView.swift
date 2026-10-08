import SwiftUI

/// Root of the menu bar panel, laid out in remote proportions: device picker
/// on top, the clickpad and buttons in the middle, apps and settings below.
struct MenuBarView: View {
    let controller: RemoteController
    let updates: UpdateController

    static let panelWidth: CGFloat = PanelMetrics.width

    /// Natural heights of both screens. The container is pinned to the height
    /// of the screen being shown, so the panel resizes once per switch while
    /// the outgoing screen is clipped as it slides away.
    @State private var remoteHeight: CGFloat?
    @State private var settingsHeight: CGFloat?

    private var targetHeight: CGFloat? {
        switch controller.screen {
        case .remote: return remoteHeight
        case .settings: return settingsHeight ?? remoteHeight
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            switch controller.screen {
            case .remote:
                remoteScreen
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.height
                    } action: { height in
                        if height > 0 { remoteHeight = height }
                    }
                    .transition(.move(edge: .leading))
            case .settings:
                SettingsScreen(controller: controller, updates: updates) { height in
                    settingsHeight = height
                }
                .transition(.move(edge: .trailing))
            }
        }
        .frame(width: Self.panelWidth)
        .frame(height: targetHeight, alignment: .top)
        .clipped()
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var remoteScreen: some View {
        VStack(spacing: 0) {
            DevicePickerMenu(controller: controller)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 4)

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
    }

    /// What stands between the user and the remote, if anything.
    private var overlay: RemoteOverlay? {
        if let device = controller.selectedDevice {
            if !controller.isPaired(device) || controller.pairingState == .succeeded {
                return .pairing(deviceID: device.id)
            }
            if !device.isOnline { return .offline(deviceID: device.id) }
            return nil
        }
        return controller.devices.isEmpty ? .searching : .choose
    }

    /// The remote is always drawn. When an overlay applies it is dimmed,
    /// blurred and inert under the card, so the panel keeps its shape and
    /// pairing reveals the remote in place.
    private var content: some View {
        let overlay = overlay
        let isLive = overlay == nil
        return VStack(spacing: 14) {
            if isLive, controller.keyboardSession != nil {
                TVTextFieldView(controller: controller)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            RemotePadView(controller: controller, isInteractive: isLive)
                .opacity(isLive ? 1 : 0.35)
                .blur(radius: isLive ? 0 : 2)
                .allowsHitTesting(isLive)
                .accessibilityHidden(!isLive)
                .overlay(alignment: .top) {
                    if let overlay {
                        overlayCard(overlay)
                            .id(overlay)
                            .frame(height: ClickpadGeometry.diameter)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
            if isLive {
                connectionBanner
            }
        }
        .animation(.snappy(duration: 0.3), value: overlay)
    }

    @ViewBuilder
    private func overlayCard(_ overlay: RemoteOverlay) -> some View {
        switch overlay {
        case .pairing, .offline:
            if let device = controller.selectedDevice {
                if case .offline = overlay {
                    OfflineCard(device: device)
                } else {
                    PairingCard(controller: controller, device: device)
                }
            }
        case .searching:
            SearchingCard(message: controller.browser.errorMessage)
        case .choose:
            ChooseDeviceCard()
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
            Spacer()
            if let version = updates.pendingUpdateVersion {
                Button {
                    updates.checkForUpdates()
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.tint)
                        .frame(width: 28, height: 24)
                }
                .help("Clicker \(version) is available")
                .accessibilityLabel("Update Clicker to \(version)")
            }
            AppMenu(controller: controller, updates: updates)
        }
        .buttonStyle(.borderless)
        .menuStyle(.borderlessButton)
        .foregroundStyle(.secondary)
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
        .background(
            .quaternary.opacity(0.5),
            in: RoundedRectangle(cornerRadius: PanelMetrics.innerCornerRadius, style: .continuous))
    }
}
