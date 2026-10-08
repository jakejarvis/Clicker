import Foundation
import Network
import Testing

@testable import Clicker

@Suite struct AppleTVDeviceTests {
    private let endpoint = NWEndpoint.service(
        name: "Living Room", type: "_companion-link._tcp", domain: "local.", interface: nil)

    private func makeDevice(
        name: String = "Living Room",
        txt: [String: String],
        interfaces: [String] = ["en0 (Wi‑Fi)"]
    ) -> AppleTVDevice? {
        AppleTVDevice(name: name, txt: txt, endpoint: endpoint, interfaces: interfaces)
    }

    @Test func rejectsDevicesThatAreNotAppleTVs() {
        #expect(makeDevice(txt: ["rpMd": "MacBookPro18,3"]) == nil)
        #expect(makeDevice(txt: ["rpBA": "AA:BB"]) == nil)
        #expect(makeDevice(txt: ["rpMd": "AppleTV14,1"]) != nil)
    }

    @Test func parsesFlagsWithAndWithoutPrefix() {
        let prefixed = makeDevice(txt: ["rpMd": "AppleTV14,1", "rpFl": "0x4004"])
        #expect(prefixed?.flags == 0x4004)
        #expect(prefixed?.pairingDisabled == true)
        #expect(prefixed?.flagDescriptions == ["Pairing disabled", "PIN pairing"])
        #expect(prefixed?.flagsHex == "0x4004")

        let bare = makeDevice(txt: ["rpMd": "AppleTV14,1", "rpFl": "36782"])
        #expect(bare?.flags == 0x36782)
        #expect(bare?.pairingDisabled == false)
        #expect(bare?.flagDescriptions == ["PIN pairing"])

        let garbage = makeDevice(txt: ["rpMd": "AppleTV14,1", "rpFl": "zz"])
        #expect(garbage?.flags == 0)
    }

    @Test func prefersStableIdentifierOverAddressOverName() {
        let full = makeDevice(txt: [
            "rpMd": "AppleTV14,1", "rpMRtID": "abcdef01-0000-0000-0000-000000000001", "rpBA": "AA:BB",
        ])
        #expect(full?.id == "ABCDEF01-0000-0000-0000-000000000001")
        #expect(makeDevice(txt: ["rpMd": "AppleTV14,1", "rpBA": "AA:BB"])?.id == "AA:BB")
        #expect(makeDevice(txt: ["rpMd": "AppleTV14,1"])?.id == "Living Room")
    }

    @Test func readsTXTValuesCaseInsensitively() throws {
        let device = try #require(
            makeDevice(txt: ["RPMD": "AppleTV11,1", "rpba": "AA:BB:CC:DD:EE:FF", "RpVr": "550.1"])
        )
        #expect(device.model == "AppleTV11,1")
        #expect(device.bluetoothAddress == "AA:BB:CC:DD:EE:FF")
        #expect(device.companionVersion == "550.1")
        #expect(device.txt("rpvr") == "550.1")
        #expect(device.txt("missing") == nil)
        #expect(device.txtRecord["RpVr"] == "550.1", "the record keeps its original keys")
        #expect(device.isOnline)
    }

    @Test func sortsAndDeduplicatesInterfaces() throws {
        let device = try #require(
            makeDevice(txt: ["rpMd": "AppleTV14,1"], interfaces: ["en1 (Ethernet)", "en0 (Wi‑Fi)", "en0 (Wi‑Fi)"])
        )
        #expect(device.interfaces == ["en0 (Wi‑Fi)", "en1 (Ethernet)"])
    }

    @Test @MainActor func mergeUnionsInterfacesAndSortsByName() throws {
        let office = try #require(
            makeDevice(name: "office", txt: ["rpMd": "AppleTV6,2", "rpMRtID": "B"], interfaces: ["en1 (Ethernet)"]))
        let bedroomWiFi = try #require(
            makeDevice(name: "Bedroom", txt: ["rpMd": "AppleTV14,1", "rpMRtID": "A"], interfaces: ["en0 (Wi‑Fi)"]))
        let bedroomWired = try #require(
            makeDevice(name: "Bedroom", txt: ["rpMd": "AppleTV14,1", "rpMRtID": "A"], interfaces: ["en1 (Ethernet)"]))

        let merged = DeviceBrowser.merge([office, bedroomWiFi, bedroomWired])
        #expect(merged.map(\.name) == ["Bedroom", "office"])
        #expect(merged.first?.interfaces == ["en0 (Wi‑Fi)", "en1 (Ethernet)"])
        #expect(merged.last?.interfaces == ["en1 (Ethernet)"])
    }

    @Test func connectionInfoFormatsEndpoints() {
        let v4 = ConnectionInfo(endpoint: .hostPort(host: "192.168.20.50", port: 49153), sessionID: 0x5C1A_7E2B)
        #expect(v4?.addressDescription == "192.168.20.50:49153")
        #expect(v4?.sessionDescription == "0x5C1A7E2B")

        let v6 = ConnectionInfo(endpoint: .hostPort(host: "fe80::1%en0", port: 7000), sessionID: 1)
        #expect(v6?.addressDescription == "[fe80::1]:7000")

        #expect(ConnectionInfo(endpoint: nil, sessionID: 1) == nil)
    }
}
