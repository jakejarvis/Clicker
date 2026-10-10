import Foundation

#if DEMO
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
        /// Living Room refuses PIN pairing (Remote App and Devices turned off).
        case pairingdisabled
        /// Living Room was reset: the stale pairing was dropped with a notice.
        case reset
        /// Living Room removed Clicker from Remotes and Devices: same, other notice.
        case removed
        /// The wrong code was entered.
        case pairingfailed
        /// Living Room paired and online but the connection failed.
        case connectionfailed
        /// Living Room paired and online, connection closed.
        case disconnected
        /// Living Room over HDMI: Mute just failed and is now disabled.
        case hdmi
        /// An update found in the background: dot on the status item, footer button.
        case update

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

        static let livingRoom = device(
            name: "Living Room", model: "AppleTV14,1", address: "A4:83:E7:2C:91:0D",
            uuid: "7B1E4C2A-5D3F-4E8B-9A6C-1F2D3E4A5B6C")
        /// Living Room with pairing turned off on the TV.
        static let livingRoomPairingDisabled = device(
            name: "Living Room", model: "AppleTV14,1", address: "A4:83:E7:2C:91:0D",
            uuid: "7B1E4C2A-5D3F-4E8B-9A6C-1F2D3E4A5B6C", pairingDisabled: true)
        static let bedroom = device(
            name: "Bedroom", model: "AppleTV11,1", address: "A4:83:E7:58:C3:7E",
            uuid: "C9D8E7F6-A5B4-4C3D-8E2F-1A0B9C8D7E6F")
        static let office = device(
            name: "Office", model: "AppleTV6,2", address: "A4:83:E7:B1:04:A2",
            uuid: "3F2E1D0C-9B8A-4756-8341-2A1B0C9D8E7F")

        /// Apple TVs on the "network".
        var onlineDevices: [AppleTVDevice] {
            switch self {
            case .searching: return []
            case .offline: return [Self.bedroom, Self.office]
            case .pairingdisabled: return [Self.livingRoomPairingDisabled, Self.bedroom, Self.office]
            default: return [Self.livingRoom, Self.bedroom, Self.office]
            }
        }

        /// Apple TVs already paired at launch. Office is never paired, so the
        /// device list always shows a Pair badge.
        var pairedDevices: [AppleTVDevice] {
            switch self {
            case .searching: return []
            case .pair, .pin, .pairingdisabled, .reset, .removed, .pairingfailed: return [Self.bedroom]
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
            case .pairingfailed: return .failed(TLV8.ErrorCode.authentication.message)
            default: return .idle
            }
        }

        /// Orange caption on the pair card, as after a stale pairing was dropped.
        var pairingNotice: String? {
            switch self {
            case .reset: return CompanionError.identityChanged.localizedDescription
            case .removed: return CompanionError.pairingLost.localizedDescription
            default: return nil
            }
        }

        /// State the stand-in connection lands in.
        var connectionState: ConnectionState {
            switch self {
            case .connectionfailed: return .failed(CompanionError.connectionFailed("demo").localizedDescription)
            case .disconnected: return .disconnected
            default: return .connected
            }
        }

        /// What the TV reports it can control; HDMI output has no absolute volume.
        var mediaControlFlags: MediaControlFlags {
            self == .hdmi ? [.play, .pause] : [.play, .pause, .volume]
        }

        /// Inline notice under the device picker while connected.
        var actionError: String? {
            self == .hdmi ? RemoteController.muteUnavailableMessage : nil
        }

        /// Version shown as a pending update.
        var pendingUpdateVersion: String? {
            self == .update ? "1.1.0" : nil
        }

        var screen: PanelScreen { self == .settings ? .settings : .remote }

        var powerState: PowerState { self == .asleep ? .asleep : .awake }

        var keyboardSession: TextInputArchive.Session? {
            guard self == .typing else { return nil }
            return TextInputArchive.Session(sessionUUID: UUID(), currentText: "Nature documentaries")
        }

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

        /// Recently launched apps shown at the top of the picker.
        static let recentAppIDs = ["com.netflix.Netflix", "com.apple.TVWatchList", "com.google.ios.youtube"]

        /// Starred apps pinned above the recents in the picker.
        static let favoriteAppIDs = ["com.plexapp.plex", "com.apple.TVMusic"]

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

        /// Demo devices have no endpoint, so they are marked online by hand. The
        /// TXT record is made up so the picker's ⌥-click details have something
        /// to show.
        private static func device(
            name: String, model: String, address: String, uuid: String, pairingDisabled: Bool = false
        ) -> AppleTVDevice {
            let txt: [String: String] = [
                "rpMRtID": uuid,
                "rpBA": address,
                "rpVr": "550.1",
                "rpFl": "0x36782",
                "rpMd": model,
            ]
            var device = AppleTVDevice(
                id: "demo-\(name.lowercased().replacingOccurrences(of: " ", with: "-"))",
                name: name,
                model: model,
                endpoint: nil,
                pairingDisabled: pairingDisabled,
                flags: 0x36782,
                txtRecord: txt,
                interfaces: ["en0 (Wi‑Fi)"]
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
#endif
