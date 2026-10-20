import ClickerApp
import ClickerCompanion
import Security

/// Pairings for a demo run: seeded at launch, then kept in memory as the
/// app stores and deletes them.
final class DemoCredentialBackend: CredentialBackend {
    private var pairings: [PairingCredentials]
    /// Refuses new pairings with the keychain's missing-entitlement error, as
    /// an add that fails after the availability probe passed would.
    private let refusesStore: Bool

    init(initial: [PairingCredentials], refusesStore: Bool) {
        pairings = initial
        self.refusesStore = refusesStore
    }

    func loadAll() throws -> [PairingCredentials] { pairings }

    func store(_ credentials: PairingCredentials) throws {
        if refusesStore {
            throw KeychainCredentialBackend.KeychainError(operation: "add", status: errSecMissingEntitlement)
        }
        pairings.removeAll { $0.deviceID == credentials.deviceID }
        pairings.append(credentials)
    }

    func delete(deviceID: String) throws {
        pairings.removeAll { $0.deviceID == deviceID }
    }
}
