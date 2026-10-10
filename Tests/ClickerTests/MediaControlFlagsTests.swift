import Foundation
import Testing

@testable import Clicker

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

    #if DEMO
        @Test @MainActor func muteIsWithheldUntilTheTVReportsVolumeControl() {
            let controller = RemoteController(demo: .ready)
            #expect(controller.canMute == false)
            controller.start()
            #expect(controller.canMute)
        }

        @Test @MainActor func anUnconfirmedMuteIsUndoneAndWithheld() {
            let controller = RemoteController(demo: .ready)
            controller.start()
            controller.toggleMute()
            #expect(controller.isMuted)
            controller.abandonMute()
            #expect(controller.isMuted == false)
            #expect(controller.canMute == false)
        }
    #endif
}
