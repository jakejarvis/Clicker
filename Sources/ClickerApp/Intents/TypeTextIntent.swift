import AppIntents

/// Types into the field the Apple TV has focused, as the panel's text field
/// does. Without a focused field there is nothing to type into, and the
/// action says so rather than send keys into the void.
struct TypeTextIntent: nonisolated AppIntent {
    nonisolated static let title: LocalizedStringResource = "Type Text on Apple TV"
    nonisolated static let description = IntentDescription(
        "Types text into the Apple TV's focused text field, such as a search or sign-in field.")

    @Parameter(title: "Text")
    var text: String

    @Parameter(title: "Press Return", description: "Press Return after typing, which runs a search.", default: false)
    var pressReturn: Bool

    @Parameter(title: "Apple TV", description: "Leave empty for the Apple TV selected in Clicker.")
    var device: AppleTVEntity?

    nonisolated static var parameterSummary: some ParameterSummary {
        Summary("Type \(\.$text) on the Apple TV") {
            \.$pressReturn
            \.$device
        }
    }

    nonisolated init() {}

    init(text: String, pressReturn: Bool = false, device: AppleTVEntity? = nil) {
        self.text = text
        self.pressReturn = pressReturn
        self.device = device
    }

    @MainActor func perform() async throws -> some IntentResult {
        try await perform(on: IntentHost.current())
        return .result()
    }

    func perform(on controller: RemoteController) async throws {
        try await IntentHost.translatingErrors {
            try await controller.prepareForIntent(deviceID: device?.id)
            try await controller.typeForIntent(text, pressingReturn: pressReturn)
        }
    }
}
