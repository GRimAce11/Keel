import Foundation

/// What a document was written about, in a form two versions can be compared.
///
/// `keel document --check` has to answer "is this stale, and what changed",
/// and Markdown cannot answer the second half: a diff of rendered prose says
/// lines moved, not that a feature was added. So each document carries a small
/// record of the project it described, and staleness becomes a comparison of
/// facts rather than of text.
///
/// It is a summary, not the model. Everything here is something a person would
/// recognise as a change worth re-reading the document for.
public struct DocumentFingerprint: Codable, Sendable, Equatable {
    public let features: [String]
    public let modules: [String]
    public let dependencies: [String]
    public let targets: [String]
    /// Architecture verdicts, keyed by dimension.
    public let architecture: [String: String]
    public let swiftFileCount: Int

    public init(model: ProjectModel) {
        features = model.features.map(\.name).sorted()
        modules = model.modules.map(\.name).sorted()
        dependencies = model.dependencies.map(\.name).sorted()
        targets = model.allTargets.map(\.name).sorted()
        architecture = Dictionary(
            model.architecture.findings.map { ($0.dimension, $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        swiftFileCount = model.source.swiftFileCount
    }

    // MARK: - Embedding

    private static let prefix = "<!-- keel:fingerprint "
    private static let suffix = " -->"

    /// One HTML comment, invisible in rendered Markdown.
    public func embedded() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return Self.prefix + json + Self.suffix
    }

    /// Reads the fingerprint out of a document, if it has one.
    ///
    /// A document written by hand, or by a Keel too old to leave one, has none.
    /// That is a real answer — "cannot tell" — rather than a failure.
    public static func extract(from markdown: String) -> DocumentFingerprint? {
        guard let start = markdown.range(of: prefix),
              let end = markdown.range(of: suffix, range: start.upperBound..<markdown.endIndex)
        else { return nil }

        let json = String(markdown[start.upperBound..<end.lowerBound])
        return try? JSONDecoder().decode(DocumentFingerprint.self, from: Data(json.utf8))
    }

    // MARK: - Comparison

    /// What changed between the project a document described and the one on
    /// disk now, phrased the way someone would describe it.
    public func changes(to current: DocumentFingerprint) -> [String] {
        var changes: [String] = []

        changes += difference(features, current.features, noun: "feature")
        changes += difference(modules, current.modules, noun: "module")
        changes += difference(dependencies, current.dependencies, noun: "package dependency")
        changes += difference(targets, current.targets, noun: "target")

        for (dimension, value) in architecture.sorted(by: { $0.key < $1.key }) {
            guard let now = current.architecture[dimension], now != value else { continue }
            changes.append("\(dimension) changed from \(value) to \(now)")
        }
        for (dimension, value) in current.architecture where architecture[dimension] == nil {
            changes.append("\(dimension) is now \(value)")
        }

        // A file count moving on its own means edits the summary above cannot
        // see, which is still a reason to regenerate.
        if swiftFileCount != current.swiftFileCount && changes.isEmpty {
            changes.append(
                "Swift files went from \(swiftFileCount) to \(current.swiftFileCount)"
            )
        }

        return changes
    }

    private func difference(_ before: [String], _ after: [String], noun: String) -> [String] {
        let removed = Set(before).subtracting(after).sorted()
        let added = Set(after).subtracting(before).sorted()
        return added.map { "Added \(noun) \($0)" } + removed.map { "Removed \(noun) \($0)" }
    }
}
