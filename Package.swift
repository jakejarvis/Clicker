// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clicker",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "Clicker",
            dependencies: [
                .product(name: "BigInt", package: "BigInt"),
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
