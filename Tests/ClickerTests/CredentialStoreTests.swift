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
        store.save(living)
        store.save(makeCredentials(id: "B", name: "Bedroom"))
        store.updateName("Den", model: "AppleTV11,1", for: "B")

        let reloaded = CredentialStore(backend: backend)
        #expect(reloaded.credentials.count == 2)
        #expect(reloaded.credentials(for: "A") == living)
        #expect(reloaded.credentials(for: "B")?.deviceName == "Den")
        #expect(reloaded.credentials(for: "B")?.deviceModel == "AppleTV11,1")

        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test @MainActor func rekeyAndRemovePersist() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let backend = FileCredentialBackend(fileURL: url)

        let store = CredentialStore(backend: backend)
        store.save(makeCredentials(id: "old"))
        store.save(makeCredentials(id: "gone", name: "Kitchen"))
        store.rekey(from: "old", to: "new")
        store.remove(deviceID: "gone")

        let reloaded = CredentialStore(backend: backend)
        #expect(reloaded.credentials.map(\.deviceID) == ["new"])
        #expect(reloaded.credentials(for: "new")?.deviceName == "Living Room")
    }
}
