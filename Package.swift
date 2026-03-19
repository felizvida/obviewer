// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Obviewer",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "Obviewer",
            targets: ["Obviewer"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "Obviewer"
        ),
        .testTarget(
            name: "ObviewerTests",
            dependencies: ["Obviewer"]
        ),
    ]
)
