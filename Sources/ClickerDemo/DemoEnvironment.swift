import ClickerApp
import ClickerCompanion
import Foundation

/// Puts the app together around a scenario's made-up Apple TVs.
enum DemoEnvironment {
    static func make(for scenario: DemoScenario) -> AppEnvironment {
        let world = DemoWorld(scenario: scenario)
        return AppEnvironment(
            makeDependencies: {
                Log.remote.info("Demo mode: \(scenario.name, privacy: .public)")
                showDemoClientName()
                return world.dependencies()
            },
            opensPanelAtLaunch: true,
            didLaunch: { controller, updates in
                if let version = scenario.pendingUpdateVersion { updates.pendingUpdateVersion = version }
                // The panel opens half a second after launch; the steps wait
                // for it so popovers have an anchor and the clickpad has
                // taken its focus.
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    await world.play(on: controller)
                }
            }
        )
    }

    /// Shows the demo name in Settings without writing it anywhere: the
    /// argument domain is volatile and outranks the saved name.
    private static func showDemoClientName() {
        let defaults = UserDefaults.standard
        var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments[IdentityStore.clientNameKey] = DemoScenario.clientName
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }
}
