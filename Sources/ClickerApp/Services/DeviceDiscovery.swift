/// The Apple TVs on the network, as `RemoteController` and the picker see
/// them. `DeviceBrowser` is the real one; the demo build has made-up TVs.
package protocol DeviceDiscovery: AnyObject {
    var devices: [AppleTVDevice] { get }
    /// True for a moment after `rescan`, for the picker's Rescan row.
    var isRescanning: Bool { get }
    /// Why discovery stopped, for the Searching card.
    var errorMessage: String? { get }
    /// Called whenever `devices` changes.
    var onUpdate: (([AppleTVDevice]) -> Void)? { get set }

    /// Starts discovering; does nothing when already running.
    func start()
    /// The picker's ⌥-click Rescan: looks again, first knocking on `host`
    /// (the selected TV's last address) in case it sleeps behind a proxy.
    func rescan(knocking host: String?)
}

extension DeviceBrowser: DeviceDiscovery {
    func rescan(knocking host: String?) {
        if let host { PortKnocker.knock(host: host) }
        restart()
    }
}
