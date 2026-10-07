import SwiftUI

struct AppsMenu: View {
    let controller: RemoteController

    var body: some View {
        Menu {
            if controller.apps.isEmpty {
                Text(controller.isLoadingApps ? "Loading…" : "No apps loaded")
            } else {
                ForEach(controller.apps) { app in
                    Button(app.name) { controller.launch(app) }
                }
            }
            Divider()
            Button("Refresh") { controller.refreshApps() }
                .disabled(controller.isLoadingApps)
        } label: {
            Label("Apps", systemImage: "square.grid.2x2")
        }
        .disabled(controller.connectionState != .connected)
        .help("Open an app on the Apple TV")
    }
}

struct PowerMenu: View {
    let controller: RemoteController

    var body: some View {
        Menu {
            Button("Wake", systemImage: "sun.max") { controller.press(.wake) }
            Button("Sleep", systemImage: "moon") { controller.press(.sleep) }
            Divider()
            Button("Screen Saver", systemImage: "sparkles.tv") { controller.press(.screensaver) }
            Button("Control Center", systemImage: "switch.2") { controller.press(.pageDown) }
            Button("Guide", systemImage: "list.bullet.rectangle") { controller.press(.guide) }
        } label: {
            Label("Power", systemImage: "power")
        }
        .disabled(controller.connectionState != .connected)
        .help("Apple TV is \(controller.powerState.title.lowercased())")
    }
}
