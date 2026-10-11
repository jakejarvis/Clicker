import KeyboardShortcuts
import SwiftUI

/// The package's recorder field, sized to the space its row has left and
/// with a working clear button.
///
/// `KeyboardShortcuts.Recorder` (the package's own SwiftUI wrapper) is rigid:
/// the field's intrinsic width is 130pt whatever is proposed, and a `.frame`
/// around it cannot shrink it. In a `SettingsRow` that minimum (title, the
/// stack spacing on both sides of the spacer, the field, the row padding)
/// came to 260pt against the 236pt the cards get, so the whole Settings
/// screen laid out 24pt wider than the panel and lost 12pt of gutter on each
/// side (2026-10-11). This wrapper answers the proposal instead, up to the
/// field's natural width.
///
/// The field's own x button never cleared anything here: a click on it makes
/// the search field first responder before the cancel button completes on
/// mouse-up, and the recorder's `becomeFirstResponder` installs a local
/// monitor that swallows every mouse-up inside the field, so the button's
/// tracking never finishes and the click only selects the text. (A plain
/// `NSSearchField` in the same row cleared fine; one with just that monitor
/// copied in failed the same way; measured on macOS 27.) `Coordinator`
/// therefore watches mouse-downs itself: a click in the cell's cancel rect
/// while a shortcut is set resets it through the package, which updates the
/// field, and the event is dropped so the field does not start editing.
struct ShortcutRecorder: NSViewRepresentable {
    let name: KeyboardShortcuts.Name
    var naturalWidth: CGFloat = 130
    /// The small search field's height; its `intrinsicContentSize` reports the
    /// regular 22 even after `controlSize` is set.
    private let height: CGFloat = 19

    func makeCoordinator() -> Coordinator { Coordinator(name: name) }

    func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
        let field = KeyboardShortcuts.RecorderCocoa(for: name)
        field.controlSize = .small
        field.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        context.coordinator.watchCancelButton(of: field)
        return field
    }

    func updateNSView(_ nsView: KeyboardShortcuts.RecorderCocoa, context: Context) {
        nsView.shortcutName = name
        context.coordinator.name = name
    }

    static func dismantleNSView(_ nsView: KeyboardShortcuts.RecorderCocoa, coordinator: Coordinator) {
        coordinator.stop()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: KeyboardShortcuts.RecorderCocoa, context: Context
    ) -> CGSize? {
        CGSize(width: min(proposal.width ?? naturalWidth, naturalWidth), height: height)
    }

    @MainActor
    final class Coordinator {
        var name: KeyboardShortcuts.Name
        private var monitor: Any?

        init(name: KeyboardShortcuts.Name) {
            self.name = name
        }

        func watchCancelButton(of field: KeyboardShortcuts.RecorderCocoa) {
            stop()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self, weak field] event in
                let location = event.locationInWindow
                let windowID = event.window.map(ObjectIdentifier.init)
                let consumed = MainActor.assumeIsolated { () -> Bool in
                    guard let self, let field, let window = field.window, windowID == ObjectIdentifier(window),
                        KeyboardShortcuts.getShortcut(for: self.name) != nil,
                        let cell = field.cell as? NSSearchFieldCell
                    else { return false }
                    let point = field.convert(location, from: nil)
                    guard cell.cancelButtonRect(forBounds: field.bounds).contains(point) else { return false }
                    KeyboardShortcuts.reset(self.name)
                    return true
                }
                return consumed ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
