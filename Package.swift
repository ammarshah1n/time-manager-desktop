// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "time-manager-desktop",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        // State management — TCA (The Composable Architecture)
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.15.0"),
        // Supabase Swift client (Auth, Database, Realtime, Storage)
        .package(url: "https://github.com/supabase/supabase-swift", from: "2.5.0"),
        // Microsoft Authentication Library — Graph API OAuth2
        .package(url: "https://github.com/AzureAD/microsoft-authentication-library-for-objc", from: "1.4.0"),
        // GRDB.swift — SQLite for offline operation queue
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        // USearch — local HNSW vector search
        .package(url: "https://github.com/unum-cloud/usearch", from: "2.16.0"),
        // Swift Testing framework (for CLT environments without Xcode)
        .package(url: "https://github.com/swiftlang/swift-testing", from: "0.12.0"),
    ],
    targets: [
        .executableTarget(
            name: "time-manager-desktop",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Supabase",               package: "supabase-swift"),
                .product(name: "MSAL",                   package: "microsoft-authentication-library-for-objc"),
                .product(name: "GRDB",                   package: "GRDB.swift"),
                .product(name: "USearch",                package: "usearch"),
            ],
            path: "Sources",
            exclude: ["Legacy"],
            resources: [
                .copy("Resources"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "time-manager-desktopTests",
            dependencies: [
                "time-manager-desktop",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests"
        ),
    ]
)
