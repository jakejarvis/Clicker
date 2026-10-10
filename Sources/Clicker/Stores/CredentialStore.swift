import Foundation
import Observation
import Security

/// Persists pairing credentials. Signed builds keep them in the data protection
/// keychain, where only code with Clicker's keychain access group can read
/// them; ad-hoc builds have no validated entitlements and fall back to a
/// private JSON file in Application Support.
@MainActor
@Observable
final class CredentialStore {
    private(set) var credentials: [PairingCredentials] = []

    @ObservationIgnored private let backend: any CredentialBackend

    init(backend: (any CredentialBackend)? = nil) {
        self.backend = backend ?? Self.defaultBackend()
        load()
    }

    /// The keychain when this build can use it, otherwise the file.
    private static func defaultBackend() -> any CredentialBackend {
        switch KeychainCredentialBackend.availability() {
        case .available:
            Log.storage.info("Storing pairings in the keychain")
            return KeychainCredentialBackend()
        case .missingEntitlement:
            Log.storage.info("Keychain entitlements not validated; storing pairings in Application Support")
            return FileCredentialBackend()
        case .failed(let status):
            Log.storage.error("Keychain unavailable (\(status)); storing pairings in Application Support")
            return FileCredentialBackend()
        }
    }

    func credentials(for deviceID: String) -> PairingCredentials? {
        credentials.first { $0.deviceID == deviceID }
    }

    /// Throws when the backend could not persist the pairing (a keychain
    /// refusal, a read-only disk); the in-memory copy is kept either way so
    /// the session that just paired still works.
    func save(_ newCredentials: PairingCredentials) throws {
        credentials.removeAll { $0.deviceID == newCredentials.deviceID }
        credentials.append(newCredentials)
        do {
            try backend.store(newCredentials)
        } catch {
            Log.storage.error("Could not save pairing: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    func updateName(_ name: String, model: String?, for deviceID: String) {
        guard let index = credentials.firstIndex(where: { $0.deviceID == deviceID }) else { return }
        guard credentials[index].deviceName != name || credentials[index].deviceModel != model else { return }
        credentials[index].deviceName = name
        credentials[index].deviceModel = model
        store(credentials[index])
    }

    /// Re-keys stored credentials, used when a device's identifier changes.
    func rekey(from oldID: String, to newID: String) {
        guard oldID != newID, let index = credentials.firstIndex(where: { $0.deviceID == oldID }) else { return }
        var updated = credentials[index]
        updated.deviceID = newID
        credentials.removeAll { $0.deviceID == oldID || $0.deviceID == newID }
        credentials.append(updated)
        delete(deviceID: oldID)
        store(updated)
        Log.storage.info("Re-keyed credentials for \(updated.deviceName, privacy: .public)")
    }

    func remove(deviceID: String) {
        credentials.removeAll { $0.deviceID == deviceID }
        delete(deviceID: deviceID)
    }

    private func load() {
        do {
            credentials = try backend.loadAll()
        } catch {
            Log.storage.error("Could not read pairings: \(String(describing: error), privacy: .public)")
        }
    }

    private func store(_ item: PairingCredentials) {
        do {
            try backend.store(item)
        } catch {
            Log.storage.error("Could not save pairing: \(String(describing: error), privacy: .public)")
        }
    }

    private func delete(deviceID: String) {
        do {
            try backend.delete(deviceID: deviceID)
        } catch {
            Log.storage.error("Could not remove pairing: \(String(describing: error), privacy: .public)")
        }
    }
}

/// Where credentials live. `store` replaces any entry with the same device ID.
protocol CredentialBackend {
    func loadAll() throws -> [PairingCredentials]
    func store(_ credentials: PairingCredentials) throws
    func delete(deviceID: String) throws
}

/// One generic-password item per Apple TV in the data protection keychain.
/// Items are scoped to the keychain access group from the app's entitlements,
/// so other processes cannot read the long-term keys.
struct KeychainCredentialBackend: CredentialBackend {
    enum Availability: Equatable {
        case available
        case missingEntitlement
        case failed(OSStatus)
    }

    struct KeychainError: Error, CustomStringConvertible, LocalizedError {
        let operation: String
        let status: OSStatus

        var description: String {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
            return "\(operation) failed: \(message) (\(status))"
        }

        /// Shown on the pair card when a save fails.
        var errorDescription: String? {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown keychain error"
            return "\(message) (\(status))"
        }
    }

    static let service = "com.jakejarvis.Clicker.pairing"

    /// Probes the keychain once. A plain query succeeds (with no results) even
    /// when the entitlements are not validated; only a query scoped to the
    /// access group reports `errSecMissingEntitlement`. The group comes from
    /// this process's own signature, so ad-hoc builds without entitlements
    /// fall back without touching the keychain at all.
    static func availability() -> Availability {
        guard let accessGroup = signedAccessGroup() else { return .missingEntitlement }
        var query = baseQuery
        query[kSecAttrAccessGroup as String] = accessGroup
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnAttributes as String] = true
        switch SecItemCopyMatching(query as CFDictionary, nil) {
        case errSecSuccess, errSecItemNotFound: return .available
        case errSecMissingEntitlement: return .missingEntitlement
        case let status: return .failed(status)
        }
    }

    /// The first `keychain-access-groups` entry in this process's code signature.
    private static func signedAccessGroup() -> String? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        let value = SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil)
        return (value as? [String])?.first
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    func loadAll() throws -> [PairingCredentials] {
        var query = Self.baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw KeychainError(operation: "load", status: status) }

        let items = result as? [[String: Any]] ?? []
        let decoder = JSONDecoder()
        return items.compactMap { item in
            guard let data = item[kSecValueData as String] as? Data else { return nil }
            do {
                return try decoder.decode(PairingCredentials.self, from: data)
            } catch {
                let account = item[kSecAttrAccount as String] as? String ?? "?"
                Log.storage.error("Skipping unreadable pairing \(account, privacy: .public): \(error)")
                return nil
            }
        }
    }

    func store(_ credentials: PairingCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrLabel as String: "Clicker: \(credentials.deviceName)",
        ]
        var query = Self.baseQuery
        query[kSecAttrAccount as String] = credentials.deviceID

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError(operation: "update", status: updateStatus)
        }

        var item = query
        item.merge(attributes) { _, new in new }
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(operation: "add", status: addStatus) }
    }

    func delete(deviceID: String) throws {
        var query = Self.baseQuery
        query[kSecAttrAccount as String] = deviceID
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(operation: "delete", status: status)
        }
    }
}

/// All credentials as one owner-only JSON file, for builds without validated
/// keychain entitlements (ad-hoc signed dev builds and CI).
struct FileCredentialBackend: CredentialBackend {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = support.appendingPathComponent("Clicker", isDirectory: true)
                .appendingPathComponent("pairings.json")
        }
    }

    func loadAll() throws -> [PairingCredentials] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([PairingCredentials].self, from: data)
    }

    func store(_ credentials: PairingCredentials) throws {
        var all = try loadAll()
        all.removeAll { $0.deviceID == credentials.deviceID }
        all.append(credentials)
        try write(all)
    }

    func delete(deviceID: String) throws {
        var all = try loadAll()
        all.removeAll { $0.deviceID == deviceID }
        try write(all)
    }

    private func write(_ all: [PairingCredentials]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(all)
        try data.write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
