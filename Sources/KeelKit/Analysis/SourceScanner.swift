import Foundation

/// Summarises the Swift source in a project directory.
///
/// This reads imports and a small set of textual markers. It is deliberately
/// shallow: it answers "is this a SwiftUI codebase" without claiming to
/// understand the code. Structural questions — what conforms to what, which
/// types are ViewModels — need a real parser, which is a later phase.
struct SourceScanner {

    /// Directories that are never the project's own source.
    private static let excludedDirectories: Set<String> = [
        ".build", ".git", "DerivedData", "Pods", "Carthage",
        "node_modules", "build", ".swiftpm", "vendor",
    ]

    let root: URL

    func scan() -> SourceSummary {
        var fileCount = 0
        var lineCount = 0
        var markers: Set<String> = []

        for file in swiftFiles() {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            fileCount += 1
            lineCount += text.lazy.filter { $0 == "\n" }.count + 1

            for (marker, needles) in Self.markers where !markers.contains(marker) {
                if needles.contains(where: text.contains) {
                    markers.insert(marker)
                }
            }
        }

        return SourceSummary(
            swiftFileCount: fileCount,
            lineCount: lineCount,
            importsSwiftUI: markers.contains("swiftui"),
            importsUIKit: markers.contains("uikit"),
            usesObservationMacro: markers.contains("observable"),
            usesObservableObject: markers.contains("observableobject"),
            usesAsyncAwait: markers.contains("async"),
            usesCombine: markers.contains("combine"),
            usesSwiftData: markers.contains("swiftdata"),
            usesCoreData: markers.contains("coredata"),
            usesSwiftTesting: markers.contains("swifttesting"),
            usesXCTest: markers.contains("xctest")
        )
    }

    /// Marker name to the substrings that prove it.
    ///
    /// Import statements are matched with the trailing newline so `import
    /// UIKit` does not also match a file importing `UIKitCore`, and so a
    /// mention inside a comment is less likely to count.
    private static let markers: [String: [String]] = [
        "swiftui": ["import SwiftUI\n"],
        "uikit": ["import UIKit\n"],
        "combine": ["import Combine\n"],
        "swiftdata": ["import SwiftData\n"],
        "coredata": ["import CoreData\n"],
        "swifttesting": ["import Testing\n"],
        "xctest": ["import XCTest\n"],
        "observable": ["@Observable"],
        "observableobject": ["ObservableObject"],
        "async": ["async ", "await "],
    ]

    func swiftFiles() -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [URL] = []
        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            if isDirectory {
                // Skipping the whole subtree rather than filtering afterwards:
                // Pods and DerivedData can hold far more source than the
                // project itself, and would dominate every count.
                if Self.excludedDirectories.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }

            if url.pathExtension == "swift" {
                results.append(url)
            }
        }
        return results
    }
}
