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

    /// Slides become fades and the ghosted remote isn't blurred, since
    /// animating into and out of a blur is motion too.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    .transition(reduceMotion ? .opacity : .move(edge: .leading))
            case .settings:
                SettingsScreen(controller: controller, updates: updates) { height in
                    // The first measurement lands a frame after the switch
                    // began, outside its transaction, so it gets the same
                    // curve; later ones follow the content's own animation.
                    if settingsHeight == nil {
                        withAnimation(.snappy(duration: 0.3)) { settingsHeight = height }
                    } else {
                        settingsHeight = height
                    }
                }
                .transition(reduceMotion ? .opacity : .move(edge: .trailing))
            }
        }
        .frame(width: Self.panelWidth)
        .frame(height: targetHeight, alignment: .top)
        .clipped()
        .frame(maxHeight: .infinity, alignment: .top)
        // The window follows this height frame by frame (PanelHeightBridge).
        .drivesPanelHeight(targetHeight)
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
                .animation(.snappy(duration: 0.25), value: controller.isTextFieldShown)

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
    /// pairing reveals the remote in place. Without a session (connecting,
    /// failed or closed) it is dimmed less and inert with no card: the
    /// device picker says which, and a notice offers Retry. Presses made
    /// then went nowhere until the session came up, or nowhere at all.
    private var content: some View {
        let overlay = overlay
        let isLive = overlay == nil
        let isConnected = controller.connectionState == .connected
        let isUsable = isLive && isConnected
        return VStack(spacing: 14) {
            RemotePadView(controller: controller, isInteractive: isUsable)
                .opacity(isLive ? (isConnected ? 1 : 0.5) : 0.35)
                .blur(radius: isLive || reduceMotion ? 0 : 2)
                .allowsHitTesting(isUsable)
                .disabled(!isUsable)
                .accessibilityHidden(!isLive)
                .overlay(alignment: .top) {
                    if let overlay {
                        overlayCard(overlay)
                            .id(overlay)
                            .frame(height: ClickpadGeometry.diameter)
                            .padding(.top, RemoteMetrics.clickpadTopInset)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
            // Below the remote, so the panel grows downward from its anchored
            // top and no button moves when the TV shows or hides a keyboard.
            if isLive, controller.isTextFieldShown {
                TVTextFieldView(controller: controller)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
            let notices = notices(isLive: isLive)
            if !notices.isEmpty {
                VStack(spacing: 6) {
                    ForEach(notices) { InlineNoticeView(notice: $0) }
                }
            }
        }
        .animation(.snappy(duration: 0.3), value: overlay)
        .animation(.snappy(duration: 0.3), value: isConnected)
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
            SearchingCard(message: controller.discovery.errorMessage)
        case .choose:
            ChooseDeviceCard()
        }
    }

    /// Notices under the remote, problems first. Connection notices only make
    /// sense while the remote is usable (an overlay card already explains the
    /// rest); the update notice shows regardless, so a TV that is off or
    /// unpaired does not hide it.
    private func notices(isLive: Bool) -> [InlineNotice] {
        var notices: [InlineNotice] = []
        if isLive {
            switch controller.connectionState {
            case .failed(let message):
                notices.append(
                    InlineNotice(
                        id: "connection", kind: .warning, message: message,
                        action: .init(title: "Retry") { controller.retryConnection() }))
            case .disconnected:
                notices.append(
                    InlineNotice(
                        id: "connection", kind: .warning, message: String(localized: "Not connected."),
                        action: .init(title: "Connect") { controller.retryConnection() }))
            case .localNetworkDenied:
                // Opening Settings closes the panel (an outside click), and
                // the next open connects again.
                notices.append(
                    InlineNotice(
                        id: "connection", kind: .warning, message: RemoteController.localNetworkDeniedMessage,
                        action: .init(title: "Open Privacy & Security", placement: .below) {
                            SystemSettings.openLocalNetworkPrivacy()
                        }))
            case .connecting, .connected:
                if let error = controller.lastActionError {
                    notices.append(InlineNotice(id: "action-error", kind: .warning, message: error))
                }
            }
        }
        if let version = updates.pendingUpdateVersion {
            notices.append(
                InlineNotice(
                    id: "update", kind: .update, message: String(localized: "Clicker \(version) is available."),
                    action: .init(title: "Update") { updates.checkForUpdates() }))
        }
        return notices
    }

    private var footer: some View {
        HStack(spacing: 2) {
            keyboardButton
            Spacer()
            AppMenu(controller: controller, updates: updates)
        }
        // Flat footer controls: a rounded highlight on hover, no glass.
        .buttonStyle(
            SurfaceButtonStyle(
                shape: RoundedRectangle(cornerRadius: 6, style: .continuous), glass: false, pressScale: 1)
        )
        .menuStyle(.button)
        .foregroundStyle(.secondary)
    }
}

extension MenuBarView {
    /// Hides or re-shows the TV text field. Enabled only while the TV has a
    /// field focused; otherwise there is nothing to type into. The tooltip
    /// sits on a wrapper because a disabled button takes no hover.
    fileprivate var keyboardButton: some View {
        let canType = overlay == nil && controller.keyboardSession != nil
        let help: LocalizedStringKey =
            !canType
            ? "Available when the Apple TV shows a keyboard"
            : controller.isTextFieldShown ? "Hide the Apple TV text field" : "Type on the Apple TV"
        return Button {
            controller.toggleTextField()
        } label: {
            Image(systemName: "keyboard")
                // Accent while the field is showing.
                .foregroundStyle(controller.isTextFieldShown ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 28, height: 24)
        }
        .disabled(!canType)
        .accessibilityLabel(
            controller.isTextFieldShown ? "Hide the Apple TV text field" : "Show the Apple TV text field"
        )
        .contentShape(Rectangle())
        .help(help)
    }
}
