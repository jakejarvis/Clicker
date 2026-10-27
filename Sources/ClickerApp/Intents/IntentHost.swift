import Foundation

/// What a Shortcuts action reaches in the running app: the controller and
/// a way to show the panel. `AppDelegate` installs both at launch. The
/// system may launch Clicker just to run an action, and an action can
/// arrive while the launch is still under way, so `current()` waits a
/// moment for them.
enum IntentHost {
    static var controller: RemoteController?
    static var openPanel: () -> Void = {}

    static func current() async throws -> RemoteController {
        for _ in 0..<50 {
            if let controller { return controller }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw IntentError.notRunning
    }

    /// Runs an action's work, turning what the session throws into an
    /// error the action can show. `IntentError`s pass through as they are.
    static func translatingErrors(_ body: () async throws -> Void) async throws {
        do {
            try await body()
        } catch let error as IntentError {
            throw error
        } catch is RemoteController.CommandNotSent {
            throw IntentError.connectFailed("Clicker lost the connection to the Apple TV.")
        } catch {
            throw IntentError.commandFailed(error.localizedDescription)
        }
    }
}
