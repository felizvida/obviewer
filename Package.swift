// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Obviewer",
    platforms: [
        .macOS(.v14),
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
            name: "ObviewerMacApp",
            targets: ["ObviewerMacApp"]
        ),
        .executable(
            name: "ObviewerFixtureTool",
            targets: ["ObviewerFixtureTool"]
        ),
        .executable(
            name: "ObviewerDocsTool",
            targets: ["ObviewerDocsTool"]
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
            name: "ObviewerMacApp",
            dependencies: ["ObviewerCore"]
        ),
        .executableTarget(
            name: "ObviewerFixtureTool",
            dependencies: ["ObviewerFixtureSupport"]
        ),
        .executableTarget(
            name: "ObviewerDocsTool",
            dependencies: ["ObviewerMacApp", "ObviewerFixtureSupport"]
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
            name: "ObviewerMacAppTests",
            dependencies: ["ObviewerMacApp", "ObviewerCore", "ObviewerFixtureSupport"]
        ),
    ]
)
