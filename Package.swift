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
