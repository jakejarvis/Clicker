import ClickerApp
import ClickerCompanion
import Foundation
import Network

/// One of the made-up Apple TVs: what it advertises over "Bonjour" and how it
/// answers once Clicker talks to it.
nonisolated struct DemoTV: Sendable {
    var name: String
    var model: String
    var host: String
    var bluetoothAddress: String
    var uuid: String
    /// Pairing turned off under Remotes and Devices (`rpFl` bit 0x04).
    var pairingDisabled = false
    var power: PowerState = .awake
    /// What the current audio output lets Clicker control. HDMI also claims
    /// volume and then ignores SetVolume; see `echoesVolume`.
    var mediaControls: MediaControlFlags = [.play, .pause, .volume]
    /// False for HDMI output: SetVolume is answered but changes nothing and
    /// sends no `_iMC`, so Mute is undone and withheld.
    var echoesVolume = true
    /// Text in a field focused on the TV, if any.
    var focusedText: String?
    /// Thrown by connect (after pair-verify, for the stale-pairing errors)
    /// with the pairing the scenario starts with; nil connects. A pairing
    /// made during the run always connects, as it would with a real TV.
    var connectError: CompanionError?
    /// False answers any code as the TV does a wrong one.
    var acceptsCode = true
    /// Thrown by pair-setup's start, before a code shows; nil shows one.
    var pairingStartError: CompanionError?
    /// False leaves a connect waiting. Unlike a real session it never times
    /// out, so the Connecting… state holds for a screenshot.
    var answersConnect = true
    /// Set, presses and touches go unanswered and time out after this long,
    /// as a session that has stopped answering does. Only the session open
    /// at launch: one opened later answers, as a real TV's fresh one did.
    var inputTimeout: Duration?

    static let livingRoom = DemoTV(
        name: "Living Room", model: "AppleTV14,1", host: "192.168.1.42", bluetoothAddress: "A4:83:E7:2C:91:0D",
        uuid: "7B1E4C2A-5D3F-4E8B-9A6C-1F2D3E4A5B6C")
    static let bedroom = DemoTV(
        name: "Bedroom", model: "AppleTV11,1", host: "192.168.1.43", bluetoothAddress: "A4:83:E7:58:C3:7E",
        uuid: "C9D8E7F6-A5B4-4C3D-8E2F-1A0B9C8D7E6F")
    static let office = DemoTV(
        name: "Office", model: "AppleTV6,2", host: "192.168.1.44", bluetoothAddress: "A4:83:E7:B1:04:A2",
        uuid: "3F2E1D0C-9B8A-4756-8341-2A1B0C9D8E7F")

    static let port: UInt16 = 49153

    var endpoint: NWEndpoint {
        .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: Self.port)!)
    }

    /// The device as discovery reports it, parsed from a made-up TXT record
    /// by the same code that parses a real one.
    var device: AppleTVDevice {
        let txt = [
            "rpMRtID": uuid,
            "rpBA": bluetoothAddress,
            "rpVr": "550.1",
            "rpFl": pairingDisabled ? "0x36786" : "0x36782",
            "rpMd": model,
        ]
        return AppleTVDevice(name: name, txt: txt, endpoint: endpoint, interfaces: ["en0 (Wi‑Fi)"])!
    }

    var id: String { device.id }

    /// Placeholder keys; nothing ever verifies them. `pairedAt` tells a
    /// pairing from before launch (`.distantPast`) from one made since.
    func credentials(pairedAt: Date) -> PairingCredentials {
        PairingCredentials(
            deviceID: id,
            deviceName: name,
            deviceModel: model,
            accessoryIdentifier: Data(),
            accessoryPublicKey: Data(),
            clientIdentifier: "demo",
            clientPrivateKey: Data(),
            pairedAt: pairedAt
        )
    }
}
