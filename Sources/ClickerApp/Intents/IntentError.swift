import AppIntents

/// Why a Shortcuts action did not reach the TV, in the panel's words.
nonisolated enum IntentError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    /// No TV is selected and the action names none.
    case noAppleTV
    /// The action names a TV Clicker no longer knows: unpaired and not on
    /// the network.
    case unknownAppleTV
    case notPaired(String)
    /// The TV is paired but Bonjour has not reported it.
    case notFound(String)
    case connectFailed(String)
    case noTextField
    case commandFailed(String)
    /// Clicker did not finish launching in time to run the action.
    case notRunning

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noAppleTV: "Choose an Apple TV in Clicker first."
        case .unknownAppleTV: "Clicker doesn't know that Apple TV anymore. Choose another one in the action."
        case .notPaired(let name): "\(name) isn't paired with Clicker. Pair it from Clicker in the menu bar first."
        case .notFound(let name): "Clicker can't find \(name) on the network."
        case .connectFailed(let message): "\(message)"
        case .noTextField: "The Apple TV isn't showing a text field to type into."
        case .commandFailed(let message): "\(message)"
        case .notRunning: "Clicker didn't start in time. Try the action again."
        }
    }
}
