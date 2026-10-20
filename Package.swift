// swift-tools-version: 6.2
import PackageDescription

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
        // The app as shipped: a thin entry point that runs ClickerApp against
        // the real network, keychain and defaults.
        .executableTarget(
            name: "Clicker",
            dependencies: ["ClickerApp"],
            path: "Sources/Clicker",
            swiftSettings: concurrencySettings + [.defaultIsolation(MainActor.self)]
        ),
        // The development build: the same app with `--demo [scenario]`, which
        // swaps in made-up Apple TVs. Nothing in Clicker depends on it.
        .executableTarget(
            name: "ClickerDemo",
            dependencies: ["ClickerApp", "ClickerCompanion"],
            path: "Sources/ClickerDemo",
            swiftSettings: concurrencySettings + [.defaultIsolation(MainActor.self)]
        ),
        // The app: UI, stores, discovery. Main actor by default, like any app
        // module; code that runs elsewhere says `nonisolated`.
        .target(
            name: "ClickerApp",
            dependencies: [
                "ClickerCompanion",
                .product(name: "Sparkle", package: "Sparkle", condition: .when(traits: ["Sparkle"])),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/ClickerApp",
            swiftSettings: concurrencySettings + [.defaultIsolation(MainActor.self)]
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
            dependencies: ["ClickerApp", "ClickerDemo", "ClickerCompanion"],
            path: "Tests/ClickerTests",
            swiftSettings: concurrencySettings
        ),
        .testTarget(
            name: "ClickerCompanionTests",
            dependencies: ["ClickerCompanion", .product(name: "BigInt", package: "BigInt")],
            path: "Tests/ClickerCompanionTests",
            swiftSettings: concurrencySettings
        ),
    ]
)
