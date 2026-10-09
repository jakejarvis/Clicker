import Foundation
import Testing

@testable import Clicker

@Suite struct AppFavoritesTests {
    @Test @MainActor func demoStartsWithPinnedApps() {
        let controller = RemoteController(demo: .ready)
        controller.start()
        #expect(controller.favoriteApps.map(\.name) == ["Plex", "Music"])
        #expect(controller.recentApps.map(\.name) == ["Netflix", "TV", "YouTube"])
    }

    @Test @MainActor func togglingStarsAndUnstarsInOrder() {
        let controller = RemoteController(demo: .ready)
        controller.start()
        let netflix = try! #require(controller.apps.first { $0.name == "Netflix" })
        let plex = try! #require(controller.apps.first { $0.name == "Plex" })

        #expect(controller.isFavorite(netflix) == false)
        controller.toggleFavorite(netflix)
        #expect(controller.isFavorite(netflix))
        #expect(controller.favoriteApps.map(\.name) == ["Plex", "Music", "Netflix"])

        controller.toggleFavorite(plex)
        #expect(controller.isFavorite(plex) == false)
        #expect(controller.favoriteApps.map(\.name) == ["Music", "Netflix"])
    }

    @Test @MainActor func clearingRecentsLeavesFavorites() {
        let controller = RemoteController(demo: .ready)
        controller.start()
        controller.clearRecents()
        #expect(controller.recentApps.isEmpty)
        #expect(controller.favoriteApps.map(\.name) == ["Plex", "Music"])
    }

    @Test @MainActor func forgettingATVDropsItsFavorites() {
        let controller = RemoteController(demo: .ready)
        controller.start()
        let device = try! #require(controller.selectedDevice)
        #expect(!controller.favoriteApps.isEmpty)
        controller.forgetPairing(for: device)
        #expect(controller.favoriteAppIDsByDevice[device.id] == nil)
    }
}
