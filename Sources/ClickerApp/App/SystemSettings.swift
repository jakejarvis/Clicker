import AppKit

/// Opens panes of System Settings.
enum SystemSettings {
    /// Privacy & Security › Local Network, where Clicker's switch is.
    static func openLocalNetworkPrivacy() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
