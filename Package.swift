// swift-tools-version: 6.1
import PackageDescription

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
    ],
    targets: [
        .executableTarget(
            name: "Clicker",
            dependencies: [
                .product(name: "BigInt", package: "BigInt"),
                .product(name: "Sparkle", package: "Sparkle", condition: .when(traits: ["Sparkle"])),
            ],
            path: "Sources/Clicker"
        ),
        .testTarget(
            name: "ClickerTests",
            dependencies: ["Clicker"],
            path: "Tests/ClickerTests"
        ),
    ]
)
