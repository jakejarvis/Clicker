import ClickerCompanion
import Foundation
import Testing

@testable import Clicker

@Suite struct CredentialStoreTests {
    private func makeCredentials(id: String, name: String = "Living Room") -> PairingCredentials {
        PairingCredentials(
            deviceID: id,
            deviceName: name,
            deviceModel: "AppleTV14,1",
            accessoryIdentifier: Data([1, 2, 3]),
            accessoryPublicKey: Data(repeating: 0xAB, count: 32),
            clientIdentifier: UUID().uuidString,
            clientPrivateKey: Data(repeating: 0xCD, count: 32),
            pairedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("clicker-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("pairings.json")
    }

    @Test @MainActor func fileBackendRoundTrips() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let backend = FileCredentialBackend(fileURL: url)

        let store = CredentialStore(backend: backend)
        #expect(store.credentials.isEmpty)
        let living = makeCredentials(id: "A")
        try store.save(living)
        try store.save(makeCredentials(id: "B", name: "Bedroom"))
        store.updateName("Den", model: "AppleTV11,1", for: "B")

        let reloaded = CredentialStore(backend: backend)
        #expect(reloaded.credentials.count == 2)
        #expect(reloaded.credentials(for: "A") == living)
        #expect(reloaded.credentials(for: "B")?.deviceName == "Den")
        #expect(reloaded.credentials(for: "B")?.deviceModel == "AppleTV11,1")

        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    /// A refused save leaves the TV unpaired, so the pair card can show the failure.
    @Test @MainActor func refusedSaveIsNotKept() throws {
        struct Refusal: Error {}
        struct RefusingBackend: CredentialBackend {
            func loadAll() throws -> [PairingCredentials] { [] }
            func store(_ credentials: PairingCredentials) throws { throw Refusal() }
            func delete(deviceID: String) throws {}
        }

        let store = CredentialStore(backend: RefusingBackend())
        #expect(throws: Refusal.self) { try store.save(makeCredentials(id: "A")) }
        #expect(store.credentials.isEmpty)
        #expect(store.credentials(for: "A") == nil)
    }

    @Test @MainActor func rekeyAndRemovePersist() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let backend = FileCredentialBackend(fileURL: url)

        let store = CredentialStore(backend: backend)
        try store.save(makeCredentials(id: "old"))
        try store.save(makeCredentials(id: "gone", name: "Kitchen"))
        store.rekey(from: "old", to: "new")
        store.remove(deviceID: "gone")

        let reloaded = CredentialStore(backend: backend)
        #expect(reloaded.credentials.map(\.deviceID) == ["new"])
        #expect(reloaded.credentials(for: "new")?.deviceName == "Living Room")
    }
}
