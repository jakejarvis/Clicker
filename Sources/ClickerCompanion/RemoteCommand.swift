import Foundation

/// Button identifiers for the Companion `_hidC` command.
package enum HIDCommand: Int64, CaseIterable, Sendable {
    case up = 1
    case down = 2
    case left = 3
    case right = 4
    case menu = 5
    case select = 6
    case home = 7
    case volumeUp = 8
    case volumeDown = 9
    case siri = 10
    case screensaver = 11
    case sleep = 12
    case wake = 13
    case playPause = 14
    case channelIncrement = 15
    case channelDecrement = 16
    case guide = 17
    case pageUp = 18
    case pageDown = 19
}

package struct AppleTVApp: Identifiable, Hashable, Sendable {
    package let bundleIdentifier: String
    package let name: String

    package var id: String { bundleIdentifier }

    package init(bundleIdentifier: String, name: String) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }
}

/// A tvOS user profile, from `FetchUserAccountsEvent`.
package struct UserAccount: Identifiable, Hashable, Sendable {
    package let id: String
    package let name: String

    package init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// The `_tPh` phase of a `_hidT` touch event, numbered as pyatv's `TouchAction`.
package enum TouchPhase: Int64, Sendable {
    case press = 1
    case hold = 3
    case release = 4
    case click = 5
}

/// Mirrors the `state` field of `TVSystemStatus` events.
package enum PowerState: Int64, Sendable {
    case unknown = 0
    case asleep = 1
    case screensaver = 2
    case awake = 3
    case idle = 4

    package var isOn: Bool? {
        switch self {
        case .unknown: return nil
        case .asleep: return false
        case .screensaver, .awake, .idle: return true
        }
    }
}

/// The `_mcF` bits of an `_iMC` event: which media controls the TV's current
/// output accepts. Bit values follow pyatv's `MediaControlFlags`. `volume` is
/// set only when the Apple TV owns an absolute level (HomePod, AirPlay or
/// Bluetooth output); over HDMI the volume buttons still work as CEC or IR
/// presses, but `_mcc` GetVolume/SetVolume have nothing to act on.
package struct MediaControlFlags: OptionSet, Sendable, Hashable {
    package let rawValue: Int64

    package static let play = MediaControlFlags(rawValue: 0x0001)
    package static let pause = MediaControlFlags(rawValue: 0x0002)
    package static let nextTrack = MediaControlFlags(rawValue: 0x0004)
    package static let previousTrack = MediaControlFlags(rawValue: 0x0008)
    package static let fastForward = MediaControlFlags(rawValue: 0x0010)
    package static let rewind = MediaControlFlags(rawValue: 0x0020)
    package static let volume = MediaControlFlags(rawValue: 0x0100)
    package static let skipForward = MediaControlFlags(rawValue: 0x0200)
    package static let skipBackward = MediaControlFlags(rawValue: 0x0400)

    /// Flags carried by an `_iMC` event's content, or nil when it has none.
    package init?(eventContent: OPACKValue) {
        guard let raw = eventContent["_mcF"]?.intValue else { return nil }
        self.init(rawValue: raw)
    }

    package init(rawValue: Int64) {
        self.rawValue = rawValue
    }

    /// Names of the known set bits, for the device details view.
    package var descriptions: [String] {
        let known: [(MediaControlFlags, String)] = [
            (.play, "play"), (.pause, "pause"), (.nextTrack, "next"), (.previousTrack, "previous"),
            (.fastForward, "fast forward"), (.rewind, "rewind"), (.volume, "volume"),
            (.skipForward, "skip forward"), (.skipBackward, "skip backward"),
        ]
        return known.filter { contains($0.0) }.map(\.1)
    }
}

/// How this Mac introduces itself to the Apple TV.
package struct ClientIdentity: Sendable {
    /// Shown on the Apple TV under Remotes and Devices.
    package var name: String
    /// MAC-style identifier sent in `_systemInfo`; generated once per install.
    package var deviceID: String

    package init(name: String, deviceID: String) {
        self.name = name
        self.deviceID = deviceID
    }
}
