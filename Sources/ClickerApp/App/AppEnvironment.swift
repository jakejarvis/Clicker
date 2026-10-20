/// How a run of the app is put together. The shipped Clicker runs `live`;
/// the ClickerDemo target builds one around made-up Apple TVs for `--demo`.
package struct AppEnvironment {
    /// What `RemoteController` talks to. Called once, at launch.
    package var makeDependencies: () -> RemoteDependencies
    /// Opens the panel at every launch, so a screenshot needs no click,
    /// instead of only on the first.
    package var opensPanelAtLaunch: Bool
    /// Runs once at launch, after the controller has started.
    package var didLaunch: (RemoteController, UpdateController) -> Void

    package init(
        makeDependencies: @escaping () -> RemoteDependencies,
        opensPanelAtLaunch: Bool,
        didLaunch: @escaping (RemoteController, UpdateController) -> Void
    ) {
        self.makeDependencies = makeDependencies
        self.opensPanelAtLaunch = opensPanelAtLaunch
        self.didLaunch = didLaunch
    }

    package static var live: AppEnvironment {
        AppEnvironment(makeDependencies: { .live }, opensPanelAtLaunch: false, didLaunch: { _, _ in })
    }
}
