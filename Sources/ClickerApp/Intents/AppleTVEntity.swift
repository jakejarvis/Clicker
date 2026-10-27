import AppIntents

/// An Apple TV as a Shortcuts parameter: one Clicker has paired with, or
/// can see on the network.
nonisolated struct AppleTVEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Apple TV"
    static let defaultQuery = AppleTVQuery()

    let id: String
    let name: String
    let modelName: String

    init(_ device: AppleTVDevice) {
        id = device.id
        name = device.name
        modelName = device.modelDisplayName
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(modelName)")
    }
}

/// Paired TVs, online or not, so an automation can wake one that is
/// asleep; the action itself waits for Bonjour to find it.
nonisolated struct AppleTVQuery: EntityStringQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [AppleTVEntity] {
        let devices = try await IntentHost.current().devices
        return identifiers.compactMap { id in devices.first { $0.id == id } }.map(AppleTVEntity.init)
    }

    @MainActor func suggestedEntities() async throws -> [AppleTVEntity] {
        let controller = try await IntentHost.current()
        return controller.devices.filter(controller.isPaired).map(AppleTVEntity.init)
    }

    @MainActor func entities(matching string: String) async throws -> [AppleTVEntity] {
        try await suggestedEntities().filter { $0.name.localizedStandardContains(string) }
    }
}
