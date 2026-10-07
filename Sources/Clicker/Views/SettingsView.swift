import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let controller: RemoteController

    @AppStorage(IdentityStore.clientNameKey) private var clientName = IdentityStore.defaultClientName
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section("This Mac") {
                TextField("Name shown on Apple TV", text: $clientName)
                    .help("Used the next time you pair; appears under Remotes and Devices on the Apple TV.")
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        updateLaunchAtLogin(enabled)
                    }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Paired Apple TVs") {
                if controller.credentialStore.credentials.isEmpty {
                    Text("No Apple TVs paired yet. Open Clicker from the menu bar and choose Pair.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(controller.credentialStore.credentials, id: \.deviceID) { credentials in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(credentials.deviceName)
                                Text("Paired \(credentials.pairedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Forget", role: .destructive) {
                                let device = controller.devices.first { $0.id == credentials.deviceID }
                                    ?? AppleTVDevice(offline: credentials)
                                controller.forgetPairing(for: device)
                            }
                        }
                    }
                }
            }

            Section("Keyboard") {
                LabeledContent("Navigate", value: "Arrow keys")
                LabeledContent("Select", value: "Return")
                LabeledContent("Back", value: "Esc or Delete")
                LabeledContent("Play/Pause", value: "Space or P")
                LabeledContent("TV / Home", value: "H")
                LabeledContent("Volume", value: "+ and −")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
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
