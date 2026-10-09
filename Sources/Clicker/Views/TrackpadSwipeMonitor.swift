import AppKit
import SwiftUI

extension View {
    /// Turns two-finger scrolls over this view into swipes on the TV's touch
    /// surface, like a finger on the Siri Remote's clickpad.
    func trackpadSwipes(controller: RemoteController, isEnabled: Bool) -> some View {
        modifier(TrackpadSwipeMonitor(controller: controller, isEnabled: isEnabled))
    }
}

/// Scroll-wheel events ride a local monitor, like the panel's Esc and the
/// Apps picker's arrows: SwiftUI has no scroll-wheel gesture outside a
/// `ScrollView`, and AppKit sends gesture scrolls to the window under the
/// pointer whether or not the app is active. The monitor acts only while the
/// pointer is over the pad in the panel itself; a scroll over the device or
/// Apps popover belongs to that popover's list and passes through.
///
/// Each event is hit-tested against the pad's own bounds rather than a
/// hover flag: an inert pad takes no hit tests and so gets no hover events,
/// which left the flag stale whenever the pad changed state under a resting
/// pointer (an overlay card coming or going).
private struct TrackpadSwipeMonitor: ViewModifier {
    let controller: RemoteController
    let isEnabled: Bool
    @State private var tracking = SwipeTracking()

    func body(content: Content) -> some View {
        content
            .background(PadLocator(tracking: tracking))
            // The monitor's closure holds the modifier as it was when it
            // was installed, so the flag is kept where the closure reads it.
            .onChange(of: isEnabled, initial: true) {
                tracking.isEnabled = isEnabled
                if !isEnabled { cancel() }
            }
            .onAppear(perform: install)
            .onDisappear(perform: remove)
    }

    /// Lifts a finger the pad can no longer follow (the pad went inert or
    /// off screen mid-gesture), so the TV is not left with it held down.
    private func cancel() {
        if let action = tracking.swipe.translate(.init(phase: .cancelled)) {
            controller.handleTrackpadSwipe(action)
        }
    }

    private func install() {
        guard tracking.monitor == nil else { return }
        tracking.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            let consumed = MainActor.assumeIsolated { handle(event) }
            return consumed ? nil : event
        }
    }

    private func remove() {
        cancel()
        if let monitor = tracking.monitor { NSEvent.removeMonitor(monitor) }
        tracking.monitor = nil
    }

    /// Whether the event was the pad's. A gesture that started over the pad
    /// is followed to its release wherever the hover state went, so the TV
    /// never keeps a finger down.
    private func handle(_ event: NSEvent) -> Bool {
        guard tracking.isEnabled, let pad = tracking.padView, event.window === pad.window else { return false }
        let overPad = pad.bounds.contains(pad.convert(event.locationInWindow, from: nil))
        guard tracking.swipe.isActive || (overPad && !controller.isAppPickerPresented) else { return false }
        if let action = tracking.swipe.translate(TrackpadSwipe.Event(event)) {
            controller.handleTrackpadSwipe(action)
        }
        return true
    }
}

/// What the monitor's closure reads and writes outside SwiftUI updates. A
/// class held in `@State` rather than `@State` values, since every scroll
/// event would otherwise invalidate the pad.
private final class SwipeTracking {
    var swipe = TrackpadSwipe()
    var isEnabled = false
    /// The pad's bounds in AppKit terms, for hit-testing scroll events.
    weak var padView: NSView?
    var monitor: Any?
}

/// An empty AppKit view filling the pad (ring, Select and the channel
/// between them, the corners of the frame included), so a scroll event's
/// window location can be converted into the pad's own bounds. It never
/// takes a hit itself, so SwiftUI's clicks and hover pass through unchanged.
private struct PadLocator: NSViewRepresentable {
    let tracking: SwipeTracking

    func makeNSView(context: Context) -> PassthroughView {
        let view = PassthroughView()
        tracking.padView = view
        return view
    }

    func updateNSView(_ nsView: PassthroughView, context: Context) {
        tracking.padView = nsView
    }
}

private final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension TrackpadSwipe.Event {
    fileprivate init(_ event: NSEvent) {
        self.init(
            phase: Phase(event.phase),
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            isDirectionInverted: event.isDirectionInvertedFromDevice)
    }
}

extension TrackpadSwipe.Event.Phase {
    /// Momentum events have a `phase` of none (their `momentumPhase` is set
    /// instead), so they map to `.none` without being looked at.
    fileprivate init(_ phase: NSEvent.Phase) {
        if phase.contains(.began) {
            self = .began
        } else if phase.contains(.changed) {
            self = .changed
        } else if phase.contains(.ended) {
            self = .ended
        } else if phase.contains(.cancelled) {
            self = .cancelled
        } else if phase.contains(.mayBegin) {
            self = .mayBegin
        } else {
            self = .none
        }
    }
}
