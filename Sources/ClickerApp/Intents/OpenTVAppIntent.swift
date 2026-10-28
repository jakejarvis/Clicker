import AppIntents

struct OpenTVAppIntent: nonisolated AppIntent {
    nonisolated static let title: LocalizedStringResource = "Open App on Apple TV"
    nonisolated static let description = IntentDescription("Opens an app on the Apple TV.")

    @Parameter(title: "App")
    var app: TVAppEntity

    @Parameter(title: "Apple TV", description: "Leave empty for the Apple TV selected in Clicker.")
    var device: AppleTVEntity?

    nonisolated static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$app) on the Apple TV") {
            \.$device
        }
    }

    nonisolated init() {}

    init(app: TVAppEntity, device: AppleTVEntity? = nil) {
        self.app = app
        self.device = device
    }

    @MainActor func perform() async throws -> some IntentResult {
        try await perform(on: IntentHost.current())
        return .result()
    }

    func perform(on controller: RemoteController) async throws {
        try await IntentHost.translatingErrors {
            try await controller.prepareForIntent(deviceID: device?.id)
            try await controller.launchForIntent(app.app)
        }
    }
}
