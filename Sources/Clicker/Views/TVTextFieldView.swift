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
                onSubmit: { controller.submitTVText() }
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
/// appears and gives it up on Esc, so the clickpad's shortcuts work again.
private struct CommittedTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
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
        // The TV can change the text under us (a new field gaining focus, or
        // Clear); never interrupt a composition in progress to show it.
        if field.stringValue != text, !Self.isComposing(field) {
            field.stringValue = text
        }
    }

    static func isComposing(_ field: NSTextField) -> Bool {
        (field.currentEditor() as? NSTextView)?.hasMarkedText() ?? false
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
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
                return true
            default:
                return false
            }
        }
    }
}

/// Becomes first responder the first time it lands in a window, the way the
/// SwiftUI field used `@FocusState` on appear.
final class FocusOnAppearTextField: NSTextField {
    private var hasRequestedFocus = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !hasRequestedFocus, let window else { return }
        hasRequestedFocus = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window === window else { return }
            window.makeFirstResponder(self)
        }
    }
}
