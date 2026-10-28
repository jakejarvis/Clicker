import AppIntents

/// Wake, as the panel's power menu sends it: the Wake button. A TV asleep
/// behind a Bonjour sleep proxy still answers the connect, which wakes it.
struct WakeAppleTVIntent: nonisolated AppIntent {
    nonisolated static let title: LocalizedStringResource = "Wake Apple TV"
    nonisolated static let description = IntentDescription("Wakes the Apple TV.")

    @Parameter(title: "Apple TV", description: "Leave empty for the Apple TV selected in Clicker.")
    var device: AppleTVEntity?

    nonisolated static var parameterSummary: some ParameterSummary {
        Summary("Wake \(\.$device)")
    }

    nonisolated init() {}

    init(device: AppleTVEntity?) {
        self.device = device
    }

    @MainActor func perform() async throws -> some IntentResult {
        try await perform(on: IntentHost.current())
        return .result()
    }

    func perform(on controller: RemoteController) async throws {
        try await IntentHost.translatingErrors {
            try await controller.prepareForIntent(deviceID: device?.id)
            try await controller.pressForIntent(.wake)
        }
    }
}
