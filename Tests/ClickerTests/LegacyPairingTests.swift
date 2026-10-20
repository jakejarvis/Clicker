import ClickerCompanion
import Foundation
import Network
import Testing

@testable import ClickerApp

@Suite struct LegacyPairingTests {
    private static let livingRoom = AppleTVDevice(
        id: "6F1C2A4E-0B7D-4C1A-9E3F-2D5B8A7C6E10", name: "Living Room", model: "AppleTV14,1",
        endpoint: .hostPort(host: "192.168.1.10", port: 49152), pairingDisabled: false)

    private static func pairing(id: String, name: String = "Living Room") -> PairingCredentials {
        PairingCredentials(
            deviceID: id, deviceName: name, deviceModel: "AppleTV14,1", accessoryIdentifier: Data([1, 2, 3]),
            accessoryPublicKey: Data(repeating: 0xAB, count: 32), clientIdentifier: UUID().uuidString,
            clientPrivateKey: Data(repeating: 0xCD, count: 32), pairedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    /// A pairing saved under the old rotating `rpBA` key moves to the TV's UUID.
    @Test func adoptsRotatingAddressKey() {
        let legacy = Self.pairing(id: "A1:B2:C3:D4:E5:F6")
        let found = RemoteController.legacyPairing(
            for: Self.livingRoom, in: [legacy], onlineIDs: [Self.livingRoom.id])
        #expect(found == legacy)
    }

    /// Another home's TV with the same name and model is a different Apple TV, not a renamed key.
    @Test func leavesSameNamedTVAlone() {
        let otherHome = Self.pairing(id: "0D9E8F7A-6B5C-4D3E-8F2A-1B0C9D8E7F65")
        let found = RemoteController.legacyPairing(
            for: Self.livingRoom, in: [otherHome], onlineIDs: [Self.livingRoom.id])
        #expect(found == nil)
    }

    @Test func leavesOnlineAndOtherNamesAlone() {
        let online = Self.pairing(id: "A1:B2:C3:D4:E5:F6")
        let bedroom = Self.pairing(id: "11:22:33:44:55:66", name: "Bedroom")
        let found = RemoteController.legacyPairing(
            for: Self.livingRoom, in: [online, bedroom], onlineIDs: [Self.livingRoom.id, online.deviceID])
        #expect(found == nil)
    }
}
