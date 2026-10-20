import ClickerCompanion
import Foundation
import Testing

@testable import ClickerApp
@testable import ClickerDemo

@Suite struct MediaControlFlagsTests {
    @Test func parsesTheFlagsOfAnInterestEvent() {
        let content: OPACKValue = .dictionary(["_mcF": .int(0x103)])
        let flags = MediaControlFlags(eventContent: content)
        #expect(flags == [.play, .pause, .volume])
        #expect(flags?.descriptions == ["play", "pause", "volume"])
    }

    @Test func eventWithoutFlagsParsesToNil() {
        #expect(MediaControlFlags(eventContent: .dictionary([String: OPACKValue]())) == nil)
        #expect(MediaControlFlags(eventContent: .null) == nil)
    }

    @Test func hdmiOutputHasNoVolumeControl() {
        let flags = MediaControlFlags(eventContent: .dictionary(["_mcF": .int(0x3)]))
        #expect(flags?.contains(.volume) == false)
    }

    @Test @MainActor func muteIsWithheldUntilTheTVReportsVolumeControl() async throws {
        let run = try await DemoRun("ready")
        #expect(run.controller.canMute == false)
        #expect(await eventually { run.controller.canMute })
    }

    @Test @MainActor func aConfirmedMuteStays() async throws {
        let run = try await DemoRun("ready") { $0.timings.muteConfirmationTimeout = .milliseconds(50) }
        let controller = run.controller
        #expect(await run.connected())
        controller.toggleMute()
        #expect(controller.isMuted)
        try await Task.sleep(for: .milliseconds(200))
        #expect(controller.isMuted)
        #expect(controller.canMute)
        #expect(controller.lastActionError == nil)
    }

    @Test @MainActor func anUnconfirmedMuteIsUndoneAndWithheld() async throws {
        let run = try await DemoRun("ready") {
            $0.livingRoom.echoesVolume = false
            $0.timings.muteConfirmationTimeout = .milliseconds(50)
        }
        let controller = run.controller
        #expect(await run.connected())
        controller.toggleMute()
        #expect(controller.isMuted)
        #expect(await eventually { controller.lastActionError == RemoteController.muteUnavailableMessage })
        #expect(controller.isMuted == false)
        #expect(controller.canMute == false)
    }
}
