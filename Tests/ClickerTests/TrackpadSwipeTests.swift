import Foundation
import Testing

@testable import Clicker

@Suite struct TrackpadSwipeTests {
    typealias Event = TrackpadSwipe.Event

    private let center = CGPoint(x: TrackpadSwipe.surfaceSize / 2, y: TrackpadSwipe.surfaceSize / 2)

    @Test func aGestureStartsWithTheFingerAtTheCenter() {
        var swipe = TrackpadSwipe()
        #expect(swipe.isActive == false)
        #expect(swipe.translate(Event(phase: .began)) == .touchDown(center))
        #expect(swipe.isActive)
    }

    @Test func naturalScrollingFollowsTheFingers() {
        var swipe = TrackpadSwipe()
        _ = swipe.translate(Event(phase: .began))
        // Fingers moving down and to the right: AppKit reports positive
        // deltas under Natural scrolling, and the TV's y grows downward.
        let action = swipe.translate(Event(phase: .changed, deltaX: 10, deltaY: 20, isDirectionInverted: true))
        let expected = CGPoint(x: center.x + 10 * TrackpadSwipe.gain, y: center.y + 20 * TrackpadSwipe.gain)
        #expect(action == .touchMove(expected))
        #expect(swipe.position == expected)
    }

    @Test func traditionalScrollingIsFlippedBackToTheFingers() {
        var swipe = TrackpadSwipe()
        _ = swipe.translate(Event(phase: .began))
        let action = swipe.translate(Event(phase: .changed, deltaX: 10, deltaY: 20, isDirectionInverted: false))
        let expected = CGPoint(x: center.x - 10 * TrackpadSwipe.gain, y: center.y - 20 * TrackpadSwipe.gain)
        #expect(action == .touchMove(expected))
    }

    @Test func slidingOffAnEdgeLiftsTheFingerThere() {
        var swipe = TrackpadSwipe()
        _ = swipe.translate(Event(phase: .began))
        let action = swipe.translate(Event(phase: .changed, deltaX: -10_000, deltaY: 10_000))
        #expect(action == .touchUp(CGPoint(x: 0, y: TrackpadSwipe.surfaceSize)))
        #expect(swipe.position == nil)
        // The rest of the gesture is still the pad's, but sends nothing.
        #expect(swipe.isActive)
        #expect(swipe.translate(Event(phase: .changed, deltaX: -1, deltaY: 1)) == nil)
        #expect(swipe.translate(Event(phase: .ended)) == nil)
        #expect(swipe.isActive == false)
    }

    @Test func easingBackAfterAnOvershootNeverMovesTheFingerBackwards() {
        var swipe = TrackpadSwipe()
        _ = swipe.translate(Event(phase: .began))
        // A flick down past the bottom edge, then the fingers settle back a
        // little as they lift: the TV must not see a move back up.
        _ = swipe.translate(Event(phase: .changed, deltaY: 120))
        let up = swipe.translate(Event(phase: .changed, deltaY: 120))
        guard case .touchUp(let released) = up else {
            Issue.record("Expected a release at the edge, got \(String(describing: up))")
            return
        }
        #expect(released.y == TrackpadSwipe.surfaceSize)
        #expect(swipe.translate(Event(phase: .changed, deltaY: -2)) == nil)
        #expect(swipe.translate(Event(phase: .ended)) == nil)
    }

    @Test func aStationaryEventSendsNothing() {
        var swipe = TrackpadSwipe()
        _ = swipe.translate(Event(phase: .began))
        #expect(swipe.translate(Event(phase: .changed)) == nil)
    }

    @Test func liftingTheFingersReleasesWhereTheyWere() {
        var swipe = TrackpadSwipe()
        _ = swipe.translate(Event(phase: .began))
        _ = swipe.translate(Event(phase: .changed, deltaY: 5))
        let last = swipe.position
        #expect(swipe.translate(Event(phase: .ended)) == .touchUp(last!))
        #expect(swipe.isActive == false)
        #expect(swipe.position == nil)
    }

    @Test func aCancelledGestureReleasesToo() {
        var swipe = TrackpadSwipe()
        _ = swipe.translate(Event(phase: .began))
        #expect(swipe.translate(Event(phase: .cancelled)) == .touchUp(center))
        #expect(swipe.isActive == false)
    }

    @Test func momentumIsLeftToTheTV() {
        var swipe = TrackpadSwipe()
        _ = swipe.translate(Event(phase: .began))
        _ = swipe.translate(Event(phase: .ended))
        // The Mac keeps coasting after the fingers lift (momentum events,
        // which carry no finger phase); tvOS already does its own, from the
        // release velocity.
        #expect(swipe.translate(Event(phase: .none, deltaY: 30)) == nil)
        #expect(swipe.translate(Event(phase: .none, deltaY: 0)) == nil)
        #expect(swipe.isActive == false)
    }

    @Test func restingFingersAndWheelNotchesAreIgnored() {
        var swipe = TrackpadSwipe()
        #expect(swipe.translate(Event(phase: .mayBegin)) == nil)
        #expect(swipe.translate(Event(phase: .cancelled)) == nil)
        #expect(swipe.translate(Event(phase: .none, deltaY: 1)) == nil)
        // Motion without a press (a Magic Mouse never sends mayBegin, but a
        // changed without a began should still not invent a finger).
        #expect(swipe.translate(Event(phase: .changed, deltaY: 1)) == nil)
        #expect(swipe.isActive == false)
    }
}
