import ClickerCompanion
import Foundation

/// Turns a two-finger scroll on the Mac's trackpad into one finger on the
/// Siri Remote's touch surface. The finger presses at the center of the TV's
/// surface when the gesture begins, follows the fingers while it lasts, and
/// lifts the moment they do, or the moment it slides off an edge, as a
/// finger on the real remote would. The Mac's own momentum events are dropped so
/// that tvOS applies its flick physics from the release velocity, the way it
/// does for the real remote; forwarding them would stack two decelerations.
///
/// Kept free of AppKit so the rules are unit tested; the view layer reduces
/// an `NSEvent` to an `Event`.
nonisolated struct TrackpadSwipe: Sendable {
    /// One scroll-wheel event, reduced to what the translation needs.
    struct Event: Sendable {
        enum Phase: Sendable {
            /// A legacy wheel notch or a momentum event: no gesture phase.
            case none
            case mayBegin
            case began
            case changed
            case ended
            case cancelled
        }

        var phase: Phase
        /// Scroll deltas in points, as AppKit reports them: already flipped
        /// for Natural scrolling when `isDirectionInverted` is set.
        var deltaX: CGFloat = 0
        var deltaY: CGFloat = 0
        /// `NSEvent.isDirectionInvertedFromDevice`: true under Natural scrolling.
        var isDirectionInverted = true
    }

    enum Action: Equatable, Sendable {
        case touchDown(CGPoint)
        case touchMove(CGPoint)
        case touchUp(CGPoint)
    }

    /// Side of the TV's touch surface, in its own units.
    static let surfaceSize: CGFloat = CompanionClient.touchpadSize
    /// Touch-surface units per point of scroll delta. The remote's pad is
    /// about 32 mm across (31 units/mm) and trackpad scrolling tracks the
    /// fingers near the display's physical scale (about 5 pt/mm on a Retina
    /// MacBook), so parity would be 6; from a center press that leaves 16 mm
    /// before the edge. At 3 a full-pad swipe takes about 33 mm of finger
    /// travel and a quick flick still arrives well above 3000 units/s, which
    /// tvOS reads as a flick. Not yet tuned against a TV.
    static let gain: CGFloat = 3

    /// Where the finger is while it touches the surface, in surface units
    /// with the origin top left; nil between gestures and once the fingers
    /// have carried it off an edge.
    private(set) var position: CGPoint?

    /// Whether a gesture is in progress, from its began to its end, whether
    /// or not the finger is still on the surface: the rest of a gesture that
    /// slid off an edge is still the pad's, so nothing else scrolls with it.
    private(set) var isActive = false

    /// The touch to send for one event, or nil when the event changes nothing.
    /// The coasting events a trackpad or Magic Mouse sends after the fingers
    /// lift carry a momentum phase and no finger phase, so they land in
    /// `.none`; a finger phase always wins, so a release is never lost.
    mutating func translate(_ event: Event) -> Action? {
        switch event.phase {
        case .none, .mayBegin:
            // Momentum, a legacy wheel notch, or two fingers resting before
            // they move: pressing on the last and then cancelling would reach
            // the TV as a tap.
            return nil
        case .began:
            let center = CGPoint(x: Self.surfaceSize / 2, y: Self.surfaceSize / 2)
            position = center
            isActive = true
            return .touchDown(center)
        case .changed:
            guard let current = position else { return nil }
            // The TV wants the fingers' own motion (focus follows the finger,
            // which for a list is the opposite of content following it), and
            // AppKit has already flipped the deltas under Natural scrolling.
            let sign: CGFloat = event.isDirectionInverted ? 1 : -1
            let moved = CGPoint(
                x: current.x + sign * event.deltaX * Self.gain,
                y: current.y + sign * event.deltaY * Self.gain)
            guard moved != current else { return nil }
            // The trackpad is far larger than the surface, so a quick swipe
            // runs past an edge within a tenth of a second. Pinning the
            // finger there made the TV see it stop dead and lift with no
            // velocity, and focus sometimes jerked back a row; lifting at the
            // edge releases it still moving, as a finger sliding off the
            // real remote would, so the flick carries on.
            let edge = CGPoint(x: Self.clamp(moved.x), y: Self.clamp(moved.y))
            guard edge == moved else {
                position = nil
                return .touchUp(edge)
            }
            position = moved
            return .touchMove(moved)
        case .ended, .cancelled:
            isActive = false
            guard let current = position else { return nil }
            position = nil
            return .touchUp(current)
        }
    }

    private static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), surfaceSize)
    }
}
