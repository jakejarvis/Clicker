import ServiceManagement
import SwiftUI

/// Settings shown inside the panel in place of the remote.
///
/// One rule set keeps it coherent: section headers are subheadline/secondary,
/// row titles are body, secondary text is caption, every action is a small
/// bordered button, every switch is a small toggle, and explanations live in
/// section footers rather than inside rows.
struct SettingsScreen: View {
    let controller: RemoteController
    /// Reports the screen's natural height (title bar plus content) so the
    /// panel can resize to it instead of inheriting the remote's height.
    var onNaturalHeightChange: (CGFloat) -> Void = { _ in }

    @State private var barHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    @AppStorage(IdentityStore.clientNameKey) private var clientName = IdentityStore.defaultClientName
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?
    @State private var pendingForgetID: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                PanelNavigationBar(title: "Settings") {
                    withAnimation(.snappy(duration: 0.3)) { controller.screen = .remote }
                }
                Divider()
                    .padding(.horizontal, PanelMetrics.horizontalPadding)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    thisMacSection
                    pairedSection
                    aboutSection
                    // Full-width actions live below the cards; more will join
                    // Quit here (Check for Updates, for one).
                    VStack(spacing: 6) {
                        PanelActionButton(title: "Quit Clicker", systemImage: "power") {
                            NSApplication.shared.terminate(nil)
                        }
                        .help("⌘Q")
                    }
                }
                .padding(.horizontal, PanelMetrics.horizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, 16)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollIndicators(.never)
        }
        .onChange(of: barHeight + contentHeight, initial: true) { _, total in
            if total > 0 { onNaturalHeightChange(total) }
        }
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
        .animation(.snappy(duration: 0.2), value: pendingForgetID)
    }

    // MARK: - Sections

    private var thisMacSection: some View {
        SettingsSection(
            "This Mac",
            footer: launchAtLoginError ?? "The name appears under Remotes and Devices on the Apple TV the next time you pair."
        ) {
            SettingsRow("Name") {
                TextField("Name", text: $clientName)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(maxWidth: 160)
            }
            SettingsDivider()
            SettingsRow("Launch at Login") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: launchAtLogin) { _, enabled in updateLaunchAtLogin(enabled) }
            }
        }
    }

    private var pairedSection: some View {
        SettingsSection("Paired Apple TVs") {
            let credentials = controller.credentialStore.credentials
            if credentials.isEmpty {
                SettingsRow("None yet", subtitle: "Choose an Apple TV at the top of the remote and pair it.") {
                    EmptyView()
                }
            } else {
                ForEach(Array(credentials.enumerated()), id: \.element.deviceID) { index, item in
                    if index > 0 { SettingsDivider() }
                    pairedRow(item)
                }
            }
        }
    }

    @ViewBuilder
    private func pairedRow(_ item: PairingCredentials) -> some View {
        let device = controller.devices.first { $0.id == item.deviceID }
        if pendingForgetID == item.deviceID {
            // Confirmation takes over the row: the question on one line, the
            // choices on the next, so nothing has to truncate.
            VStack(alignment: .leading, spacing: 8) {
                Text("Forget \(item.deviceName)?")
                    .font(.body)
                HStack(spacing: 8) {
                    Text("You'll need to pair again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Cancel") { pendingForgetID = nil }
                        .buttonStyle(.bordered)
                    Button("Forget") {
                        pendingForgetID = nil
                        controller.forgetPairing(for: device ?? AppleTVDevice(offline: item))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .controlSize(.small)
            }
            .settingsRowPadding()
            .frame(minHeight: SettingsMetrics.rowHeight)
            .transition(.opacity)
        } else {
            HStack(spacing: 10) {
                DeviceIcon(
                    device: device,
                    isConnected: controller.selectedDeviceID == item.deviceID && controller.connectionState == .connected
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.deviceName)
                        .font(.body)
                        .lineLimit(1)
                    Text("Paired \(item.pairedAt.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button("Forget…") { pendingForgetID = item.deviceID }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .settingsRowPadding()
            .frame(minHeight: SettingsMetrics.rowHeight)
            .transition(.opacity)
        }
    }

    private var aboutSection: some View {
        SettingsSection("About") {
            SettingsRow("Version") {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Building blocks

enum SettingsMetrics {
    static let rowHeight: CGFloat = 40
    static let rowHorizontalPadding: CGFloat = 12
    static let rowVerticalPadding: CGFloat = 8
}

/// Title bar for a secondary panel screen.
struct PanelNavigationBar: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(PressFeedbackStyle())
                .surface(Circle())
                .help("Back (Esc)")
                .accessibilityLabel("Back")
                Spacer()
            }
        }
        .padding(.horizontal, PanelMetrics.horizontalPadding)
        .padding(.vertical, 10)
    }
}

/// Header, a flat card of rows, and an optional explanatory footer.
struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, SettingsMetrics.rowHorizontalPadding)
            VStack(spacing: 0) {
                content()
            }
            .card()
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, SettingsMetrics.rowHorizontalPadding)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Compact full-width action for the bottom of the settings screen, sized
/// like a footer control rather than a remote button.
struct PanelActionButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(title)
                    .font(.callout)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .contentShape(RoundedRectangle(cornerRadius: PanelMetrics.innerCornerRadius, style: .continuous))
        }
        .buttonStyle(PressFeedbackStyle())
        .surface(RoundedRectangle(cornerRadius: PanelMetrics.innerCornerRadius, style: .continuous))
    }
}

/// Hairline between rows, inset to the row content.
struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, SettingsMetrics.rowHorizontalPadding)
    }
}

/// A labelled row with its control on the trailing edge.
struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let control: () -> Control

    init(_ title: String, subtitle: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.control = control
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body)
                    .fixedSize()
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control()
        }
        .settingsRowPadding()
        .frame(minHeight: SettingsMetrics.rowHeight)
    }
}

extension View {
    func settingsRowPadding() -> some View {
        padding(.horizontal, SettingsMetrics.rowHorizontalPadding)
            .padding(.vertical, SettingsMetrics.rowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
