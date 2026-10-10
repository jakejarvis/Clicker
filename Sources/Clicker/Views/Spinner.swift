import SwiftUI

/// Indeterminate spinner drawn with the `progress.indicator` symbol in the
/// current foreground style. The system `ProgressView` spinner is a mid gray
/// whose tail fades to nothing, which all but vanishes on the dark panel's
/// materials and can't be tinted.
struct Spinner: View {
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: "progress.indicator")
            .font(.system(size: size))
            .symbolEffect(
                .variableColor.iterative.hideInactiveLayers.nonReversing,
                options: .repeat(.continuous)
            )
            .accessibilityLabel("Loading")
    }
}
