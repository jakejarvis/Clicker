import SwiftUI

/// Walks through the one-time pairing: ask the Apple TV to show a PIN, then
/// type it here.
struct PairingView: View {
    let controller: RemoteController
    let device: AppleTVDevice

    @State private var pin = ""
    @FocusState private var pinFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "appletv")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Pair with \(device.name)")
                .font(.headline)

            switch controller.pairingState {
            case .idle:
                Text("Clicker pairs once, like the iPhone Remote app. A four-digit PIN will appear on the TV.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Pair…") { controller.beginPairing() }
                    .prominentActionStyle()
                    .disabled(device.pairingDisabled)
                if device.pairingDisabled {
                    Text(CompanionError.pairingDisabled.localizedDescription)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

            case .starting:
                ProgressView()
                    .controlSize(.small)
                Text("Asking the Apple TV to show a PIN…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Cancel") { controller.cancelPairing() }

            case .awaitingPIN, .finishing:
                Text("Enter the PIN shown on the TV.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("0000", text: $pin)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.title2, design: .rounded).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .frame(width: 110)
                    .focused($pinFocused)
                    .disabled(controller.pairingState == .finishing)
                    .onChange(of: pin) { _, newValue in
                        let digits = String(newValue.filter(\.isNumber).prefix(4))
                        if digits != newValue { pin = digits }
                        if digits.count == 4, controller.pairingState == .awaitingPIN {
                            controller.submitPIN(digits)
                        }
                    }
                    .onSubmit { controller.submitPIN(pin) }
                    .onAppear { pinFocused = true }
                HStack {
                    Button("Cancel") {
                        controller.cancelPairing()
                        pin = ""
                    }
                    Button("Pair") { controller.submitPIN(pin) }
                        .prominentActionStyle()
                        .disabled(pin.count != 4 || controller.pairingState == .finishing)
                }
                if controller.pairingState == .finishing {
                    ProgressView()
                        .controlSize(.small)
                }

            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    pin = ""
                    controller.beginPairing()
                }
                .prominentActionStyle()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
