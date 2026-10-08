import Foundation
import Network
import Testing

@testable import Clicker

@Suite struct DevicePickerOrderTests {
    private static func device(_ name: String, online: Bool) -> AppleTVDevice {
        AppleTVDevice(
            id: name, name: name, model: "AppleTV14,1",
            endpoint: online ? .hostPort(host: "192.168.1.10", port: 49152) : nil,
            pairingDisabled: false)
    }

    @Test func usableDevicesComeFirst() {
        let paired: Set<String> = ["Bedroom", "attic", "Living Room"]
        let devices = [
            Self.device("Office", online: true),  // unpaired
            Self.device("Living Room", online: false),  // paired, offline
            Self.device("Den", online: true),  // unpaired
            Self.device("Bedroom", online: true),  // paired, online
            Self.device("attic", online: true),  // paired, online; lowercase sorts by name, not case
        ]
        let order = RemoteController.pickerOrder(devices) { paired.contains($0.id) }
        #expect(order.map(\.name) == ["attic", "Bedroom", "Living Room", "Den", "Office"])
    }
}
