import AppIntents

struct PressButtonIntent: nonisolated AppIntent {
    nonisolated static let title: LocalizedStringResource = "Press Remote Button"
    nonisolated static let description = IntentDescription("Presses a button on the Apple TV's remote.")

    @Parameter(title: "Button")
    var button: RemoteButton

    @Parameter(title: "Apple TV", description: "Leave empty for the Apple TV selected in Clicker.")
    var device: AppleTVEntity?

    nonisolated static var parameterSummary: some ParameterSummary {
        Summary("Press \(\.$button)") {
            \.$device
        }
    }

    nonisolated init() {}

    init(button: RemoteButton, device: AppleTVEntity? = nil) {
        self.button = button
        self.device = device
    }

    @MainActor func perform() async throws -> some IntentResult {
        try await perform(on: IntentHost.current())
        return .result()
    }

    func perform(on controller: RemoteController) async throws {
        try await IntentHost.translatingErrors {
            try await controller.prepareForIntent(deviceID: device?.id)
            try await controller.pressForIntent(button.command)
        }
    }
}
