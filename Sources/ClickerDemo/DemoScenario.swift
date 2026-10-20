import ClickerApp
import ClickerCompanion

/// A canned state for screenshots and checking wording, picked with
/// `--demo [scenario]`: which made-up Apple TVs are around, how they answer,
/// and what to do once the panel is up. Every state is reached through
/// `RemoteController`'s own code, so a trouble card shows exactly what a real
/// TV failing that way would.
nonisolated struct DemoScenario: Sendable {
    /// Something done to the app once the panel is up, as a click would.
    enum Step: Sendable {
        case beginPairing
        case enterCode(String)
        case showSettings
        case openApps
        case openDevices
        case mute
        /// The TV closes the session.
        case dropSession
    }

    let name: String
    /// Apple TVs on the "network".
    var online: [DemoTV] = [.livingRoom, .bedroom, .office]
    /// Paired at launch. Office never is, so the device list always shows a
    /// Pair badge.
    var paired: [DemoTV] = [.livingRoom, .bedroom]
    /// The selection remembered from the "last launch".
    var selected: DemoTV? = .livingRoom
    /// The keychain refuses to store a new pairing (a missing-entitlement
    /// error from the add itself, after the availability probe passed).
    var refusesStore = false
    /// macOS has Clicker turned off under Privacy & Security › Local Network.
    var localNetworkDenied = false
    var pendingUpdateVersion: String?
    var steps: [Step] = []
    /// Stretched where the real timing would move the panel on before a
    /// screenshot, or shortened where it would keep one waiting.
    var timings = RemoteTimings()

    init(_ name: String, _ configure: (inout DemoScenario) -> Void = { _ in }) {
        self.name = name
        configure(&self)
    }

    /// Living Room as this scenario has it, wherever it appears.
    var livingRoom: DemoTV {
        get { (online + paired).first { $0.uuid == DemoTV.livingRoom.uuid } ?? .livingRoom }
        set {
            online = online.map { $0.uuid == newValue.uuid ? newValue : $0 }
            paired = paired.map { $0.uuid == newValue.uuid ? newValue : $0 }
        }
    }

    static let all: [DemoScenario] = [
        // Living Room connected and awake.
        DemoScenario("ready"),
        // Living Room connected but asleep.
        DemoScenario("asleep") { $0.livingRoom.power = .asleep },
        // A text field focused on the TV.
        DemoScenario("typing") { $0.livingRoom.focusedText = "Nature documentaries" },
        // The Settings screen over a ready remote.
        DemoScenario("settings") { $0.steps = [.showSettings] },
        // The Apps picker open over a ready remote.
        DemoScenario("apps") { $0.steps = [.openApps] },
        // The device list open over a ready remote.
        DemoScenario("devices") { $0.steps = [.openDevices] },
        // Living Room found but not paired yet.
        DemoScenario("pair") { $0.paired = [.bedroom] },
        // Pairing with Living Room, waiting for the code.
        DemoScenario("pin") {
            $0.paired = [.bedroom]
            $0.steps = [.beginPairing]
        },
        // The check shown the moment pairing finishes, held on screen.
        DemoScenario("paired") {
            $0.paired = [.bedroom]
            $0.steps = [.beginPairing, .enterCode("1234")]
            $0.timings.pairingSuccessHold = .seconds(3600)
        },
        // Living Room paired but not on the network.
        DemoScenario("offline") { $0.online = [.bedroom, .office] },
        // No Apple TVs found.
        DemoScenario("searching") {
            $0.online = []
            $0.paired = []
            $0.selected = nil
        },
        // Paired Apple TVs, none on the network and none chosen. (With any
        // TV online the controller picks one itself.)
        DemoScenario("choose") {
            $0.online = []
            $0.selected = nil
        },
        // Living Room refuses PIN pairing (Remote App and Devices turned off).
        DemoScenario("pairingdisabled") {
            $0.paired = [.bedroom]
            $0.livingRoom.pairingDisabled = true
        },
        // Living Room was reset: pair-verify drops the stale pairing with a notice.
        DemoScenario("reset") { $0.livingRoom.connectError = .identityChanged },
        // Living Room removed Clicker from Remotes and Devices: same, other notice.
        DemoScenario("removed") { $0.livingRoom.connectError = .pairingLost },
        // The wrong code was entered.
        DemoScenario("pairingfailed") {
            $0.paired = [.bedroom]
            $0.livingRoom.acceptsCode = false
            $0.steps = [.beginPairing, .enterCode("1234")]
        },
        // The TV accepted the pairing but the keychain refused to store it.
        DemoScenario("savefailed") {
            $0.paired = [.bedroom]
            $0.refusesStore = true
            $0.steps = [.beginPairing, .enterCode("1234")]
        },
        // Living Room paired and online, the connection still being set up.
        DemoScenario("connecting") { $0.livingRoom.answersConnect = false },
        // Living Room paired and online but the connection failed.
        DemoScenario("connectionfailed") { $0.livingRoom.connectError = .connectionFailed(.posix(.ECONNREFUSED)) },
        // macOS refused Clicker the local network: the connect times out
        // and the probe that follows reports the denial.
        DemoScenario("localnetwork") {
            $0.livingRoom.connectError = .timeout
            $0.localNetworkDenied = true
        },
        // The TV closed the session while the panel was open; the reconnect
        // is held off so the notice stays.
        DemoScenario("disconnected") {
            $0.steps = [.dropSession]
            $0.timings.reconnectDelay = .seconds(3600)
        },
        // Living Room over HDMI: Mute was tried, did nothing, and is now disabled.
        DemoScenario("hdmi") {
            $0.livingRoom.echoesVolume = false
            $0.steps = [.mute]
            $0.timings.muteConfirmationTimeout = .milliseconds(500)
        },
        // An update found in the background: an inline notice and the menus' Update to… items.
        DemoScenario("update") { $0.pendingUpdateVersion = "1.1.0" },
        // A failed connection with an update pending: both inline notices stacked.
        DemoScenario("notices") {
            $0.livingRoom.connectError = .connectionFailed(.posix(.ECONNREFUSED))
            $0.pendingUpdateVersion = "1.1.0"
        },
    ]

    static func named(_ name: String) -> DemoScenario? {
        all.first { $0.name == name.lowercased() }
    }

    /// The scenario the launch arguments ask for, if any: `--demo` on its
    /// own means `ready`. An unknown name is an error, so a typo does not
    /// quietly show the wrong state.
    static func parse(_ arguments: [String]) -> Result<DemoScenario, UnknownName>? {
        guard let index = arguments.firstIndex(of: "--demo") else { return nil }
        let next = arguments.index(after: index)
        guard next < arguments.endIndex, !arguments[next].hasPrefix("-") else { return .success(named("ready")!) }
        guard let scenario = named(arguments[next]) else { return .failure(UnknownName(name: arguments[next])) }
        return .success(scenario)
    }

    struct UnknownName: Error, Equatable, CustomStringConvertible {
        let name: String

        var description: String {
            "Unknown demo scenario \"\(name)\". Scenarios: \(DemoScenario.all.map(\.name).joined(separator: ", "))"
        }
    }

    // MARK: - Content

    /// Enough apps that the picker scrolls, in the TV's alphabetical order.
    static let apps: [AppleTVApp] = [
        AppleTVApp(bundleIdentifier: "com.apple.Arcade", name: "Arcade"),
        AppleTVApp(bundleIdentifier: "com.disney.disneyplus", name: "Disney+"),
        AppleTVApp(bundleIdentifier: "com.apple.Fitness", name: "Fitness"),
        AppleTVApp(bundleIdentifier: "com.wbd.stream", name: "HBO Max"),
        AppleTVApp(bundleIdentifier: "com.hulu.plus", name: "Hulu"),
        AppleTVApp(bundleIdentifier: "com.apple.TVMusic", name: "Music"),
        AppleTVApp(bundleIdentifier: "com.netflix.Netflix", name: "Netflix"),
        AppleTVApp(bundleIdentifier: "com.cbsvideo.app", name: "Paramount+"),
        AppleTVApp(bundleIdentifier: "com.peacocktv.peacock", name: "Peacock"),
        AppleTVApp(bundleIdentifier: "com.apple.TVPhotos", name: "Photos"),
        AppleTVApp(bundleIdentifier: "com.plexapp.plex", name: "Plex"),
        AppleTVApp(bundleIdentifier: "com.apple.podcasts", name: "Podcasts"),
        AppleTVApp(bundleIdentifier: "com.amazon.aiv.AIVApp", name: "Prime Video"),
        AppleTVApp(bundleIdentifier: "com.apple.TVSettings", name: "Settings"),
        AppleTVApp(bundleIdentifier: "com.apple.TVWatchList", name: "TV"),
        AppleTVApp(bundleIdentifier: "com.google.ios.youtube", name: "YouTube"),
    ]

    /// Recently launched apps on Living Room, newest first.
    static let recentAppIDs = ["com.netflix.Netflix", "com.apple.TVWatchList", "com.google.ios.youtube"]

    /// Starred apps on Living Room, pinned above the recents.
    static let favoriteAppIDs = ["com.plexapp.plex", "com.apple.TVMusic"]

    /// The TV's user profiles, for the Switch User menu.
    static let userAccounts = [UserAccount(id: "1", name: "Alex"), UserAccount(id: "2", name: "Sam")]

    /// Name shown in Settings, and sent to the TVs, in place of this Mac's.
    static let clientName = "MacBook Pro"
}
