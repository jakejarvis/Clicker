import Foundation
import Testing

@testable import ClickerApp
@testable import ClickerDemo

@Suite @MainActor struct AppFavoritesTests {
    @Test func demoStartsWithPinnedApps() async throws {
        let run = try await DemoRun("ready")
        #expect(await run.connected())
        #expect(run.controller.favoriteApps.map(\.name) == ["Plex", "Music"])
        #expect(run.controller.recentApps.map(\.name) == ["Netflix", "TV", "YouTube"])
    }

    @Test func togglingStarsAndUnstarsInOrder() async throws {
        let run = try await DemoRun("ready")
        let controller = run.controller
        #expect(await run.connected())
        let netflix = try #require(controller.apps.first { $0.name == "Netflix" })
        let plex = try #require(controller.apps.first { $0.name == "Plex" })

        #expect(controller.isFavorite(netflix) == false)
        controller.toggleFavorite(netflix)
        #expect(controller.isFavorite(netflix))
        #expect(controller.favoriteApps.map(\.name) == ["Plex", "Music", "Netflix"])

        controller.toggleFavorite(plex)
        #expect(controller.isFavorite(plex) == false)
        #expect(controller.favoriteApps.map(\.name) == ["Music", "Netflix"])
        #expect(run.settings.favoriteAppIDsByDevice == controller.favoriteAppIDsByDevice)
    }

    @Test func clearingRecentsLeavesFavorites() async throws {
        let run = try await DemoRun("ready")
        #expect(await run.connected())
        run.controller.clearRecents()
        #expect(run.controller.recentApps.isEmpty)
        #expect(run.controller.favoriteApps.map(\.name) == ["Plex", "Music"])
    }

    @Test func forgettingATVDropsItsFavorites() async throws {
        let run = try await DemoRun("ready")
        let controller = run.controller
        let device = try #require(controller.selectedDevice)
        #expect(await run.connected())
        #expect(!controller.favoriteApps.isEmpty)
        controller.forgetPairing(for: device)
        #expect(controller.favoriteAppIDsByDevice[device.id] == nil)
        #expect(run.settings.favoriteAppIDsByDevice[device.id] == nil)
        #expect(run.settings.lastAddressByDevice[device.id] == nil)
    }
}
