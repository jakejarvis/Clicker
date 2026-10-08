import AppKit
import SwiftUI

/// The device selector: a full-width control showing the current Apple TV's
/// icon, name, model and state. Clicking it drops down a list of every known
/// device in the same style, with a checkmark on the current one. A custom
/// popover is used because system menus cannot show subtitles.
///
/// ⌥-clicking the control opens the same list in details mode, like the Wi-Fi
/// menu: each row is followed by its Bonjour TXT record and, for the connected
/// TV, where the session landed, with a Rescan action at the bottom. The mode
/// is decided when the control is clicked and stays until the popover closes.
struct DevicePickerMenu: View {
    let controller: RemoteController
    /// Non-nil while the popover is open. The mode rides on the item because
    /// an `isPresented` popover rendered the content with the previous
    /// `showsDetails` value when both changed in the same click.
    @State private var presentation: Presentation?

    private struct Presentation: Identifiable {
        let showsDetails: Bool
        var id: Bool { showsDetails }
    }

    private let shape = RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)

    var body: some View {
        Button {
            if presentation != nil {
                presentation = nil
                return
            }
            // The click's own flags cover synthetic events; the class property
            // covers a key held before the panel took the event.
            let flags = (NSApp.currentEvent?.modifierFlags ?? []).union(NSEvent.modifierFlags)
            presentation = Presentation(showsDetails: flags.contains(.option))
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
        }
        .buttonStyle(SurfaceButtonStyle(shape: shape, pressScale: 0.98))
        .disabled(controller.devices.isEmpty)
        .help("Choose an Apple TV. ⌥-click for details.")
        .accessibilityLabel("Apple TV: \(controller.selectedDevice?.name ?? "none selected")")
        .accessibilityHint("Opens the list of Apple TVs")
        .popover(item: $presentation, arrowEdge: .bottom) { presentation in
            DeviceListView(controller: controller, showsDetails: presentation.showsDetails) { device in
                controller.select(device)
                self.presentation = nil
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
    let showsDetails: Bool
    let onSelect: (AppleTVDevice) -> Void

    /// Details mode is wider so a UUID fits on one caption line.
    static let detailsWidth: CGFloat = PanelMetrics.width + 56

    /// Past this the rows scroll and Rescan stays pinned below them; a few
    /// TVs in details mode reach it, a plain list needs about ten.
    static let maxListHeight: CGFloat = 480

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(controller.devices) { device in
                        row(for: device)
                    }
                }
                .padding([.horizontal, .top], 6)
                .padding(.bottom, showsRescan ? 0 : 6)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: Self.maxListHeight)
            .fixedSize(horizontal: false, vertical: true)
            if showsRescan {
                Divider()
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                RescanRow(isRescanning: controller.browser.isRescanning) {
                    controller.rescan()
                }
                .padding([.horizontal, .bottom], 6)
            }
        }
        .frame(width: showsDetails ? Self.detailsWidth : MenuBarView.panelWidth - 28)
    }

    private var showsRescan: Bool { showsDetails && controller.demo == nil }

    @ViewBuilder
    private func row(for device: AppleTVDevice) -> some View {
        let isSelected = device.id == controller.selectedDeviceID
        let isConnected = isSelected && controller.connectionState == .connected
        DeviceRow(
            device: device,
            subtitle: subtitle(for: device),
            isSelected: isSelected,
            isConnected: isConnected,
            isPaired: controller.isPaired(device)
        ) {
            onSelect(device)
        }
        if showsDetails {
            DeviceDetailsView(
                device: device,
                connectionInfo: isConnected ? controller.connectionInfo : nil,
                powerState: isConnected ? controller.powerState : nil,
                mediaControlFlags: isConnected ? controller.mediaControlFlags : nil
            )
        }
    }

    private func subtitle(for device: AppleTVDevice) -> String {
        if device.id == controller.selectedDeviceID {
            return "\(device.shortModelName) · \(controller.selectedStateDescription)"
        }
        if !device.isOnline { return "\(device.shortModelName) · Offline" }
        // Unpaired rows carry a Pair badge, which already says it.
        return controller.isPaired(device) ? device.modelDisplayName : device.shortModelName
    }
}

/// Hover wash shared by the device rows and the Rescan row: the selection
/// fill with white content, like a menu item.
private struct PickerRowStyle: ViewModifier {
    let isHovered: Bool
    var verticalPadding: CGFloat = 7
    var cornerRadius: CGFloat = PanelMetrics.innerCornerRadius

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isHovered ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear))
            )
            .foregroundStyle(isHovered ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
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
            .modifier(PickerRowStyle(isHovered: isHovered))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .opacity(device.isOnline ? 1 : 0.6)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(device.name), \(subtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The ⌥-click lines under a device row: one `Label: value` caption per
/// known fact, middle-truncated with the full value as a tooltip.
private struct DeviceDetailsView: View {
    let device: AppleTVDevice
    let connectionInfo: ConnectionInfo?
    let powerState: PowerState?
    let mediaControlFlags: MediaControlFlags?

    /// Lines up with the row's text: 8pt row padding, 30pt icon, 10pt gap.
    static let leadingInset: CGFloat = 48

    private var lines: [(label: String, value: String)] {
        var lines: [(String, String)] = []
        if let model = device.model { lines.append(("Model", model)) }
        if let id = device.txt("rpMRtID") { lines.append(("ID", id)) }
        if let address = device.bluetoothAddress { lines.append(("Bluetooth", address)) }
        if let version = connectionInfo?.osVersion { lines.append(("tvOS", version)) }
        if let version = device.companionVersion { lines.append(("Protocol", version)) }
        if device.txt("rpFl") != nil {
            let names = device.flagDescriptions
            lines.append(
                ("Flags", names.isEmpty ? device.flagsHex : "\(device.flagsHex) (\(names.joined(separator: ", ")))"))
        }
        if !device.interfaces.isEmpty { lines.append(("Interface", device.interfaces.joined(separator: ", "))) }
        if let connectionInfo {
            lines.append(("Address", connectionInfo.addressDescription))
            lines.append(("Session", connectionInfo.sessionDescription))
        }
        if let powerState { lines.append(("Power", "\(powerState.title) (\(powerState.rawValue))")) }
        if let mediaControlFlags {
            let names = mediaControlFlags.descriptions
            let hex = String(format: "0x%03llX", mediaControlFlags.rawValue)
            lines.append(("Controls", names.isEmpty ? hex : "\(hex) (\(names.joined(separator: ", ")))"))
        }
        return lines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(lines, id: \.label) { line in
                (Text("\(line.label): ").foregroundStyle(.secondary) + Text(line.value))
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(line.value)
            }
        }
        .padding(.leading, Self.leadingInset)
        .padding(.trailing, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(device.isOnline ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }
}

/// Restarts Bonjour browsing; only shown in details mode. Sized like a
/// plain menu item rather than a device row, with a menu item's tighter
/// corners: the rows' 10pt radius on a 22pt row reads as a capsule.
private struct RescanRow: View {
    static let cornerRadius: CGFloat = 5

    let isRescanning: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        let style = PickerRowStyle(
            isHovered: isHovered && !isRescanning, verticalPadding: 3, cornerRadius: Self.cornerRadius)
        Button(action: action) {
            HStack(spacing: 6) {
                Group {
                    if isRescanning {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                    }
                }
                .frame(width: 16, height: 16)
                Text(isRescanning ? "Rescanning…" : "Rescan Network")
                    .font(.callout)
            }
            .modifier(style)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(isRescanning)
        .onHover { isHovered = $0 }
        .help("Ask the network again for Apple TVs")
    }
}
