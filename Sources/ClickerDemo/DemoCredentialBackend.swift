import ClickerApp
import ClickerCompanion
import Security

/// Pairings for a demo run: seeded at launch, kept only in memory.
struct DemoCredentialBackend: CredentialBackend {
    let initial: [PairingCredentials]
    /// Refuses new pairings the way the keychain does for a signed build
    /// without a validated profile.
    let refusesStore: Bool

    func loadAll() throws -> [PairingCredentials] { initial }

    func store(_ credentials: PairingCredentials) throws {
        if refusesStore {
            throw KeychainCredentialBackend.KeychainError(operation: "add", status: errSecMissingEntitlement)
        }
    }

    func delete(deviceID: String) throws {}
}
