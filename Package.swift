// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Timed",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(name: "TimedKit", targets: ["TimedKit"]),
        .executable(name: "time-manager-desktop", targets: ["TimedMacApp"]),
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
        // ElevenLabs Conversational AI — LiveKit WebRTC wrapper, Custom LLM support.
        .package(url: "https://github.com/elevenlabs/elevenlabs-swift-sdk", from: "2.0.0"),
    ],
    targets: [
        // Multiplatform-future library: Core/, Features/, Resources/.
        // AppKit imports gated with #if canImport(AppKit) where unavoidable.
        // For now this builds on macOS only; iOS readiness lands in Steps 3-5.
        .target(
            name: "TimedKit",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Supabase",               package: "supabase-swift"),
                .product(name: "MSAL",                   package: "microsoft-authentication-library-for-objc"),
                .product(name: "GRDB",                   package: "GRDB.swift"),
                .product(name: "USearch",                package: "usearch"),
                .product(name: "ElevenLabs",             package: "elevenlabs-swift-sdk"),
            ],
            path: "Sources/TimedKit",
            // Resources/ is currently empty (.gitkeep only). Adding it back
            // when there are real resources to ship — Xcode 26 codesigns an
            // empty resource bundle as "bundle format unrecognized" and
            // breaks iOS sim builds.
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        // Thin Mac executable shim. Imports TimedKit, applies macOS-only Scene modifiers.
        // iOS gets its own app target in Step 5 (Timed.xcodeproj).
        .executableTarget(
            name: "TimedMacApp",
            dependencies: [
                "TimedKit",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            path: "Sources/TimedMacApp",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "TimedKitTests",
            dependencies: [
                "TimedKit",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests"
        ),
    ]
)
