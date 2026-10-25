import AppKit
import ClickerCompanion
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
    /// The popover's item lives on the controller (`devicePickerPresentation`),
    /// like the Apps picker's flag: the popover goes with the panel when it
    /// hides, but view state would not, so the next open found it still set.
    @Bindable var controller: RemoteController

    private let shape = RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)

    var body: some View {
        Button {
            if controller.devicePickerPresentation != nil {
                controller.devicePickerPresentation = nil
                return
            }
            // The click's own flags cover synthetic events; the class property
            // covers a key held before the panel took the event.
            let flags = (NSApp.currentEvent?.modifierFlags ?? []).union(NSEvent.modifierFlags)
            controller.devicePickerPresentation = DevicePickerPresentation(showsDetails: flags.contains(.option))
        } label: {
            HStack(spacing: 10) {
                DeviceIcon(device: controller.selectedDevice, isConnected: controller.connectionState == .connected)
                VStack(alignment: .leading, spacing: 1) {
                    Text(controller.selectedDevice?.name ?? String(localized: "Choose an Apple TV"))
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    subtitle
                        .font(.caption)
                        .foregroundStyle(.glassSecondary)
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
        .help("Choose an Apple TV. Option-click for details.")
        .accessibilityLabel(
            controller.selectedDevice.map { String(localized: "Apple TV: \($0.name)") }
                ?? String(localized: "Apple TV: none selected")
        )
        // The label replaces the subtitle, so its state is read as the value.
        .accessibilityValue(accessibilityStatus)
        .accessibilityHint("Opens the list of Apple TVs")
        .popover(item: $controller.devicePickerPresentation, arrowEdge: .bottom) { presentation in
            DeviceListView(controller: controller, showsDetails: presentation.showsDetails) { device in
                controller.select(device)
                controller.devicePickerPresentation = nil
            }
            .popoverAppearance()
        }
    }

    /// The subtitle in words, for VoiceOver.
    private var accessibilityStatus: String {
        if let device = controller.selectedDevice {
            return String(localized: "\(device.shortModelName), \(controller.selectedStateDescription)")
        }
        let online = controller.devices.count(where: \.isOnline)
        return online > 0 ? String(localized: "\(online) found") : String(localized: "Searching")
    }

    @ViewBuilder
    private var subtitle: some View {
        // Paired TVs that are offline are listed but not "found".
        let online = controller.devices.count(where: \.isOnline)
        if let device = controller.selectedDevice {
            // A long state ("Connection failed") would cut the model down to
            // "Apple…"; drop the model instead of truncating it.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    Text(device.shortModelName)
                    Text(verbatim: "·")
                    Text(controller.selectedStateDescription)
                }
                Text(controller.selectedStateDescription)
                    .truncationMode(.tail)
            }
        } else if online > 0 {
            Text("\(online) found")
        } else {
            HStack(spacing: 5) {
                Spinner(size: 11)
                Text("Searching…")
            }
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

/// Arrow keys move the highlight and Return picks the highlighted TV, like
/// the Apps picker. The panel stays the key window under the popover, so the
/// keys ride a local monitor installed while the list is up (the clickpad
/// stands down meanwhile) and Esc stays with the panel's own monitor.
private struct DeviceListView: View {
    let controller: RemoteController
    let showsDetails: Bool
    let onSelect: (AppleTVDevice) -> Void

    @State private var keyMonitor: Any?
    @State private var highlightedDeviceID: String?
    /// Set only by the arrow keys, so the list scrolls to follow the
    /// keyboard but never jumps under the pointer.
    @State private var keyboardDeviceID: String?

    /// Details mode is wider so a UUID fits on one caption line.
    static let detailsWidth: CGFloat = PanelMetrics.width + 56

    /// Past this the rows scroll and Rescan stays pinned below them; a few
    /// TVs in details mode reach it, a plain list needs about ten.
    static let maxListHeight: CGFloat = 480

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(controller.devices) { device in
                            row(for: device)
                        }
                    }
                    .padding([.horizontal, .top], 6)
                    .padding(.bottom, showsDetails ? 0 : 6)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: Self.maxListHeight)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: keyboardDeviceID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
            if showsDetails {
                Divider()
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                RescanRow(isRescanning: controller.discovery.isRescanning) {
                    controller.rescan()
                }
                .padding([.horizontal, .bottom], 6)
            }
        }
        .frame(width: showsDetails ? Self.detailsWidth : MenuBarView.panelWidth - 28)
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: removeKeyMonitor)
    }

    @ViewBuilder
    private func row(for device: AppleTVDevice) -> some View {
        let isSelected = device.id == controller.selectedDeviceID
        let isConnected = isSelected && controller.connectionState == .connected
        DeviceRow(
            device: device,
            subtitle: subtitle(for: device),
            isSelected: isSelected,
            isConnected: isConnected,
            isPaired: controller.isPaired(device),
            isHighlighted: device.id == highlightedDeviceID
        ) {
            onSelect(device)
        } onHover: { hovering in
            if hovering {
                highlightedDeviceID = device.id
            } else if highlightedDeviceID == device.id {
                highlightedDeviceID = nil
            }
        }
        .id(device.id)
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
        if !device.isOnline { return "\(device.shortModelName) · \(String(localized: "Offline"))" }
        // Unpaired rows carry a Pair badge, which already says it.
        return controller.isPaired(device) ? device.modelDisplayName : device.shortModelName
    }

    // MARK: - Keys

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                switch event.keyCode {
                case 126: return moveHighlight(by: -1)
                case 125: return moveHighlight(by: 1)
                case 36, 76:  // Return, keypad Enter
                    guard let device = controller.devices.first(where: { $0.id == highlightedDeviceID }) else {
                        return false
                    }
                    onSelect(device)
                    return true
                default: return false
                }
            }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// From no highlight, Down starts at the top and Up at the bottom.
    private func moveHighlight(by offset: Int) -> Bool {
        let devices = controller.devices
        guard !devices.isEmpty else { return false }
        let next: Int
        if let current = devices.firstIndex(where: { $0.id == highlightedDeviceID }) {
            next = min(max(current + offset, 0), devices.count - 1)
        } else {
            next = offset > 0 ? 0 : devices.count - 1
        }
        highlightedDeviceID = devices[next].id
        keyboardDeviceID = devices[next].id
        return true
    }
}

