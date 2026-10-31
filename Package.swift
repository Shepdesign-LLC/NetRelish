// swift-tools-version: 6.0
// PantryKit — the Pantry core as a SwiftPM package, groundwork for the iOS Duo
// companion (1.1, Q1 2027). ADR 0009.
//
// Path-based over Sources/Pantry: the exact files the Mac app's `Pantry` framework
// target compiles (NetRelish.xcodeproj, generated from project.yml). No file moves,
// no project changes — the Mac build does not know this manifest exists. The library
// is named PantryKit because the xcodeproj already owns the names `Pantry` and
// `PantryTests`.
//
// Platforms: macOS 27 matches the app's locked OS floor; iOS 17 is the module's
// technical floor — WKWebsiteDataStore(forIdentifier:) in Store/JarProfile.swift is
// an iOS 17+ API, and everything else in the module is Foundation/GRDB/CryptoKit/
// AppIntents, available earlier. Duo may raise the iOS floor when it ships.

import PackageDescription

let package = Package(
    name: "PantryKit",
    platforms: [
        .macOS("27.0"),
        .iOS("17.0"),
    ],
    products: [
        .library(name: "PantryKit", targets: ["PantryKit"]),
    ],
    dependencies: [
        // Same range as project.yml — the workspace pins 7.11.1; see docs/PantryKit_Groundwork.md.
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "PantryKit",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            path: "Sources/Pantry"
        ),
        .testTarget(
            name: "PantryKitTests",
            // GRDB declared here too: the tests import it directly (Database, fetch APIs).
            dependencies: ["PantryKit", .product(name: "GRDB", package: "GRDB.swift")],
            path: "Tests/PantryKitTests"
        ),
    ]
)
