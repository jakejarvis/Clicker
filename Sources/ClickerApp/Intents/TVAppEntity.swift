import AppIntents
import ClickerCompanion

/// An app on the Apple TV as a Shortcuts parameter. It is launched by
/// bundle identifier, so one picked from one TV opens on any TV that has it.
nonisolated struct TVAppEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Apple TV App"
    static let defaultQuery = TVAppQuery()

    let id: String
    let name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(_ app: AppleTVApp) {
        self.init(id: app.bundleIdentifier, name: app.name)
    }

    var app: AppleTVApp { AppleTVApp(bundleIdentifier: id, name: name) }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// The connected TV's apps, or every TV's last known list while none is
/// connected (`RemoteController.knownApps`): the editor asks for them
/// with the TV asleep too. Starred and recent apps come first.
nonisolated struct TVAppQuery: EntityStringQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [TVAppEntity] {
        let apps = try await IntentHost.current().knownApps
        // An app missing from the lists (they were cleared) still launches
        // by its identifier.
        return identifiers.map { id in apps.first { $0.id == id }.map(TVAppEntity.init) ?? TVAppEntity(id: id, name: id)
        }
    }

    @MainActor func suggestedEntities() async throws -> [TVAppEntity] {
        let controller = try await IntentHost.current()
        var seen = Set<String>()
        let ordered = controller.favoriteApps + controller.recentApps + controller.knownApps
        return ordered.filter { seen.insert($0.id).inserted }.map(TVAppEntity.init)
    }

    @MainActor func entities(matching string: String) async throws -> [TVAppEntity] {
        try await suggestedEntities().filter { $0.name.localizedStandardContains(string) }
    }
}
