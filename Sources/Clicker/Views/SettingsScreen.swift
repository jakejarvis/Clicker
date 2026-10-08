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
    let updates: UpdateController
    /// Reports the screen's natural height (title bar plus content) so the
    /// panel can resize to it instead of inheriting the remote's height.
    var onNaturalHeightChange: (CGFloat) -> Void = { _ in }

    @State private var barHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    @AppStorage(IdentityStore.clientNameKey) private var clientName = IdentityStore.defaultClientName
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?
    @State private var checksForUpdates = false
    /// The pairing awaiting confirmation in the alert sheet.
    @State private var forgetCandidate: PairingCredentials?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                PanelNavigationBar(title: "Settings") {
                    withAnimation(.snappy(duration: 0.3)) { controller.screen = .remote }
                }
                Divider()
                    .padding(.horizontal, PanelMetrics.horizontalPadding)
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: {
                barHeight = $0
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    thisMacSection
                    pairedSection
                    aboutSection
                    updatesSection
                    // Full-width actions live below the cards.
                    PanelActionButton(
                        title: updates.pendingUpdateVersion.map { "Update to \($0)…" } ?? "Check for Updates…",
                        systemImage: "arrow.down.circle"
                    ) {
                        updates.checkForUpdates()
                    }
                    .disabled(!updates.canCheckForUpdates)
                }
                .padding(.horizontal, PanelMetrics.horizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, 16)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    contentHeight = $0
                }
            }
            .scrollIndicators(.never)
        }
        .onChange(of: barHeight + contentHeight, initial: true) { _, total in
            if total > 0 { onNaturalHeightChange(total) }
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            checksForUpdates = updates.automaticallyChecksForUpdates
        }
        .alert(
            "Forget \(forgetCandidate?.deviceName ?? "this Apple TV")?",
            isPresented: Binding(
                get: { forgetCandidate != nil },
                set: { if !$0 { forgetCandidate = nil } }
            ),
            presenting: forgetCandidate
        ) { item in
            Button("Forget", role: .destructive) {
                let device = controller.devices.first { $0.id == item.deviceID } ?? AppleTVDevice(offline: item)
                controller.forgetPairing(for: device)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Clicker will need to pair with it again.")
        }
    }

    // MARK: - Sections

    private var thisMacSection: some View {
        SettingsSection(
            "This Mac",
            footer: launchAtLoginError
                ?? "The name appears under Remotes and Devices on the Apple TV the next time you pair."
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

    /// Only the names, with a hover-revealed remove control: the picker on the
    /// remote already shows model and state, and forgetting is rare. The
    /// section disappears entirely when nothing is paired.
    @ViewBuilder
    private var pairedSection: some View {
        let credentials = controller.credentialStore.credentials
        if !credentials.isEmpty {
            SettingsSection("Paired Apple TVs") {
                ForEach(Array(credentials.enumerated()), id: \.element.deviceID) { index, item in
                    if index > 0 { SettingsDivider() }
                    PairedDeviceRow(name: item.deviceName) {
                        forgetCandidate = item
                    }
                }
            }
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

    private var updatesSection: some View {
        SettingsSection("Updates", footer: updatesFooter) {
            SettingsRow("Check Automatically") {
                Toggle("Check Automatically", isOn: $checksForUpdates)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: checksForUpdates) { _, enabled in
                        // Sparkle persists this; only write when the user changes it.
                        if enabled != updates.automaticallyChecksForUpdates {
                            updates.automaticallyChecksForUpdates = enabled
                        }
                    }
            }
        }
        .disabled(!updates.isEnabled)
    }

    private var updatesFooter: String {
        guard updates.isEnabled else { return "Updates are off in development builds." }
        guard let lastCheck = updates.lastUpdateCheckDate else { return "Clicker hasn't checked for updates yet." }
        return "Last checked \(lastCheck.formatted(.relative(presentation: .named)))."
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
                }
                .buttonStyle(SurfaceButtonStyle(shape: Circle()))
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

/// One paired Apple TV. The remove control appears on hover (and via the
/// context menu) and asks for confirmation in a sheet.
private struct PairedDeviceRow: View {
    let name: String
    let onForget: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "appletv.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(name)
                .font(.body)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(action: onForget) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(SurfaceButtonStyle(shape: Circle(), glass: false, pressScale: 1))
            .opacity(isHovered ? 1 : 0)
            .help("Forget this pairing")
            .accessibilityLabel("Forget \(name)")
        }
        .contextMenu {
            Button("Forget \(name)…", role: .destructive, action: onForget)
        }
        .settingsRowPadding()
        .frame(minHeight: SettingsMetrics.rowHeight)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
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
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
        }
        .buttonStyle(
            SurfaceButtonStyle(
                shape: RoundedRectangle(cornerRadius: PanelMetrics.innerCornerRadius, style: .continuous),
                pressScale: 0.98))
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
