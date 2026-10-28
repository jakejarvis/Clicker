import ClickerApp

/// The controller's remembered state, in memory.
final class DemoSettings: ControllerSettings {
    var selectedDeviceID: String?
    var recentAppIDsByDevice: [String: [String]] = [:]
    var favoriteAppIDsByDevice: [String: [String]] = [:]
    var lastAddressByDevice: [String: String] = [:]
    var knownAppsByDevice: [String: [String: String]] = [:]
}
