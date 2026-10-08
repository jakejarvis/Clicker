import AppKit
import SwiftUI

/// Appears while the Apple TV shows its keyboard; keystrokes go straight to
/// the TV's focused field.
struct TVTextFieldView: View {
    let controller: RemoteController

    private var text: Binding<String> {
        Binding(
            get: { controller.tvText },
            set: { controller.updateTVText($0) }
        )
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PanelMetrics.innerCornerRadius, style: .continuous)
        HStack(spacing: 8) {
            Image(systemName: "keyboard")
                .foregroundStyle(.secondary)
            CommittedTextField(
                text: text,
                placeholder: "Type on Apple TV",
                focusToken: controller.panelAppearances,
                onSubmit: { controller.submitTVText() },
                onCancel: { controller.focusPad() }
            )
            if !controller.tvText.isEmpty {
                Button {
                    controller.clearTVText()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear the field on the Apple TV")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .surface(shape, interactive: false)
        .accessibilityLabel("Text for the Apple TV")
    }
}

/// A plain text field that reports only committed text. While an input
/// method is composing (Japanese, Korean, Chinese, or a dead key such as ⌥E
/// for an accent) the field editor holds a marked range and every keystroke
/// rewrites it; a SwiftUI `TextField` pushes each of those steps through its
/// binding, which here would mean a replace event to the TV per keystroke.
/// This field skips changes made while marked text is present and forwards
/// the text once the composition is committed. It takes focus when it
/// appears and whenever `focusToken` changes (the panel opening again, which
/// clears the first responder). Esc resigns it and calls `onCancel`, which
/// hands the keys to the clickpad; resigning alone leaves the window itself
/// as first responder and every key beeps.
private struct CommittedTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusToken: Int
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, focusToken: focusToken, onSubmit: onSubmit, onCancel: onCancel)
    }

    func makeNSView(context: Context) -> FocusOnAppearTextField {
        let field = FocusOnAppearTextField(string: text)
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .preferredFont(forTextStyle: .body)
        field.lineBreakMode = .byClipping
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: FocusOnAppearTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onCancel = onCancel
        // The TV can change the text under us (a new field gaining focus, or
        // Clear); never interrupt a composition in progress to show it.
        if field.stringValue != text, !Self.isComposing(field) {
            field.stringValue = text
        }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            field.requestFocus()
        }
    }

    static func isComposing(_ field: NSTextField) -> Bool {
        (field.currentEditor() as? NSTextView)?.hasMarkedText() ?? false
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var focusToken: Int
        var onSubmit: () -> Void
        var onCancel: () -> Void

        init(
            text: Binding<String>, focusToken: Int, onSubmit: @escaping () -> Void, onCancel: @escaping () -> Void
        ) {
            self.text = text
            self.focusToken = focusToken
            self.onSubmit = onSubmit
            self.onCancel = onCancel
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField, !CommittedTextField.isComposing(field) else {
                return
            }
            if text.wrappedValue != field.stringValue {
                text.wrappedValue = field.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                control.window?.makeFirstResponder(nil)
                onCancel()
                return true
            default:
                return false
            }
        }
    }
}

/// Becomes first responder the first time it lands in a window, the way the
/// SwiftUI field used `@FocusState` on appear, and again on request.
final class FocusOnAppearTextField: NSTextField {
    private var hasRequestedFocus = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !hasRequestedFocus, window != nil else { return }
        hasRequestedFocus = true
        requestFocus()
    }

    /// Deferred a turn so it lands after whatever cleared the first
    /// responder in the same pass.
    func requestFocus() {
        guard let window else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window === window else { return }
            window.makeFirstResponder(self)
        }
    }
}
