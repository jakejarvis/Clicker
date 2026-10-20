import ClickerCompanion
import Network

/// Everything `RemoteController` reaches outside the process through. `live`
/// is the real network, keychain and defaults; the demo build and the tests
/// pass made-up Apple TVs and in-memory stores instead.
package struct RemoteDependencies {
    package var discovery: any DeviceDiscovery
    package var credentialBackend: any CredentialBackend
    package var settings: any ControllerSettings
    /// This Mac as the TV sees it.
    package var identity: () -> ClientIdentity
    package var makeSession: (NWEndpoint, PairingCredentials, ClientIdentity) -> any RemoteSession
    package var makePairingSession: (NWEndpoint) -> any PairingSession
    /// Whether macOS lets Clicker on the local network, asked after a
    /// connect times out.
    package var localNetworkAccess: () async -> LocalNetworkAccess.Status
    package var timings: RemoteTimings

    package init(
        discovery: any DeviceDiscovery,
        credentialBackend: any CredentialBackend,
        settings: any ControllerSettings,
        identity: @escaping () -> ClientIdentity,
        makeSession: @escaping (NWEndpoint, PairingCredentials, ClientIdentity) -> any RemoteSession,
        makePairingSession: @escaping (NWEndpoint) -> any PairingSession,
        localNetworkAccess: @escaping () async -> LocalNetworkAccess.Status,
        timings: RemoteTimings = RemoteTimings()
    ) {
        self.discovery = discovery
        self.credentialBackend = credentialBackend
        self.settings = settings
        self.identity = identity
        self.makeSession = makeSession
        self.makePairingSession = makePairingSession
        self.localNetworkAccess = localNetworkAccess
        self.timings = timings
    }

    /// Bonjour, the Companion protocol, the keychain (or its file fallback),
    /// user defaults and the local network probe.
    static var live: RemoteDependencies {
        RemoteDependencies(
            discovery: DeviceBrowser(),
            credentialBackend: CredentialStore.defaultBackend(),
            settings: DefaultsControllerSettings(),
            identity: IdentityStore.identity,
            makeSession: { CompanionClient(endpoint: $0, credentials: $1, identity: $2) },
            makePairingSession: { CompanionPairingSession(endpoint: $0) },
            localNetworkAccess: LocalNetworkAccess.check
        )
    }
}

/// How long `RemoteController` waits for things the TV does or doesn't do.
/// The demo build stretches some to hold a state on screen; tests shrink them.
package nonisolated struct RemoteTimings: Sendable {
    /// After a dropped session, before connecting again, so a TV that is
    /// tearing down (sleep, a restart) is not hit at once.
    package var reconnectDelay: Duration
    /// How long the pair card's check shows before the remote takes over.
    package var pairingSuccessHold: Duration
    /// How long a SetVolume gets to be echoed by an `_iMC` event; pyatv
    /// waits the same (see `RemoteController.confirmMute`).
    package var muteConfirmationTimeout: Duration

    package init(
        reconnectDelay: Duration = .seconds(1),
        pairingSuccessHold: Duration = .seconds(1.2),
        muteConfirmationTimeout: Duration = .seconds(5)
    ) {
        self.reconnectDelay = reconnectDelay
        self.pairingSuccessHold = pairingSuccessHold
        self.muteConfirmationTimeout = muteConfirmationTimeout
    }
}
