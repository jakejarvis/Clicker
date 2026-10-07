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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    thisMacSection
                    pairedSection
                    keyboardSection
                    aboutSection
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.never)
        }
        .frame(height: height)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private var thisMacSection: some View {
        SettingsSection("This Mac") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Name shown on Apple TV")
                    .font(.callout)
                TextField("Name", text: $clientName)
                    .textFieldStyle(.roundedBorder)
                Text("Appears under Remotes and Devices the next time you pair.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
                .padding(.horizontal, 12)
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
            if controller.credentialStore.credentials.isEmpty {
                Text("No Apple TVs paired yet. Pick one from the title menu and choose Pair.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ForEach(controller.credentialStore.credentials, id: \.deviceID) { credentials in
                    SettingsRow(credentials.deviceName, subtitle: "Paired \(credentials.pairedAt.formatted(date: .abbreviated, time: .omitted))") {
                        Button("Forget", role: .destructive) {
                            let device = controller.devices.first { $0.id == credentials.deviceID }
                                ?? AppleTVDevice(offline: credentials)
                            controller.forgetPairing(for: device)
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var keyboardSection: some View {
        SettingsSection("Keyboard") {
            SettingsRow("Navigate") { shortcut("↑ ↓ ← →") }
            SettingsRow("Select") { shortcut("Return") }
            SettingsRow("Back") { shortcut("Delete") }
            SettingsRow("Play/Pause") { shortcut("Space") }
            SettingsRow("TV") { shortcut("H") }
            SettingsRow("Volume") { shortcut("+  −") }
            SettingsRow("Mute") { shortcut("M") }
            SettingsRow("Close panel") { shortcut("Esc") }
        }
    }

    private var aboutSection: some View {
        SettingsSection("About") {
            SettingsRow("Version") {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
                    .foregroundStyle(.secondary)
            }
            SettingsRow("Quit Clicker", subtitle: "⌘Q also works") {
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .controlSize(.small)
            }
        }
    }

    private func shortcut(_ text: String) -> some View {
        Text(text)
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
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
                .buttonStyle(.plain)
                .surface(Circle())
                .help("Back")
                .accessibilityLabel("Back")
                .keyboardShortcut(.escape, modifiers: [])
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

/// Caption header over a rounded card of rows.
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
                .padding(.leading, 6)
            VStack(spacing: 0) {
                content()
            }
            .surface(RoundedRectangle(cornerRadius: 12, style: .continuous), interactive: false)
        }
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 36)
    }
}
