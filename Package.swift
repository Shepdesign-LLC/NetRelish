// swift-tools-version: 6.4
// NetRelish — design-system package (P0). The Xcode project (Prompt 2) folds
// Sources/UI into the app target; until then this package is how it builds.
import PackageDescription

let package = Package(
    name: "NetRelish",
    platforms: [.macOS(.v27)],
    products: [
        .library(name: "NRUI", targets: ["NRUI"]),
        .executable(name: "DesignKit", targets: ["DesignKit"]),
    ],
    targets: [
        // Sources/UI — tokens, symbols, shapes. Tokens.swift and Symbols.swift
        // are GENERATED from /design; never hand-edit them.
        .target(
            name: "NRUI",
            path: "Sources/UI",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // DEBUG-only Design Kit window, standalone until the app exists.
        .executableTarget(
            name: "DesignKit",
            dependencies: ["NRUI"],
            path: "Sources/DesignKitApp",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "NRUITests",
            dependencies: ["NRUI"],
            path: "Tests/NRUITests",
            exclude: ["Fixtures"],   // read by path in tests, not bundled
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
