import AppIntents

/// Opens the menu bar panel, as the status item and the global shortcut do.
struct ShowRemoteIntent: nonisolated AppIntent {
    nonisolated static let title: LocalizedStringResource = "Show Remote"
    nonisolated static let description = IntentDescription("Opens Clicker's remote from the menu bar.")

    nonisolated static var parameterSummary: some ParameterSummary {
        Summary("Show the Clicker remote")
    }

    @MainActor func perform() async throws -> some IntentResult {
        _ = try await IntentHost.current()
        IntentHost.openPanel()
        return .result()
    }
}
