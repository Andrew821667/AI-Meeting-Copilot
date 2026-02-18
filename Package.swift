// swift-tools-version: 6.2
import PackageDescription

let relaxedConcurrency: [SwiftSetting] = [
    .unsafeFlags([
        "-Xfrontend", "-strict-concurrency=minimal",
        "-Xfrontend", "-disable-actor-data-race-checks"
    ])
]

let package = Package(
    name: "AIMeetingCopilot",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "AIMeetingCopilotCore", targets: ["AIMeetingCopilotCore"]),
        .executable(name: "AIMeetingCopilot", targets: ["AIMeetingCopilotApp"])
    ],
    targets: [
        .target(
            name: "AIMeetingCopilotCore",
            path: "Sources/AIMeetingCopilotCore",
            swiftSettings: relaxedConcurrency
        ),
        .executableTarget(
            name: "AIMeetingCopilotApp",
            dependencies: ["AIMeetingCopilotCore"],
            path: "Sources/AIMeetingCopilotApp",
            swiftSettings: relaxedConcurrency
        ),
        .testTarget(
            name: "AIMeetingCopilotTests",
            dependencies: ["AIMeetingCopilotCore"],
            path: "Tests/AIMeetingCopilotTests",
            swiftSettings: relaxedConcurrency
        )
    ]
)
