import Foundation

/// What `RemoteController` remembers between launches. The real store is
/// user defaults; the demo build keeps it in memory so a demo run never
/// touches the user's selection or app lists.
package protocol ControllerSettings: AnyObject {
    var selectedDeviceID: String? { get set }
    /// Recently launched apps per TV, newest first, keyed by device id.
    var recentAppIDsByDevice: [String: [String]] { get set }
    /// Starred apps per TV, in the order they were starred.
    var favoriteAppIDsByDevice: [String: [String]] { get set }
    /// The host each TV was last connected at, for Rescan's wake knock.
    var lastAddressByDevice: [String: String] { get set }
}

/// `ControllerSettings` in user defaults, the standard ones in a real run.
final class DefaultsControllerSettings: ControllerSettings {
    private static let selectedDeviceKey = "selectedDeviceID"
    private static let recentAppsKey = "recentAppIDsByDevice"
    private static let favoriteAppsKey = "favoriteAppIDsByDevice"
    private static let lastAddressesKey = "lastAddressByDevice"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedDeviceID: String? {
        get { defaults.string(forKey: Self.selectedDeviceKey) }
        set { defaults.set(newValue, forKey: Self.selectedDeviceKey) }
    }

    var recentAppIDsByDevice: [String: [String]] {
        get { defaults.dictionary(forKey: Self.recentAppsKey) as? [String: [String]] ?? [:] }
        set { defaults.set(newValue, forKey: Self.recentAppsKey) }
    }

    var favoriteAppIDsByDevice: [String: [String]] {
        get { defaults.dictionary(forKey: Self.favoriteAppsKey) as? [String: [String]] ?? [:] }
        set { defaults.set(newValue, forKey: Self.favoriteAppsKey) }
    }

    var lastAddressByDevice: [String: String] {
        get { defaults.dictionary(forKey: Self.lastAddressesKey) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Self.lastAddressesKey) }
    }
}
