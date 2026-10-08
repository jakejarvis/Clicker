import SwiftUI

/// The device selector: a full-width control showing the current Apple TV's
/// icon, name, model and state. Clicking it drops down a list of every known
/// device in the same style, with a checkmark on the current one. A custom
/// popover is used because system menus cannot show subtitles.
struct DevicePickerMenu: View {
    let controller: RemoteController
    @State private var isPresented = false

    private let shape = RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 10) {
                DeviceIcon(device: controller.selectedDevice, isConnected: controller.connectionState == .connected)
                VStack(alignment: .leading, spacing: 1) {
                    Text(controller.selectedDevice?.name ?? "Choose an Apple TV")
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    subtitle
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: PanelMetrics.headerControlHeight)
            .contentShape(shape)
        }
        .buttonStyle(PressFeedbackStyle())
        .surface(shape)
        .disabled(controller.devices.isEmpty)
        .help("Choose an Apple TV")
        .accessibilityLabel("Apple TV: \(controller.selectedDevice?.name ?? "none selected")")
        .accessibilityHint("Opens the list of Apple TVs")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            DeviceListView(controller: controller) { device in
                controller.select(device)
                isPresented = false
            }
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if let device = controller.selectedDevice {
            HStack(spacing: 4) {
                Text(device.shortModelName)
                    .truncationMode(.tail)
                Text("·")
                Text(controller.selectedStateDescription)
                    .layoutPriority(1)
            }
        } else if controller.devices.isEmpty {
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text("Looking on your network…")
            }
        } else {
            Text("\(controller.devices.count) found")
        }
    }
}

/// Rounded tile with the Apple TV glyph; tinted while connected.
struct DeviceIcon: View {
    let device: AppleTVDevice?
    let isConnected: Bool

    var body: some View {
        Image(systemName: device?.isOnline == false ? "appletv" : "appletv.fill")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isConnected ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.gray.gradient))
            )
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
                    subtitle: subtitle(for: device),
                    isSelected: device.id == controller.selectedDeviceID,
                    isConnected: device.id == controller.selectedDeviceID && controller.connectionState == .connected,
                    isPaired: controller.isPaired(device)
                ) {
                    onSelect(device)
                }
            }
        }
        .padding(6)
        .frame(width: MenuBarView.panelWidth - 28)
    }

    private func subtitle(for device: AppleTVDevice) -> String {
        if device.id == controller.selectedDeviceID {
            return "\(device.shortModelName) · \(controller.selectedStateDescription)"
        }
        if !device.isOnline { return "\(device.shortModelName) · Offline" }
        return controller.isPaired(device) ? device.modelDisplayName : "\(device.shortModelName) · Not paired"
    }
}

private struct DeviceRow: View {
    let device: AppleTVDevice
    let subtitle: String
    let isSelected: Bool
    let isConnected: Bool
    let isPaired: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                DeviceIcon(device: device, isConnected: isConnected)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isHovered ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isHovered ? AnyShapeStyle(.white) : AnyShapeStyle(Color.accentColor))
                } else if !isPaired, device.isOnline {
                    Text("Pair")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: PanelMetrics.innerCornerRadius, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: PanelMetrics.innerCornerRadius, style: .continuous)
                    .fill(isHovered ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear))
            )
            .foregroundStyle(isHovered ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .opacity(device.isOnline ? 1 : 0.6)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(device.name), \(subtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Subtle press feedback for plain, non-remote buttons.
struct PressFeedbackStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
