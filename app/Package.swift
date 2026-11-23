// swift-tools-version: 6.2
// NoSpeaker: the window app. HapticEngine drives the trackpad motors (no UI, nonisolated); NoSpeaker is the
// SwiftUI app around it (main actor by default).
import PackageDescription

let package = Package(
    name: "NoSpeaker",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "HapticEngine", path: "Sources/HapticEngine"),
        .testTarget(name: "HapticEngineTests", dependencies: ["HapticEngine"], path: "Tests/HapticEngineTests"),
        .executableTarget(
            name: "NoSpeaker",
            dependencies: ["HapticEngine"],
            path: "Sources/NoSpeaker",
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
    ]
)
