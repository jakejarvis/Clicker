import Foundation
import Observation

/// Persists pairing credentials as a private JSON file in Application Support.
@MainActor
@Observable
final class CredentialStore {
    private(set) var credentials: [PairingCredentials] = []

    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = support.appendingPathComponent("Clicker", isDirectory: true)
                .appendingPathComponent("pairings.json")
        }
        load()
    }

    func credentials(for deviceID: String) -> PairingCredentials? {
        credentials.first { $0.deviceID == deviceID }
    }

    func save(_ newCredentials: PairingCredentials) {
        credentials.removeAll { $0.deviceID == newCredentials.deviceID }
        credentials.append(newCredentials)
        persist()
    }

    func updateName(_ name: String, model: String?, for deviceID: String) {
        guard let index = credentials.firstIndex(where: { $0.deviceID == deviceID }) else { return }
        guard credentials[index].deviceName != name || credentials[index].deviceModel != model else { return }
        credentials[index].deviceName = name
        credentials[index].deviceModel = model
        persist()
    }

    /// Re-keys stored credentials, used when a device's identifier changes.
    func rekey(from oldID: String, to newID: String) {
        guard oldID != newID, let index = credentials.firstIndex(where: { $0.deviceID == oldID }) else { return }
        var updated = credentials[index]
        updated.deviceID = newID
        credentials.removeAll { $0.deviceID == oldID || $0.deviceID == newID }
        credentials.append(updated)
        persist()
        Log.storage.info("Re-keyed credentials for \(updated.deviceName, privacy: .public)")
    }

    func remove(deviceID: String) {
        credentials.removeAll { $0.deviceID == deviceID }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            credentials = try JSONDecoder().decode([PairingCredentials].self, from: data)
        } catch {
            Log.storage.error("Could not read pairings: \(String(describing: error), privacy: .public)")
        }
    }

    private func persist() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(credentials)
            try data.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            Log.storage.error("Could not save pairings: \(String(describing: error), privacy: .public)")
        }
    }
}
