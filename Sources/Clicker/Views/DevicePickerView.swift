import SwiftUI

struct DevicePickerView: View {
    let controller: RemoteController

    private var selection: Binding<String?> {
        Binding(
            get: { controller.selectedDeviceID },
            set: { newValue in
                guard let newValue, let device = controller.devices.first(where: { $0.id == newValue }) else { return }
                controller.select(device)
            }
        )
    }

    var body: some View {
        Picker("Apple TV", selection: selection) {
            if controller.devices.isEmpty {
                Text("No Apple TVs found").tag(String?.none)
            }
            ForEach(controller.devices) { device in
                Text(label(for: device)).tag(Optional(device.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .disabled(controller.devices.isEmpty)
        .help(controller.selectedDevice?.modelDisplayName ?? "Choose an Apple TV")
    }

    private func label(for device: AppleTVDevice) -> String {
        var text = device.name
        if !device.isOnline { text += " (offline)" }
        else if !controller.isPaired(device) { text += " (not paired)" }
        return text
    }
}
