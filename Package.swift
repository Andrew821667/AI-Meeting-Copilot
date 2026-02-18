// swift-tools-version: 6.2
import PackageDescription

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
            path: "Sources/AIMeetingCopilotCore"
        ),
        .executableTarget(
            name: "AIMeetingCopilotApp",
            dependencies: ["AIMeetingCopilotCore"],
            path: "Sources/AIMeetingCopilotApp"
        ),
        .testTarget(
            name: "AIMeetingCopilotTests",
            dependencies: ["AIMeetingCopilotCore"],
            path: "Tests/AIMeetingCopilotTests"
        )
    ]
)
