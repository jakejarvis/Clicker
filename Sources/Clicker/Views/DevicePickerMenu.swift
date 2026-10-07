import SwiftUI

/// The selected Apple TV's name as a title; clicking it drops down a list of
/// every known device with icon, name, state and a checkmark on the current
/// one. A custom popover is used because system menus cannot show subtitles.
struct DevicePickerMenu: View {
    let controller: RemoteController
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: controller.selectedDevice?.isOnline == false ? "appletv" : "appletv.fill")
                    .font(.title3)
                    .foregroundStyle(controller.connectionState == .connected ? Color.accentColor : .secondary)
                    .frame(width: 22)
                Text(controller.selectedDevice?.name ?? "Choose Apple TV")
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isPresented ? 180 : 0))
                    .animation(.snappy(duration: 0.2), value: isPresented)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(controller.devices.isEmpty)
        .help(controller.selectedDevice?.modelDisplayName ?? "Choose an Apple TV")
        .accessibilityLabel("Apple TV: \(controller.selectedDevice?.name ?? "none selected")")
        .accessibilityHint("Opens the list of Apple TVs")
        // Anchor the popover to the full header width so it centers under the
        // panel instead of hanging off its left edge.
        .frame(maxWidth: .infinity, alignment: .leading)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            DeviceListView(controller: controller) { device in
                controller.select(device)
                isPresented = false
            }
        }
    }
}

private struct DeviceListView: View {
    let controller: RemoteController
    let onSelect: (AppleTVDevice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(controller.devices) { device in
                DeviceRow(
                    device: device,
                    state: stateText(for: device),
                    isSelected: device.id == controller.selectedDeviceID,
                    isPaired: controller.isPaired(device)
                ) {
                    onSelect(device)
                }
            }
        }
        .padding(6)
        .frame(width: 240)
    }

    private func stateText(for device: AppleTVDevice) -> String {
        if device.id == controller.selectedDeviceID {
            return controller.selectedStateDescription
        }
        if !device.isOnline { return "Offline" }
        return controller.isPaired(device) ? device.modelDisplayName : "Not paired"
    }
}

private struct DeviceRow: View {
    let device: AppleTVDevice
    let state: String
    let isSelected: Bool
    let isPaired: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: device.isOnline ? "appletv.fill" : "appletv")
                    .font(.title3)
                    .foregroundStyle(device.isOnline ? Color.accentColor : .secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(state)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                } else if !isPaired, device.isOnline {
                    Text("Pair")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? AnyShapeStyle(.selection.opacity(0.9)) : AnyShapeStyle(.clear))
            )
            .foregroundStyle(isHovered ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .opacity(device.isOnline ? 1 : 0.6)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(device.name), \(state)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
