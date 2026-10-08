import SwiftUI

/// Something standing between the user and a working remote. The remote is
/// shown ghosted behind one of these cards so the panel keeps its shape and
/// the user can see what they are about to unlock.
enum RemoteOverlay: Hashable {
    /// The selected TV has no pairing yet (or just finished one).
    case pairing(deviceID: String)
    /// The selected TV is paired but not on the network right now.
    case offline(deviceID: String)
    /// No Apple TV has been found yet.
    case searching
    /// TVs exist but none is selected.
    case choose
}

/// Material card centered over the clickpad.
struct OverlayCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    private let shape = RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)

    var body: some View {
        VStack(spacing: 10) {
            content()
        }
        .multilineTextAlignment(.center)
        .padding(16)
        .frame(width: 212)
        .background(.regularMaterial, in: shape)
        .overlay(shape.strokeBorder(.separator.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
    }
}

/// Walks through the one-time pairing in place: Pair, wait for the TV to
/// show a code, enter it, see a check, then the remote comes alive.
struct PairingCard: View {
    let controller: RemoteController
    let device: AppleTVDevice

    @State private var pin = ""

    var body: some View {
        OverlayCard {
            stateContent
                .transition(.opacity)
        }
        .animation(.snappy(duration: 0.25), value: controller.pairingState)
        .onChange(of: controller.pairingState) { _, state in
            if state == .idle || state == .starting { pin = "" }
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch controller.pairingState {
        case .idle:
            CardTitle("Pair with \(device.name)")
            if device.pairingDisabled {
                CardCaption(CompanionError.pairingDisabled.localizedDescription, tint: .orange)
            } else {
                CardCaption("A code will appear on your TV.")
            }
            Button("Pair…") { controller.beginPairing() }
                .prominentActionStyle()
                .disabled(device.pairingDisabled)

        case .starting:
            CardTitle("Pair with \(device.name)")
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                CardCaption("Waiting for your TV…")
            }
            Button("Cancel") { controller.cancelPairing() }

        case .awaitingPIN, .finishing:
            CardTitle("Enter the code")
            CardCaption("Shown on your TV.")
            PINCodeField(code: $pin, isEnabled: controller.pairingState == .awaitingPIN) { code in
                controller.submitPIN(code)
            }
            if controller.pairingState == .finishing {
                ProgressView()
                    .controlSize(.small)
                    .frame(height: 22)
            } else {
                Button("Cancel") { cancel() }
            }

        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: controller.pairingState)
            CardTitle("Paired")

        case .failed(let message):
            CardTitle("Pairing failed")
            CardCaption(message)
            HStack(spacing: 8) {
                Button("Cancel") { cancel() }
                Button("Try Again") {
                    pin = ""
                    controller.beginPairing()
                }
                .prominentActionStyle()
            }
        }
    }

    private func cancel() {
        controller.cancelPairing()
        pin = ""
    }
}

struct OfflineCard: View {
    let device: AppleTVDevice

    var body: some View {
        OverlayCard {
            Image(systemName: "wifi.slash")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            CardTitle("\(device.name) is offline")
            CardCaption("Not on this network right now.")
        }
    }
}

struct SearchingCard: View {
    let message: String?

    var body: some View {
        OverlayCard {
            ProgressView()
                .controlSize(.small)
            CardTitle("Looking for Apple TVs…")
            CardCaption(message ?? "Make sure this Mac and the Apple TV share a network.")
        }
    }
}

struct ChooseDeviceCard: View {
    var body: some View {
        OverlayCard {
            Image(systemName: "appletv")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            CardTitle("Choose an Apple TV")
            CardCaption("Pick one from the list above.")
        }
    }
}

private struct CardTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.headline)
            .lineLimit(2)
    }
}

private struct CardCaption: View {
    let text: String
    var tint: Color?

    init(_ text: String, tint: Color? = nil) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}
