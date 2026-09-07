// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MeetingNoter",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "MeetingNoter",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/MeetingNoter",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
