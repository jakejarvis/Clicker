import SwiftUI

/// Four digit cells that take keyboard focus directly and collect digits
/// from key presses, the same way the remote's shortcuts work. A hidden
/// text field was tried first and never became first responder in the
/// non-activating panel. The next empty cell carries an accent border; the
/// code is handed over as soon as the fourth digit lands.
struct PINCodeField: View {
    @Binding var code: String
    var isEnabled = true
    let onComplete: (String) -> Void

    @FocusState private var isFocused: Bool

    private let length = 4
    private let cellWidth: CGFloat = 38
    private let cellHeight: CGFloat = 46

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<length, id: \.self) { index in
                cell(at: index)
            }
        }
        .contentShape(Rectangle())
        .focusable(isEnabled)
        .focusEffectDisabled()
        .focused($isFocused)
        .onTapGesture { isFocused = true }
        .onAppear {
            DispatchQueue.main.async { isFocused = true }
        }
        .onKeyPress(characters: .decimalDigits, phases: .down) { press in
            guard isEnabled, code.count < length else { return .ignored }
            // Reading the binding back inside the handler returns the old
            // value, so decide on the local copy.
            let next = code + press.characters
            code = next
            if next.count == length { onComplete(next) }
            return .handled
        }
        .onKeyPress(phases: .down) { press in
            // Backspace and forward delete arrive as different keys depending
            // on the source; match the characters as well as the key.
            let isDelete =
                press.key == .delete || press.key == .deleteForward || press.characters == "\u{8}"
                || press.characters == "\u{7F}"
            guard isDelete, isEnabled, !code.isEmpty else { return .ignored }
            code.removeLast()
            return .handled
        }
        .onKeyPress(.return, phases: .down) { _ in
            guard isEnabled, code.count == length else { return .ignored }
            onComplete(code)
            return .handled
        }
        .animation(.snappy(duration: 0.15), value: code)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PIN")
        .accessibilityValue(code)
    }

    private func cell(at index: Int) -> some View {
        let digits = Array(code)
        let digit = index < digits.count ? String(digits[index]) : ""
        let isActive = isEnabled && isFocused && index == min(digits.count, length - 1)
        let shape = RoundedRectangle(cornerRadius: PanelMetrics.innerCornerRadius, style: .continuous)

        return Text(digit)
            .font(.system(size: 22, weight: .medium, design: .rounded).monospacedDigit())
            .frame(width: cellWidth, height: cellHeight)
            .background(.quaternary, in: shape)
            .overlay(
                shape.strokeBorder(
                    isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
                    lineWidth: isActive ? 2 : 1)
            )
            .opacity(isEnabled ? 1 : 0.6)
    }
}
