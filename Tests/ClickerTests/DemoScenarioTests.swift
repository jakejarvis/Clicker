import ClickerCompanion
import Foundation
import Testing

@testable import ClickerApp
@testable import ClickerDemo

/// Every `--demo` scenario reaches its state through the controller's real
/// code paths, against made-up Apple TVs.
@Suite @MainActor struct DemoScenarioTests {
    @Test func parsesLaunchArguments() throws {
        #expect(DemoScenario.parse(["Clicker"]) == nil)
        #expect(try DemoScenario.parse(["Clicker", "--demo"])?.get().name == "ready")
        #expect(try DemoScenario.parse(["Clicker", "--demo", "--regular"])?.get().name == "ready")
        #expect(try DemoScenario.parse(["Clicker", "--demo", "pin"])?.get().name == "pin")
        #expect(try DemoScenario.parse(["Clicker", "--demo", "Offline"])?.get().name == "offline")
        guard case .failure(let error)? = DemoScenario.parse(["Clicker", "--demo", "nonsense"]) else {
            Issue.record("an unknown name should be an error")
            return
        }
        #expect(error.name == "nonsense")
    }

    @Test func scenarioNamesAreUnique() {
        let names = DemoScenario.all.map(\.name)
        #expect(Set(names).count == names.count)
    }

    @Test func readyConnectsToLivingRoom() async throws {
        let run = try await DemoRun("ready")
        let controller = run.controller
        #expect(await run.connected())
        #expect(controller.selectedDevice?.name == "Living Room")
        #expect(controller.selectedStateDescription == "Ready")
        #expect(controller.apps == DemoScenario.apps)
        #expect(controller.connectionInfo?.addressDescription == "192.168.1.42:49153")
        #expect(controller.devices.map(\.name) == ["Bedroom", "Living Room", "Office"])
        #expect(controller.devices.first { $0.name == "Office" }.map(controller.isPaired) == false)
    }

    @Test(arguments: [("asleep", "Asleep"), ("offline", "Offline"), ("pair", "Not paired"), ("pin", "Not paired")])
    func scenariosDescribeTheirState(_ name: String, description: String) async throws {
        let run = try await DemoRun(name)
        #expect(await eventually { run.controller.selectedStateDescription == description })
    }

    @Test func typingMirrorsTheTVField() async throws {
        let run = try await DemoRun("typing")
        #expect(await run.connected())
        #expect(run.controller.keyboardSession != nil)
        #expect(run.controller.tvText == "Nature documentaries")
        #expect(run.controller.isTextFieldShown)
    }

    @Test func screenAndPopoverScenariosOpenThem() async throws {
        #expect(try await DemoRun("settings").controller.screen == .settings)
        let apps = try await DemoRun("apps").controller
        #expect(apps.isAppPickerPresented)
        #expect(!apps.apps.isEmpty)
        #expect(try await DemoRun("devices").controller.devicePickerPresentation?.showsDetails == false)
    }

    @Test func pinWaitsForTheCode() async throws {
        let run = try await DemoRun("pin")
        #expect(await eventually { run.controller.pairingState == .awaitingPIN })
    }

    @Test func pairedHoldsTheCheckOnceConnected() async throws {
        let run = try await DemoRun("paired")
        #expect(await eventually { run.controller.pairingState == .succeeded })
        #expect(await run.connected())
        #expect(run.controller.selectedDevice.map(run.controller.isPaired) == true)
    }

    @Test func pairingDisabledRefusesToPair() async throws {
        let run = try await DemoRun("pairingdisabled")
        let controller = run.controller
        #expect(controller.selectedDevice?.pairingDisabled == true)
        #expect(controller.selectedStateDescription == "Not paired")
        controller.beginPairing()
        #expect(controller.pairingState == .failed(CompanionError.pairingDisabled.localizedDescription))
    }

    @Test(arguments: [("reset", CompanionError.identityChanged), ("removed", .pairingLost)])
    func stalePairingsAreDroppedWithANotice(_ name: String, reason: CompanionError) async throws {
        let run = try await DemoRun(name)
        let controller = run.controller
        #expect(await eventually { controller.pairingNotice == reason.localizedDescription })
        #expect(controller.selectedStateDescription == "Not paired")
        #expect(controller.recentAppIDsByDevice[DemoTV.livingRoom.id] == nil)
    }

