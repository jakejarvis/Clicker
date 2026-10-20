import Testing

@testable import ClickerApp
@testable import ClickerDemo

/// A `RemoteController` wired to a demo scenario's made-up Apple TVs, the
/// way `--demo` runs the app, with pair-setup taking no time. The scenario's
/// steps have been played by the time `init` returns.
@MainActor
struct DemoRun {
    let controller: RemoteController
    let world: DemoWorld
    /// What the controller has "saved" for the next launch.
    let settings: DemoSettings

    init(_ name: String, _ configure: (inout DemoScenario) -> Void = { _ in }) async throws {
        var scenario = try #require(DemoScenario.named(name))
        configure(&scenario)
        world = DemoWorld(scenario: scenario, latency: .zero)
        let dependencies = world.dependencies()
        settings = try #require(dependencies.settings as? DemoSettings)
        controller = RemoteController(dependencies: dependencies)
        controller.start()
        await world.play(on: controller)
    }

    /// Waits for the session to come up and the TV's apps to arrive.
    func connected() async -> Bool {
        await eventually { controller.connectionState == .connected && !controller.apps.isEmpty }
    }
}

/// Polls `condition` until it holds or two seconds pass; the controller
/// reaches most states through a few task hops.
@MainActor
func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
