import SwiftUI

/// Appears while the Apple TV shows its keyboard; keystrokes go straight to
/// the TV's focused field.
struct TVTextFieldView: View {
    let controller: RemoteController
    @FocusState private var isFocused: Bool

    private var text: Binding<String> {
        Binding(
            get: { controller.tvText },
            set: { controller.updateTVText($0) }
        )
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        HStack(spacing: 8) {
            Image(systemName: "keyboard")
                .foregroundStyle(.secondary)
            TextField("Type on Apple TV", text: text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onExitCommand { isFocused = false }
                .onSubmit { isFocused = false }
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
        .onAppear { isFocused = true }
        .accessibilityLabel("Text for the Apple TV")
    }
}
