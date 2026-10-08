import Foundation

/// Canned states for screenshots and demos, picked with `--demo [scenario]`.
///
/// A demo run never browses, connects or touches the stored pairings or the
/// remembered selection: devices and pairings live in memory, the selected
/// TV is "connected" at once, remote commands go nowhere, and pairing walks
/// through its steps on timers and accepts any code.
enum DemoScenario: String, CaseIterable, Sendable {
    /// Living Room connected and awake.
    case ready
    /// Living Room connected but asleep.
    case asleep
    /// Living Room with a text field focused on the TV.
    case typing
    /// The Settings screen over a ready remote.
    case settings
    /// Living Room found but not paired yet.
    case pair
    /// Pairing with Living Room, waiting for the code.
    case pin
    /// The check shown the moment pairing finishes.
    case paired
    /// Living Room paired but not on the network.
    case offline
    /// No Apple TVs found.
    case searching
    /// Apple TVs found, none chosen.
    case choose

    /// The scenario from the launch arguments, if any. `--demo` on its own,
    /// or with a name it does not know, means `ready`.
    static let current: DemoScenario? = parse(CommandLine.arguments)

    static func parse(_ arguments: [String]) -> DemoScenario? {
        guard let index = arguments.firstIndex(of: "--demo") else { return nil }
        let next = arguments.index(after: index)
        guard next < arguments.endIndex, !arguments[next].hasPrefix("-") else { return .ready }
        return DemoScenario(rawValue: arguments[next].lowercased()) ?? .ready
    }

    // MARK: - Devices

    static let livingRoom = device(name: "Living Room", model: "AppleTV14,1")
    static let bedroom = device(name: "Bedroom", model: "AppleTV11,1")
    static let office = device(name: "Office", model: "AppleTV6,2")

    /// Apple TVs on the "network".
    var onlineDevices: [AppleTVDevice] {
        switch self {
        case .searching: return []
        case .offline: return [Self.bedroom, Self.office]
        default: return [Self.livingRoom, Self.bedroom, Self.office]
        }
    }

    /// Apple TVs already paired at launch. Office is never paired, so the
    /// device list always shows a Pair badge.
    var pairedDevices: [AppleTVDevice] {
        switch self {
        case .searching: return []
        case .pair, .pin: return [Self.bedroom]
        default: return [Self.livingRoom, Self.bedroom]
        }
    }

    var selectedDeviceID: String? {
        switch self {
        case .searching, .choose: return nil
        default: return Self.livingRoom.id
        }
    }

    var pairingState: PairingState {
        switch self {
        case .pin: return .awaitingPIN
        case .paired: return .succeeded
        default: return .idle
        }
    }

    var screen: PanelScreen { self == .settings ? .settings : .remote }

    var powerState: PowerState { self == .asleep ? .asleep : .awake }

    var keyboardSession: TextInputArchive.Session? {
        guard self == .typing else { return nil }
        return TextInputArchive.Session(sessionUUID: UUID(), currentText: "Nature documentaries")
    }

    static let apps: [AppleTVApp] = [
        AppleTVApp(bundleIdentifier: "com.apple.TVWatchList", name: "TV"),
        AppleTVApp(bundleIdentifier: "com.apple.TVMusic", name: "Music"),
        AppleTVApp(bundleIdentifier: "com.apple.Arcade", name: "Arcade"),
        AppleTVApp(bundleIdentifier: "com.apple.TVPhotos", name: "Photos"),
        AppleTVApp(bundleIdentifier: "com.apple.podcasts", name: "Podcasts"),
        AppleTVApp(bundleIdentifier: "com.apple.Fitness", name: "Fitness"),
        AppleTVApp(bundleIdentifier: "com.apple.TVSettings", name: "Settings"),
    ]

    /// Name shown in Settings in place of this Mac's.
    static let clientName = "MacBook Pro"

    /// Shows the demo name in Settings without writing it anywhere: the
    /// argument domain is volatile and outranks the saved name.
    static func overrideDefaults() {
        let defaults = UserDefaults.standard
        var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments[IdentityStore.clientNameKey] = clientName
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }

    /// Placeholder keys; nothing ever connects with them.
    static func credentials(for device: AppleTVDevice) -> PairingCredentials {
        PairingCredentials(
            deviceID: device.id,
            deviceName: device.name,
            deviceModel: device.model,
            accessoryIdentifier: Data(),
            accessoryPublicKey: Data(),
            clientIdentifier: "demo",
            clientPrivateKey: Data(),
            pairedAt: .now
        )
    }

    /// Demo devices have no endpoint, so they are marked online by hand.
    private static func device(name: String, model: String) -> AppleTVDevice {
        var device = AppleTVDevice(
            id: "demo-\(name.lowercased().replacingOccurrences(of: " ", with: "-"))",
            name: name,
            model: model,
            endpoint: nil,
            pairingDisabled: false
        )
        device.isOnline = true
        return device
    }
}

/// Pairings for a demo run: seeded at launch, kept only in memory.
struct DemoCredentialBackend: CredentialBackend {
    let initial: [PairingCredentials]

    func loadAll() throws -> [PairingCredentials] { initial }
    func store(_ credentials: PairingCredentials) throws {}
    func delete(deviceID: String) throws {}
}