/// Hover wash shared by the device rows and the Rescan row: the highlight
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
                    .fill(isHovered ? AnyShapeStyle(.rowHighlight) : AnyShapeStyle(.clear))
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
    /// Hovered, or reached with the arrow keys.
    let isHighlighted: Bool
    let action: () -> Void
    let onHover: (Bool) -> Void

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
                        .foregroundStyle(
                            isHighlighted ? AnyShapeStyle(.white.opacity(0.85)) : .glassSecondary
                        )
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : AnyShapeStyle(Color.accentColor))
                } else if !isPaired, device.isOnline {
                    Text("Pair", comment: "Badge on an Apple TV that isn't paired yet")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }
            .modifier(PickerRowStyle(isHovered: isHighlighted))
        }
        .buttonStyle(.plain)
        // The arrows and Return are the list's keys (`DeviceListView`). A
        // focusable row took focus when the list opened, unseen, and Space
        // picked it whatever the highlight said.
        .focusable(false)
        .focusEffectDisabled()
        .opacity(device.isOnline ? 1 : 0.6)
        .onHover(perform: onHover)
        .accessibilityLabel(Text(verbatim: "\(device.name), \(subtitle)"))
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
        if let model = device.model { lines.append((String(localized: "Model"), model)) }
        if let id = device.txt("rpMRtID") { lines.append((String(localized: "ID"), id)) }
        if let address = device.bluetoothAddress { lines.append(("Bluetooth", address)) }
        if let version = connectionInfo?.osVersion { lines.append(("tvOS", version)) }
        if let version = device.companionVersion { lines.append((String(localized: "Protocol"), version)) }
        if device.txt("rpFl") != nil {
            let names = device.flagDescriptions
            lines.append(
                (
                    String(localized: "Flags"),
                    names.isEmpty ? device.flagsHex : "\(device.flagsHex) (\(names.joined(separator: ", ")))"
                ))
        }
        if !device.interfaces.isEmpty {
            lines.append((String(localized: "Interface"), device.interfaces.joined(separator: ", ")))
        }
        if let connectionInfo {
            lines.append((String(localized: "Address"), connectionInfo.addressDescription))
            lines.append((String(localized: "Session"), connectionInfo.sessionDescription))
        }
        if let powerState {
            lines.append((String(localized: "Power"), "\(powerState.title) (\(powerState.rawValue))"))
        }
        if let mediaControlFlags {
            let names = mediaControlFlags.descriptions
            let hex = String(format: "0x%03llX", mediaControlFlags.rawValue)
            lines.append(
                (String(localized: "Controls"), names.isEmpty ? hex : "\(hex) (\(names.joined(separator: ", ")))"))
        }
        return lines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(lines, id: \.label) { line in
                (Text("\(line.label): ").foregroundStyle(.glassSecondary) + Text(line.value))
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
                        Spinner(size: 11)
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
        .focusable(false)
        .focusEffectDisabled()
        .disabled(isRescanning)
        .onHover { isHovered = $0 }
        .help("Search the network again")
    }
}
