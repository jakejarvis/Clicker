import AppKit
import Observation
import Sparkle

/// Sparkle updates, adapted to an app that lives in the menu bar.
///
/// Background checks use Sparkle's gentle reminders: unless Sparkle can show
/// the alert in immediate focus (right after launch), the app shows its own
/// indicator (a dot on the status item and an Update button in the panel) and
/// the alert only appears when the user asks for it. While a Sparkle window is
/// up the app becomes `.regular` so the window comes forward with a Dock icon,
/// then returns to the activation policy it launched with.
@MainActor
@Observable
final class UpdateController: NSObject {
    /// False for development builds, whose Info.plist has no `SUFeedURL`.
    let isEnabled: Bool
    private(set) var canCheckForUpdates = false
    /// Version of an update found in the background that the user hasn't seen.
    private(set) var pendingUpdateVersion: String?
    private(set) var lastUpdateCheckDate: Date?
    /// Called before Sparkle shows a window; the panel floats at pop-up menu
    /// level and would otherwise cover it.
    @ObservationIgnored var onWillPresent: () -> Void = {}

    @ObservationIgnored private let launchPolicy: NSApplication.ActivationPolicy
    @ObservationIgnored private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: self
    )
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    init(launchPolicy: NSApplication.ActivationPolicy) {
        self.launchPolicy = launchPolicy
        isEnabled = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        super.init()
    }

    func start() {
        guard isEnabled else { return }
        let updater = updaterController.updater
        let options: NSKeyValueObservingOptions = [.initial, .new]
        canCheckObservation = updater.observe(\.canCheckForUpdates, options: options) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
        updaterController.startUpdater()
        lastUpdateCheckDate = updaterController.updater.lastUpdateCheckDate
    }

    #if DEMO
        /// Shows the gentle-reminder state (`--demo update`) without a feed:
        /// the status item dot, the footer button and the "Update to" menu items.
        func previewPendingUpdate(_ version: String) {
            pendingUpdateVersion = version
        }
    #endif

    /// User-initiated check. Also brings a pending update's alert forward.
    func checkForUpdates() {
        guard isEnabled else { return }
        presentForUpdate()
        updaterController.checkForUpdates(nil)
    }

    // Sparkle persists this itself; only set it in response to the user.

    var automaticallyChecksForUpdates: Bool {
        get { isEnabled && updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    private func presentForUpdate() {
        onWillPresent()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    private func endUpdateSession() {
        pendingUpdateVersion = nil
        NSApp.setActivationPolicy(launchPolicy)
    }
}

extension UpdateController: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if let error = error as NSError?,
            error.code != Int(SUError.noUpdateError.rawValue),
            error.code != Int(SUError.installationCanceledError.rawValue)
        {
            Log.updates.error("Update cycle failed: \(String(describing: error), privacy: .public)")
        }
        lastUpdateCheckDate = updater.lastUpdateCheckDate
        // Backstop for "up to date" and error alerts, which may not end a
        // user driver session. A pending reminder keeps its session open.
        if pendingUpdateVersion == nil {
            NSApp.setActivationPolicy(launchPolicy)
        }
    }
}

// The user driver delegate protocol isn't annotated for the main actor, but
// Sparkle only calls it on the main thread.
extension UpdateController: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        if handleShowingUpdate {
            presentForUpdate()
        } else {
            pendingUpdateVersion = update.displayVersionString
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        pendingUpdateVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        endUpdateSession()
    }
}
