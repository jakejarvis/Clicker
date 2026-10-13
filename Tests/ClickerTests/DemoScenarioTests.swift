import ClickerCompanion
import Foundation
import Testing

@testable import Clicker

#if DEMO
    @Suite struct DemoScenarioTests {
        @Test func parsesLaunchArguments() {
            #expect(DemoScenario.parse(["Clicker"]) == nil)
            #expect(DemoScenario.parse(["Clicker", "--demo"]) == .ready)
            #expect(DemoScenario.parse(["Clicker", "--demo", "--regular"]) == .ready)
            #expect(DemoScenario.parse(["Clicker", "--demo", "pin"]) == .pin)
            #expect(DemoScenario.parse(["Clicker", "--demo", "Offline"]) == .offline)
            #expect(DemoScenario.parse(["Clicker", "--demo", "nonsense"]) == .ready)
        }

        @Test @MainActor func readyScenarioConnectsWithoutANetwork() {
            let controller = RemoteController(demo: .ready)
            controller.start()
            #expect(controller.connectionState == .connected)
            #expect(controller.selectedDevice?.name == "Living Room")
            #expect(controller.selectedStateDescription == "Ready")
            #expect(controller.apps == DemoScenario.apps)
            #expect(controller.devices.map(\.name) == ["Bedroom", "Living Room", "Office"])
            #expect(controller.devices.first { $0.name == "Office" }.map(controller.isPaired) == false)
        }

        @Test(arguments: [
            (DemoScenario.asleep, "Asleep"), (.offline, "Offline"), (.pair, "Not paired"), (.pin, "Not paired"),
        ])
        @MainActor func scenariosDescribeTheirState(_ scenario: DemoScenario, description: String) {
            let controller = RemoteController(demo: scenario)
            controller.start()
            #expect(controller.selectedStateDescription == description)
        }

        @Test @MainActor func typingScenarioMirrorsTheTVField() {
            let typing = RemoteController(demo: .typing)
            typing.start()
            #expect(typing.keyboardSession != nil)
            #expect(typing.tvText == "Nature documentaries")
        }

        @Test @MainActor func troubleScenariosShowTheirNotices() {
            let disabled = RemoteController(demo: .pairingdisabled)
            disabled.start()
            #expect(disabled.selectedDevice?.pairingDisabled == true)
            #expect(disabled.selectedStateDescription == "Not paired")

            let reset = RemoteController(demo: .reset)
            reset.start()
            #expect(reset.pairingNotice == CompanionError.identityChanged.localizedDescription)

            let removed = RemoteController(demo: .removed)
            removed.start()
            #expect(removed.pairingNotice == CompanionError.pairingLost.localizedDescription)
            #expect(removed.selectedStateDescription == "Not paired")

            let wrongCode = RemoteController(demo: .pairingfailed)
            wrongCode.start()
            #expect(wrongCode.pairingState == .failed(TLV8.ErrorCode.authentication.message))

            let notSaved = RemoteController(demo: .savefailed)
            notSaved.start()
            #expect(notSaved.selectedStateDescription == "Not paired")
            guard case .failed(let message) = notSaved.pairingState else {
                Issue.record("savefailed should show a failed pair card")
                return
            }
            #expect(message.hasPrefix("Paired, but the pairing couldn't be saved: "))

            let failed = RemoteController(demo: .connectionfailed)
            failed.start()
            #expect(failed.selectedStateDescription == "Connection failed")

            let disconnected = RemoteController(demo: .disconnected)
            disconnected.start()
            #expect(disconnected.connectionState == .disconnected)

            let hdmi = RemoteController(demo: .hdmi)
            hdmi.start()
            #expect(hdmi.connectionState == .connected)
            #expect(hdmi.canMute == false)
            #expect(hdmi.lastActionError == RemoteController.muteUnavailableMessage)
        }

        @Test @MainActor func emptyScenariosSelectNothing() {
            let searching = RemoteController(demo: .searching)
            searching.start()
            #expect(searching.devices.isEmpty)
            #expect(searching.selectedDevice == nil)

            let choose = RemoteController(demo: .choose)
            choose.start()
            #expect(choose.devices.count == 3)
            #expect(choose.selectedDevice == nil)
        }

        /// Forgetting the selected offline TV moves on to a usable one at once.
        @Test @MainActor func forgettingTheSelectedOfflineDeviceReselects() {
            let controller = RemoteController(demo: .offline)
            controller.start()
            #expect(controller.selectedDevice?.name == "Living Room")
            #expect(controller.selectedDevice?.isOnline == false)
            controller.forgetPairing(for: controller.selectedDevice!)
            #expect(controller.selectedDevice?.name == "Bedroom")
            #expect(controller.connectionState == .connected)
        }

        @Test @MainActor func pairingCompletesWithAnyCode() async throws {
            let controller = RemoteController(demo: .pair)
            controller.start()
            controller.beginPairing()
            #expect(controller.pairingState == .starting)
            try await Task.sleep(for: .seconds(1.2))
            #expect(controller.pairingState == .awaitingPIN)
            controller.submitPIN("1234")
            try await Task.sleep(for: .seconds(1.2))
            #expect(controller.pairingState == .succeeded)
            #expect(controller.connectionState == .connected)
        }
    }
#endif
