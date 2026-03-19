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
            name: "ObviewerMacApp",
            targets: ["ObviewerMacApp"]
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
            name: "ObviewerMacApp",
            dependencies: ["ObviewerCore"]
        ),
        .executableTarget(
            name: "Obviewer",
            dependencies: ["ObviewerMacApp"]
        ),
        .testTarget(
            name: "ObviewerCoreTests",
            dependencies: ["ObviewerCore"]
        ),
        .testTarget(
            name: "ObviewerMacAppTests",
            dependencies: ["ObviewerMacApp", "ObviewerCore"]
        ),
    ]
)
