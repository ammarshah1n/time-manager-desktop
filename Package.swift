// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "time-manager-desktop",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "time-manager-desktop",
            path: "Sources"
        ),
        .testTarget(
            name: "time-manager-desktopTests",
            dependencies: ["time-manager-desktop"],
            path: "Tests"
        ),
    ]
)
