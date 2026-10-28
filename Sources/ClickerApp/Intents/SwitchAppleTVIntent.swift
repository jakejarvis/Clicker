import AppIntents

/// Selects a TV as the device menu does: the panel and every action
/// without an Apple TV of its own follow it.
struct SwitchAppleTVIntent: nonisolated AppIntent {
    nonisolated static let title: LocalizedStringResource = "Switch Apple TV"
    nonisolated static let description = IntentDescription(
        "Chooses which Apple TV Clicker controls, as picking it in the device menu does.")

    @Parameter(title: "Apple TV")
    var device: AppleTVEntity

    nonisolated static var parameterSummary: some ParameterSummary {
        Summary("Switch Clicker to \(\.$device)")
    }

    nonisolated init() {}

    init(device: AppleTVEntity) {
        self.device = device
    }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let name = try await perform(on: IntentHost.current())
        return .result(dialog: "Clicker now controls \(name).")
    }

    /// Returns the selected TV's name.
    func perform(on controller: RemoteController) async throws -> String {
        var name = device.name
        try await IntentHost.translatingErrors {
            name = try await controller.selectForIntent(deviceID: device.id).name
        }
        return name
    }
}
