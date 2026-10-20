// swift-tools-version: 6.2
import PackageDescription

// `--demo` (DemoScenario and the controller's canned state) is compiled into
// debug builds only. Release builds leave it out; script/package_app.sh
// --with-demo adds -DDEMO for the screenshot build.
let demoSettings: [SwiftSetting] = [.define("DEMO", .when(configuration: .debug))]

// Swift 6.2's approachable concurrency: a nonisolated async function runs on
// its caller's actor unless marked `@concurrent`, and a conformance of a
// main-actor type is main-actor isolated.
let concurrencySettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "Clicker",
    platforms: [.macOS(.v15)],
    traits: [
        // Off for the Mac App Store build, which the store updates.
        .trait(name: "Sparkle", description: "In-app updates through Sparkle."),
        .default(enabledTraits: ["Sparkle"]),
    ],
    dependencies: [
        .package(url: "https://github.com/attaswift/BigInt.git", from: "6.0.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "1.17.0"),
    ],
    targets: [
        // The app: UI, stores, discovery. Main actor by default, like any app
        // module; code that runs elsewhere says `nonisolated`.
        .executableTarget(
            name: "Clicker",
            dependencies: [
                "ClickerCompanion",
                .product(name: "Sparkle", package: "Sparkle", condition: .when(traits: ["Sparkle"])),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/Clicker",
            swiftSettings: demoSettings + concurrencySettings + [.defaultIsolation(MainActor.self)]
        ),
        // The Companion protocol: codecs, pairing crypto and the session
        // actors. Nonisolated by default, so callers decide where work runs.
        .target(
            name: "ClickerCompanion",
            dependencies: [.product(name: "BigInt", package: "BigInt")],
            path: "Sources/ClickerCompanion",
            swiftSettings: concurrencySettings
        ),
        .testTarget(
            name: "ClickerTests",
            dependencies: ["Clicker", "ClickerCompanion"],
            path: "Tests/ClickerTests",
            swiftSettings: demoSettings + concurrencySettings
        ),
        .testTarget(
            name: "ClickerCompanionTests",
            dependencies: ["ClickerCompanion", .product(name: "BigInt", package: "BigInt")],
            path: "Tests/ClickerCompanionTests",
            swiftSettings: concurrencySettings
        ),
    ]
)
