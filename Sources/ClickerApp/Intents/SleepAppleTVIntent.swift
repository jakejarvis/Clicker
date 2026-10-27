import AppIntents

/// Sleep, as the panel's power menu sends it: the Sleep button.
struct SleepAppleTVIntent: nonisolated AppIntent {
    nonisolated static let title: LocalizedStringResource = "Put Apple TV to Sleep"
    nonisolated static let description = IntentDescription("Puts the Apple TV to sleep.")

    @Parameter(title: "Apple TV", description: "Leave empty for the Apple TV selected in Clicker.")
    var device: AppleTVEntity?

    nonisolated static var parameterSummary: some ParameterSummary {
        Summary("Put \(\.$device) to sleep")
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
            try await controller.pressForIntent(.sleep)
        }
    }
}
