// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Obviewer",
    platforms: [
        // macOS 26 and later only (decision of November 15, 2026).
        .macOS("26.0"),
    ],
    products: [
        .library(
            name: "ObviewerCore",
            targets: ["ObviewerCore"]
        ),
        .library(
            name: "ObviewerFixtureSupport",
            targets: ["ObviewerFixtureSupport"]
        ),
        .library(
            name: "ObviewerReaderKit",
            targets: ["ObviewerReaderKit"]
        ),
        .library(
            name: "ObviewerMacApp",
            targets: ["ObviewerMacApp"]
        ),
        .executable(
            name: "ObviewerFixtureTool",
            targets: ["ObviewerFixtureTool"]
        ),
        .executable(
            name: "ObviewerBenchmarkTool",
            targets: ["ObviewerBenchmarkTool"]
        ),
        .executable(
            name: "Obviewer",
            targets: ["Obviewer"]
        ),
    ],
    targets: [
        .target(
            name: "ObviewerCore"
        ),
        .target(
            name: "ObviewerFixtureSupport"
        ),
        .target(
            name: "ObviewerReaderKit",
            dependencies: ["ObviewerCore"],
            resources: [
                .copy("Resources/Reader"),
            ]
        ),
        .target(
            name: "ObviewerMacApp",
            dependencies: ["ObviewerCore", "ObviewerReaderKit"]
        ),
        .executableTarget(
            name: "ObviewerFixtureTool",
            dependencies: ["ObviewerFixtureSupport"]
        ),
        .executableTarget(
            name: "ObviewerBenchmarkTool",
            dependencies: ["ObviewerCore", "ObviewerFixtureSupport"]
        ),
        .executableTarget(
            name: "Obviewer",
            dependencies: ["ObviewerMacApp"]
        ),
        .testTarget(
            name: "ObviewerCoreTests",
            dependencies: ["ObviewerCore", "ObviewerFixtureSupport"]
        ),
        .testTarget(
            name: "ObviewerReaderKitTests",
            dependencies: ["ObviewerReaderKit", "ObviewerCore"]
        ),
        .testTarget(
            name: "ObviewerMacAppTests",
            dependencies: ["ObviewerMacApp", "ObviewerReaderKit", "ObviewerCore", "ObviewerFixtureSupport"]
        ),
    ]
)