    @Test func pairingAResetTVAgainConnects() async throws {
        let controller = try await DemoRun("reset") { $0.timings.pairingSuccessHold = .zero }.controller
        #expect(await eventually { controller.selectedStateDescription == "Not paired" })
        controller.beginPairing()
        #expect(await eventually { controller.pairingState == .awaitingPIN })
        controller.submitPIN("1234")
        #expect(await eventually { controller.connectionState == .connected })
        #expect(controller.pairingNotice == nil)
    }

    /// A timed-out pair-setup asks about the local network too.
    @Test func aDeniedLocalNetworkBlocksPairing() async throws {
        let controller = try await DemoRun("pairinglocalnetwork").controller
        #expect(await eventually { controller.pairingState == .localNetworkDenied })

        let allowed = try await DemoRun("pairinglocalnetwork") { $0.localNetworkDenied = false }.controller
        #expect(await eventually { allowed.pairingState == .failed(CompanionError.timeout.localizedDescription) })
    }

    @Test func aWrongCodeFailsThePairing() async throws {
        let run = try await DemoRun("pairingfailed")
        #expect(await eventually { run.controller.pairingState == .failed(TLV8.ErrorCode.authentication.message) })
        #expect(run.controller.selectedStateDescription == "Not paired")
    }

    @Test func aRefusedSaveFailsThePairing() async throws {
        let run = try await DemoRun("savefailed")
        let controller = run.controller
        #expect(
            await eventually {
                if case .failed(let message) = controller.pairingState {
                    return message.hasPrefix("Paired, but the pairing couldn't be saved: ")
                }
                return false
            })
        #expect(controller.selectedStateDescription == "Not paired")
    }

    @Test func aFailedConnectNamesTheTV() async throws {
        let run = try await DemoRun("connectionfailed")
        #expect(await eventually { run.controller.connectionState == .failed("Couldn't connect to Living Room.") })
        #expect(run.controller.selectedStateDescription == "Connection failed")
    }

    @Test func connectingHoldsWhileTheTVIsSilent() async throws {
        let controller = try await DemoRun("connecting").controller
        #expect(await eventually { controller.connectionState == .connecting })
        try await Task.sleep(for: .milliseconds(100))
        #expect(controller.selectedStateDescription == "Connecting…")
    }

    /// A timed-out connect asks about the local network and, denied, skips
    /// the retry.
    @Test func aDeniedLocalNetworkIsNamed() async throws {
        let controller = try await DemoRun("localnetwork").controller
        #expect(await eventually { controller.connectionState == .localNetworkDenied })
        #expect(controller.selectedStateDescription == "No local network access")
    }

    @Test func aTimeoutWithTheLocalNetworkAllowedRetriesThenFails() async throws {
        let controller = try await DemoRun("localnetwork") { $0.localNetworkDenied = false }.controller
        #expect(await eventually { controller.connectionState == .failed("Couldn't connect to Living Room.") })
    }

    @Test func aDroppedSessionWaitsToReconnect() async throws {
        let run = try await DemoRun("disconnected")
        #expect(await eventually { run.controller.connectionState == .disconnected })
        #expect(run.controller.selectedStateDescription == "Not connected")
    }

    /// A press the TV leaves unanswered drops the session, and the presses
    /// queued behind it go too rather than replay on the next session.
    @Test func anUnansweredPressDropsTheSessionAndTheQueue() async throws {
        let run = try await DemoRun("unresponsive") {
            $0.livingRoom.inputTimeout = .milliseconds(100)
            $0.steps = []
        }
        let controller = run.controller
        #expect(await run.connected())
        controller.buttonDown(.down)
        controller.buttonUp(.down)
        controller.press(.up)
        #expect(await eventually { controller.connectionState == .disconnected })
        #expect(controller.lastActionError == CompanionError.timeout.localizedDescription)

        // With the panel hidden nothing reconnects until the next press,
        // which a fresh session answers.
        controller.press(.select)
        #expect(await eventually { controller.connectionState == .connected && controller.lastActionError == nil })
        #expect(run.world.sessions.count == 2)
        #expect(await run.world.sessions[0].buttons == [.down(.down)])
        #expect(await run.world.sessions[1].buttons == [.press(.select)])
    }

    @Test func anUnansweredPressReconnectsWhileThePanelIsOpen() async throws {
        let run = try await DemoRun("unresponsive") {
            $0.livingRoom.inputTimeout = .milliseconds(100)
            $0.timings.reconnectDelay = .zero
            $0.steps = []
        }
        let controller = run.controller
        controller.panelDidAppear()
        #expect(await run.connected())
        controller.press(.select)
        controller.press(.down)
        #expect(await eventually { run.world.sessions.count == 2 && controller.connectionState == .connected })
        #expect(await run.world.sessions[0].buttons == [.press(.select)])
        #expect(await run.world.sessions[1].buttons.isEmpty)
    }

    @Test func anUnansweredTouchDropsTheSession() async throws {
        let run = try await DemoRun("unresponsive") {
            $0.livingRoom.inputTimeout = .milliseconds(100)
            $0.steps = []
        }
        let controller = run.controller
        #expect(await run.connected())
        controller.handleTrackpadSwipe(.touchDown(CGPoint(x: 500, y: 500)))
        controller.handleTrackpadSwipe(.touchUp(CGPoint(x: 500, y: 800)))
        #expect(await eventually { controller.connectionState == .disconnected })
    }

    @Test func hdmiWithholdsMuteAfterItDoesNothing() async throws {
        let run = try await DemoRun("hdmi")
        let controller = run.controller
        #expect(await eventually { controller.lastActionError == RemoteController.muteUnavailableMessage })
        #expect(controller.connectionState == .connected)
        #expect(controller.canMute == false)
        #expect(controller.isMuted == false)
    }

    @Test func emptyScenariosSelectNothing() async throws {
        let searching = try await DemoRun("searching").controller
        #expect(searching.devices.isEmpty)
        #expect(searching.selectedDevice == nil)

        let choose = try await DemoRun("choose").controller
        #expect(choose.devices.map(\.name) == ["Bedroom", "Living Room"])
        #expect(choose.selectedDevice == nil)
    }

    /// Forgetting the selected offline TV moves on to a usable one at once.
    @Test func forgettingTheSelectedOfflineDeviceReselects() async throws {
        let controller = try await DemoRun("offline").controller
        #expect(controller.selectedDevice?.name == "Living Room")
        #expect(controller.selectedDevice?.isOnline == false)
        controller.forgetPairing(for: controller.selectedDevice!)
        #expect(controller.selectedDevice?.name == "Bedroom")
        #expect(await eventually { controller.connectionState == .connected })
    }

    @Test func pairingThenConnects() async throws {
        let controller = try await DemoRun("pair") { $0.timings.pairingSuccessHold = .zero }.controller
        controller.beginPairing()
        #expect(controller.pairingState == .starting)
        #expect(await eventually { controller.pairingState == .awaitingPIN })
        controller.submitPIN("1234")
        #expect(controller.pairingState == .finishing)
        #expect(await eventually { controller.pairingState == .idle && controller.connectionState == .connected })
    }

    @Test func aShortCodeIsRejectedBeforeReachingTheTV() async throws {
        let controller = try await DemoRun("pin").controller
        #expect(await eventually { controller.pairingState == .awaitingPIN })
        controller.submitPIN("12")
        #expect(controller.pairingState == .failed("Enter the four-digit code shown on the Apple TV."))
    }

    @Test func choicesAreRememberedForTheNextLaunch() async throws {
        let run = try await DemoRun("ready")
        let controller = run.controller
        #expect(await run.connected())
        #expect(run.settings.lastAddressByDevice[DemoTV.livingRoom.id] == "192.168.1.42")
        let bedroom = try #require(controller.devices.first { $0.name == "Bedroom" })
        controller.select(bedroom)
        #expect(run.settings.selectedDeviceID == bedroom.id)
        // The address and apps arrive a few hops after the state flips.
        #expect(await run.connected())
        #expect(controller.connectionInfo?.addressDescription == "192.168.1.43:49153")
        let netflix = try #require(controller.apps.first { $0.name == "Netflix" })
        controller.launch(netflix)
        #expect(run.settings.recentAppIDsByDevice[bedroom.id] == ["com.netflix.Netflix"])
    }
}
