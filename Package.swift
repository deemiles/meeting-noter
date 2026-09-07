// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MeetingNoter",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "MeetingNoter",
            path: "Sources/MeetingNoter",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
