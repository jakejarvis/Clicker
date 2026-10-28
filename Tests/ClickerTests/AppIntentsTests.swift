import ClickerCompanion
import Testing

@testable import ClickerApp
@testable import ClickerDemo

/// The Shortcuts actions against the demo TVs, run the way the system runs
/// them minus the lookup of the app's controller.
@Suite @MainActor struct AppIntentsTests {
    /// Long enough for the demo's Bonjour to report, short enough that a
    /// TV that never shows up does not hold a test for five seconds.
    private static func quickDiscovery(_ scenario: inout DemoScenario) {
        scenario.timings.intentDiscoveryTimeout = .milliseconds(300)
    }

    private func device(_ tv: DemoTV, in run: DemoRun) throws -> AppleTVEntity {
        AppleTVEntity(try #require(run.controller.devices.first { $0.id == tv.id }))
    }

    @Test func pressReachesTheSelectedTV() async throws {
        let run = try await DemoRun("ready")
        try await PressButtonIntent(button: .playPause).perform(on: run.controller)
        let session = try #require(run.world.session)
        #expect(await session.presses == [.playPause])
    }

    @Test func sleepAndWakeSendThePowerButtons() async throws {
        let run = try await DemoRun("ready")
        try await SleepAppleTVIntent(device: nil).perform(on: run.controller)
        try await WakeAppleTVIntent(device: nil).perform(on: run.controller)
        let session = try #require(run.world.session)
        #expect(await session.presses == [.sleep, .wake])
    }

    @Test func openAppLaunchesItAndRemembersIt() async throws {
        let run = try await DemoRun("ready")
        #expect(await run.connected())
        let netflix = TVAppEntity(id: "com.netflix.Netflix", name: "Netflix")
        try await OpenTVAppIntent(app: netflix).perform(on: run.controller)
        let session = try #require(run.world.session)
        #expect(await session.launchedBundleIDs == ["com.netflix.Netflix"])
        #expect(run.controller.recentApps.first?.id == "com.netflix.Netflix")
    }

    @Test func anActionNamingAnotherTVSwitchesToIt() async throws {
        let run = try await DemoRun("ready")
        let bedroom = try device(.bedroom, in: run)
        try await PressButtonIntent(button: .home, device: bedroom).perform(on: run.controller)
        #expect(run.controller.selectedDeviceID == DemoTV.bedroom.id)
        #expect(run.settings.selectedDeviceID == DemoTV.bedroom.id)
        let session = try #require(run.world.session)
        #expect(await session.presses == [.home])
    }

    @Test func switchSelectsTheTVAndNamesIt() async throws {
        let run = try await DemoRun("ready")
        let bedroom = try device(.bedroom, in: run)
        let name = try await SwitchAppleTVIntent(device: bedroom).perform(on: run.controller)
        #expect(name == DemoTV.bedroom.device.name)
        #expect(run.settings.selectedDeviceID == DemoTV.bedroom.id)
    }

    @Test func typingInsertsTextThenReturn() async throws {
        let run = try await DemoRun("typing")
        try await TypeTextIntent(text: " in 4K", pressReturn: true).perform(on: run.controller)
        let session = try #require(run.world.session)
        #expect(await session.insertedText == [" in 4K", "\n"])
        // The panel's field carries on from what the action typed.
        #expect(run.controller.tvText == "Nature documentaries in 4K")
    }

    @Test func typingWithoutAFocusedFieldFails() async throws {
        let run = try await DemoRun("ready")
        await #expect(throws: IntentError.noTextField) {
            try await TypeTextIntent(text: "hello").perform(on: run.controller)
        }
    }

    @Test func aPairedTVOffTheNetworkIsNotFound() async throws {
        let run = try await DemoRun("offline", Self.quickDiscovery)
        await #expect(throws: IntentError.notFound(DemoTV.livingRoom.device.name)) {
            try await PressButtonIntent(button: .select).perform(on: run.controller)
        }
    }

    @Test func anUnpairedTVAsksForPairing() async throws {
        let run = try await DemoRun("pair", Self.quickDiscovery)
        await #expect(throws: IntentError.notPaired(DemoTV.livingRoom.device.name)) {
            try await PressButtonIntent(button: .select).perform(on: run.controller)
        }
    }

    @Test func nothingSelectedFails() async throws {
        let run = try await DemoRun("searching", Self.quickDiscovery)
        await #expect(throws: IntentError.noAppleTV) {
            try await PressButtonIntent(button: .select).perform(on: run.controller)
        }
    }

    @Test func aFailedConnectIsTriedAgainAndReported() async throws {
        let run = try await DemoRun("connectionfailed")
        let message = RemoteController.connectFailedMessage(DemoTV.livingRoom.device.name)
        await #expect(throws: IntentError.connectFailed(message)) {
            try await PressButtonIntent(button: .select).perform(on: run.controller)
        }
    }

    @Test func theAppPickerKeepsTheLastFetchedAppsWhileDisconnected() async throws {
        let run = try await DemoRun("ready")
        #expect(await run.connected())
        #expect(run.settings.knownAppsByDevice[DemoTV.livingRoom.id]?.count == DemoScenario.apps.count)
        // The office TV is not paired, so selecting it leaves no apps to show.
        let office = try #require(run.controller.devices.first { $0.id == DemoTV.office.id })
        run.controller.select(office)
        #expect(run.controller.apps.isEmpty)
        #expect(Set(run.controller.knownApps.map(\.id)) == Set(DemoScenario.apps.map(\.id)))
    }
}

@Suite struct RemoteButtonTests {
    @Test func everyButtonButSleepAndWakeHasACase() {
        let pressable = Set(HIDCommand.allCases).subtracting([.sleep, .wake])
        #expect(Set(RemoteButton.allCases.map(\.command)) == pressable)
        #expect(RemoteButton.allCases.count == pressable.count)
    }

    /// The names are literals the build reads, so they can drift from the
    /// panel's; this keeps them the same.
    @Test(arguments: RemoteButton.allCases)
    @MainActor func titlesMatchThePanel(_ button: RemoteButton) throws {
        let representation = try #require(RemoteButton.caseDisplayRepresentations[button])
        #expect(String(localized: representation.title) == button.command.title)
    }
}
