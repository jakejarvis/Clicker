import AppKit
import ClickerCompanion
import Observation

#if Sparkle
    import Sparkle
#endif

/// Sparkle updates, adapted to an app that lives in the menu bar.
///
/// Background checks use Sparkle's gentle reminders: unless Sparkle can show
/// the alert in immediate focus (right after launch), the app shows its own
/// indicator (an inline notice with an Update button under the remote, and
/// Update to X… in both menus) and the alert only appears when the user asks
/// for it. While a Sparkle window is
/// up the app becomes `.regular` so the window comes forward with a Dock icon,
/// then returns to the activation policy it launched with.
///
/// The Mac App Store build is compiled without the `Sparkle` trait: the store
/// updates the app and allows no other updater (rule 2.4.5(vii)), so Sparkle
/// is left out entirely and the update UI disappears with `isIncluded`.
@Observable
package final class UpdateController: NSObject {
    #if Sparkle
        static let isIncluded = true
    #else
        static let isIncluded = false
    #endif

    /// False for the App Store build and for development builds, whose
    /// Info.plist has no `SUFeedURL`.
    let isEnabled: Bool
    private(set) var canCheckForUpdates = false
    /// Version of an update found in the background that the user hasn't
    /// seen. Set from outside only by the demo build's `update` scenario.
    package var pendingUpdateVersion: String?
    private(set) var lastUpdateCheckDate: Date?
    /// Called before Sparkle shows a window; the panel floats at pop-up menu
    /// level and would otherwise cover it.
    @ObservationIgnored var onWillPresent: () -> Void = {}

    @ObservationIgnored private let launchPolicy: NSApplication.ActivationPolicy
    #if Sparkle
        @ObservationIgnored private lazy var updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
    #endif

    init(launchPolicy: NSApplication.ActivationPolicy) {
        self.launchPolicy = launchPolicy
        isEnabled = Self.isIncluded && Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        super.init()
    }

    func start() {
        #if Sparkle
            guard isEnabled else { return }
            let updater = updaterController.updater
            let options: NSKeyValueObservingOptions = [.initial, .new]
            canCheckObservation = updater.observe(\.canCheckForUpdates, options: options) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
            }
            updaterController.startUpdater()
            lastUpdateCheckDate = updaterController.updater.lastUpdateCheckDate
        #endif
    }

    /// User-initiated check. Also brings a pending update's alert forward.
    func checkForUpdates() {
        #if Sparkle
            guard isEnabled else { return }
            presentForUpdate()
            updaterController.checkForUpdates(nil)
        #endif
    }

    // Sparkle persists this itself; only set it in response to the user.

    #if Sparkle
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
    #else
        var automaticallyChecksForUpdates: Bool {
            get { false }
            set {}
        }
    #endif
}

#if Sparkle

    extension UpdateController: SPUUpdaterDelegate {
        package func updater(
            _ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?
        ) {
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
        package var supportsGentleScheduledUpdateReminders: Bool { true }

        /// Never: a scheduled find only sets `pendingUpdateVersion`, so the panel
        /// shows its notice and Sparkle's alert waits for a click on Update.
        /// Immediate focus includes "just launched", which with Open at Login
        /// would put the alert in front of whatever the user is doing.
        package func standardUserDriverShouldHandleShowingScheduledUpdate(
            _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
        ) -> Bool {
            false
        }

        package func standardUserDriverWillHandleShowingUpdate(
            _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
        ) {
            if handleShowingUpdate {
                presentForUpdate()
            } else {
                pendingUpdateVersion = update.displayVersionString
            }
        }

        package func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
            pendingUpdateVersion = nil
        }

        package func standardUserDriverWillFinishUpdateSession() {
            endUpdateSession()
        }
    }
#endif
