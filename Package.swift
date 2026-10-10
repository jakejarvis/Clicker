// swift-tools-version: 6.0
import PackageDescription

// `--demo` (DemoScenario and the controller's canned state) is compiled into
// debug builds only. Release builds leave it out; script/package_app.sh
// --with-demo adds -DDEMO for the screenshot build.
let demoSettings: [SwiftSetting] = [.define("DEMO", .when(configuration: .debug))]

let package = Package(
    name: "Clicker",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/attaswift/BigInt.git", from: "6.0.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Clicker",
            dependencies: [
                .product(name: "BigInt", package: "BigInt"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Clicker",
            swiftSettings: demoSettings
        ),
        .testTarget(
            name: "ClickerTests",
            dependencies: ["Clicker"],
            path: "Tests/ClickerTests",
            swiftSettings: demoSettings
        ),
    ]
)
