import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// The global shortcut that opens or closes the panel from any app. Unset
    /// until the user records one in Settings; the package stores it in user
    /// defaults and registers it with Carbon, which needs no permission.
    @MainActor static let togglePanel = Self("togglePanel")
}
