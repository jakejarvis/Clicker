import ServiceManagement
import SwiftUI

/// Settings shown inside the panel in place of the remote: a navigation bar
/// with a back button, then captioned cards of rows with controls on the
/// trailing edge, like System Settings.
struct SettingsScreen: View {
    let controller: RemoteController
    /// Total height to fill, matching the remote screen.
    let height: CGFloat

    @AppStorage(IdentityStore.clientNameKey) private var clientName = IdentityStore.defaultClientName
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

    var body: some View {
        VStack(spacing: 0) {
            PanelNavigationBar(title: "Settings") {
                withAnimation(.snappy(duration: 0.3)) { controller.screen = .remote }
            }
            Divider()
                .padding(.horizontal, PanelMetrics.horizontalPadding)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    thisMacSection
                    pairedSection
                    keyboardSection
                    aboutSection
                }
                .padding(.horizontal, PanelMetrics.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)
        }
        .frame(height: height)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    // MARK: - Sections

    private var thisMacSection: some View {
        SettingsSection("This Mac") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Name shown on Apple TV")
                TextField("Name", text: $clientName)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                Text("Appears under Remotes and Devices the next time you pair.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingsRowPadding()
            SettingsDivider()
            SettingsRow("Launch at Login") {
                Toggle("", isOn: $launchAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: launchAtLogin) { _, enabled in updateLaunchAtLogin(enabled) }
            }
            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
    }

    private var pairedSection: some View {
        SettingsSection("Paired Apple TVs") {
            let credentials = controller.credentialStore.credentials
            if credentials.isEmpty {
                Text("None yet. Pick an Apple TV from the top of the remote and choose Pair.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .settingsRowPadding()
            } else {
                ForEach(Array(credentials.enumerated()), id: \.element.deviceID) { index, item in
                    if index > 0 { SettingsDivider() }
                    HStack(spacing: 10) {
                        DeviceIcon(
                            device: controller.devices.first { $0.id == item.deviceID },
                            isConnected: controller.selectedDeviceID == item.deviceID && controller.connectionState == .connected
                        )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.deviceName)
                                .font(.callout.weight(.medium))
                            Text("Paired \(item.pairedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button("Forget") {
                            let device = controller.devices.first { $0.id == item.deviceID }
                                ?? AppleTVDevice(offline: item)
                            controller.forgetPairing(for: device)
                        }
                        .buttonStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(.red)
                    }
                    .settingsRowPadding()
                }
            }
        }
    }

    private var keyboardSection: some View {
        SettingsSection("Keyboard") {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 10) {
                shortcut("↑↓←→", "Navigate")
                shortcut("⏎", "Select")
                shortcut("⌫", "Back")
                shortcut("␣", "Play/Pause")
                shortcut("H", "TV")
                shortcut("M", "Mute")
                shortcut("+ −", "Volume")
                shortcut("Esc", "Close")
            }
            .settingsRowPadding()
        }
    }

    private var aboutSection: some View {
        SettingsSection("About") {
            SettingsRow("Version") {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
                    .foregroundStyle(.secondary)
            }
            SettingsDivider()
            SettingsRow("Quit Clicker", subtitle: "⌘Q") {
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .controlSize(.small)
            }
        }
    }

    private func shortcut(_ keys: String, _ action: String) -> some View {
        HStack(spacing: 8) {
            Text(keys)
                .font(.caption.weight(.semibold).monospaced())
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(action)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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

/// Caption header over a flat card of rows.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
            VStack(spacing: 0) {
                content()
            }
            .card()
        }
    }
}

/// Hairline between rows, inset to the row content.
struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 12)
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
                    .font(.callout)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            control()
        }
        .settingsRowPadding()
        .frame(minHeight: 38)
    }
}

private extension View {
    func settingsRowPadding() -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
