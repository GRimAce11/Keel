// swift-tools-version: 6.0
//
// 6.0 rather than 6.1, deliberately. The manifest uses nothing 6.1 added, and
// the tools version sets the floor on who can build Keel at all: 6.1 means
// Xcode 16.3, which cannot be installed before macOS 15. Anyone on Sonoma
// following the install instructions got "Xcode 16.3 cannot be installed on
// macOS 14" instead of a working binary. 6.0 means Xcode 16.0 and still
// defaults to the Swift 6 language mode, so nothing is given up for it.
import PackageDescription

let package = Package(
    name: "Keel",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        // keel is a command line tool. Install it with Homebrew, or build from
        // source: swift build -c release && cp .build/release/keel /usr/local/bin/
        .executable(name: "keel", targets: ["keel"]),

        // The engine, if you want to drive Keel programmatically.
        .library(name: "KeelKit", targets: ["KeelKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        // Structural analysis of Swift source. Keel itself may take a
        // dependency; the no-dependency rule covers what it *generates*.
        // Regex cannot reliably tell a conformance from a comment.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.1"),
    ],
    targets: [
        // Thin CLI shell. All logic lives in KeelKit so it stays testable —
        // SwiftPM cannot import an executable target from a test target.
        .executableTarget(
            name: "keel",
            dependencies: [
                "KeelKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "KeelKit",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            resources: [
                // Copied verbatim, so templates ship inside the binary and
                // generation never needs the network. Every file carries a
                // .tpl suffix, which also stops SwiftPM mistaking a template
                // for a compilable source file.
                .copy("Resources/Templates"),
            ]
        ),
        .testTarget(
            name: "KeelTests",
            dependencies: ["KeelKit"]
        ),
    ]
)
