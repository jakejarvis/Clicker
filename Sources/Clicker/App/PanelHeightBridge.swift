import AppKit
import SwiftUI
import os

/// SwiftUI owns the panel's height; the window follows it one frame at a time.
///
/// An identity `GeometryEffect` whose `animatableData` is the content height:
/// inside a `withAnimation` SwiftUI sets it once per frame with the
/// interpolated value, so the window resize rides the same curve as the
/// screen slide instead of an AppKit animation of its own chasing a moving
/// target. `effectValue` forwards un-animated changes too. A `GeometryEffect`
/// rather than a `ViewModifier` because a modifier's `body` is main-actor
/// isolated, which `Animatable` does not allow. Zero means "not measured
/// yet" and is skipped, so the panel keeps its opening size until then.
struct PanelHeightEffect: GeometryEffect {
    var height: CGFloat

    var animatableData: CGFloat {
        get { height }
        set {
            height = newValue
            PanelHeightBridge.push(newValue)
        }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        PanelHeightBridge.push(height)
        return ProjectionTransform()
    }
}

extension View {
    /// Makes the panel follow `height`. Attach at the root, outside any
    /// `.animation(nil)` scope, so the height rides the active animation.
    func drivesPanelHeight(_ height: CGFloat?) -> some View {
        modifier(PanelHeightEffect(height: height ?? 0))
    }
}

/// Hands heights from SwiftUI's layout pass to the panel on the next turn of
/// the main queue: a synchronous `setFrame` from inside the pass re-enters
/// AppKit layout on the constraint-pinned host. A burst within one turn is
/// coalesced to its newest height, and a generation bumped on every open and
/// close drops frames queued for a panel that has since been hidden or
/// reopened, since a pending hop cannot be cancelled.
enum PanelHeightBridge {
    /// Installed by `StatusItemController`; applies one clamped frame.
    @MainActor static var apply: ((CGFloat) -> Void)?

    private struct State {
        var generation = 0
        var pending: CGFloat?
        var isScheduled = false
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    static func invalidate() {
        state.withLock {
            $0.generation += 1
            $0.pending = nil
            $0.isScheduled = false
        }
    }

    static func push(_ height: CGFloat) {
        guard height > 0 else { return }
        let (generation, shouldSchedule) = state.withLock { state in
            state.pending = height
            if state.isScheduled { return (state.generation, false) }
            state.isScheduled = true
            return (state.generation, true)
        }
        guard shouldSchedule else { return }
        DispatchQueue.main.async {
            let height = state.withLock { state -> CGFloat? in
                guard state.generation == generation else { return nil }
                defer {
                    state.pending = nil
                    state.isScheduled = false
                }
                return state.pending
            }
            guard let height else { return }
            MainActor.assumeIsolated { apply?(height) }
        }
    }
}
