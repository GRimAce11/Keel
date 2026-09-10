// swift-tools-version: 6.1
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
