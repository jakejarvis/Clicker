import Foundation
import Testing

@testable import ClickerApp
@testable import ClickerDemo

@Suite @MainActor struct ControllerSettingsTests {
    /// What the controller remembers survives a relaunch: a second store on
    /// the same defaults reads back what the first wrote.
    @Test func defaultsRoundTripEveryValue() throws {
        let suite = "ControllerSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let written = DefaultsControllerSettings(defaults: defaults)
        #expect(written.selectedDeviceID == nil)
        #expect(written.recentAppIDsByDevice.isEmpty)
        written.selectedDeviceID = "TV-1"
        written.recentAppIDsByDevice = ["TV-1": ["com.netflix.Netflix", "com.apple.TVWatchList"]]
        written.favoriteAppIDsByDevice = ["TV-1": ["com.plexapp.plex"]]
        written.lastAddressByDevice = ["TV-1": "192.168.1.42"]

        let read = DefaultsControllerSettings(defaults: defaults)
        #expect(read.selectedDeviceID == "TV-1")
        #expect(read.recentAppIDsByDevice == ["TV-1": ["com.netflix.Netflix", "com.apple.TVWatchList"]])
        #expect(read.favoriteAppIDsByDevice == ["TV-1": ["com.plexapp.plex"]])
        #expect(read.lastAddressByDevice == ["TV-1": "192.168.1.42"])

        read.selectedDeviceID = nil
        #expect(written.selectedDeviceID == nil)
    }

    @Test func demoPairingsFollowWritesAndDeletes() throws {
        let backend = DemoCredentialBackend(
            initial: [DemoTV.livingRoom.credentials(pairedAt: .distantPast)], refusesStore: false)
        let store = CredentialStore(backend: backend)
        store.remove(deviceID: DemoTV.livingRoom.id)
        try store.save(DemoTV.bedroom.credentials(pairedAt: .now))
        #expect(CredentialStore(backend: backend).credentials.map(\.deviceName) == ["Bedroom"])
    }

    /// Living Room's settings stick whether it is online or only paired.
    @Test func scenarioEditsAnOfflineLivingRoom() {
        let scenario = DemoScenario("test") {
            $0.online = [.bedroom]
            $0.livingRoom.power = .asleep
            $0.livingRoom.acceptsCode = false
        }
        #expect(scenario.livingRoom.power == .asleep)
        #expect(scenario.livingRoom.acceptsCode == false)
    }
}
