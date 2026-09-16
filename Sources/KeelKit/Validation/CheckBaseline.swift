import Foundation

/// The findings a project has agreed to live with, so `check` can be switched
/// on before they are all fixed.
///
/// `keel check --strict` in CI is the headline use, and on an inherited
/// codebase it fails on day one with every pre-existing finding. So nobody
/// turns it on, and fifteen sound rules protect nothing on precisely the
/// projects Keel is for. A baseline accepts what is already there and fails on
/// what is new, which is the only adoption path that has ever worked for a
/// checker meeting an existing codebase.
public struct CheckBaseline: Codable, Sendable, Equatable {

    /// One rule, in one file, this many times.
    ///
    /// Never a line number. Lines move on every unrelated edit, and a baseline
    /// keyed on them goes stale the first time somebody adds an import — the
    /// same reason `document --check` leaves reference counts out of its
    /// fingerprint.
    public struct Accepted: Codable, Sendable, Equatable, Comparable {
        public let rule: String
        public let file: String
        public let count: Int

        public init(rule: String, file: String, count: Int) {
            self.rule = rule
            self.file = file
            self.count = count
        }

        public static func < (lhs: Accepted, rhs: Accepted) -> Bool {
            (lhs.rule, lhs.file) < (rhs.rule, rhs.file)
        }

        var key: String { "\(rule)@\(file)" }
    }

    public let version: Int
    /// Which Keel wrote it, so a reader can tell whether the rule set has moved
    /// underneath the file.
    public let recorded: String
    public let accepted: [Accepted]

    public static let fileName = ".keel/baseline.json"
    public static let currentVersion = 1

    public init(version: Int = CheckBaseline.currentVersion, recorded: String, accepted: [Accepted]) {
        self.version = version
        self.recorded = recorded
        self.accepted = accepted.sorted()
    }

    // MARK: - Recording

    public init(recording diagnostics: [Diagnostic]) {
        self.init(
            recorded: KeelVersion.current,
            accepted: Self.tally(diagnostics).values.map {
                Accepted(rule: $0.rule, file: $0.file, count: $0.count)
            }
        )
    }

    /// Which file a finding is about, with any line number removed.
    ///
    /// A finding about the project as a whole — no scheme shared, no test
    /// target — belongs to no file, and gets one bucket of its own rather than
    /// being dropped.
    static func file(of diagnostic: Diagnostic) -> String {
        guard let location = diagnostic.location else { return "-" }
        guard let colon = location.lastIndex(of: ":"),
              Int(location[location.index(after: colon)...]) != nil
        else { return location }
        return String(location[location.startIndex..<colon])
    }

    private static func tally(
        _ diagnostics: [Diagnostic]
    ) -> [String: (rule: String, file: String, count: Int)] {
        var counts: [String: (rule: String, file: String, count: Int)] = [:]
        for diagnostic in diagnostics {
            let file = file(of: diagnostic)
            let key = "\(diagnostic.rule)@\(file)"
            counts[key, default: (diagnostic.rule, file, 0)].count += 1
        }
        return counts
    }

    // MARK: - Applying

    /// What is left after the baseline has had its say.
    public struct Outcome: Sendable, Equatable {
        /// Findings to report and to fail on.
        public let remaining: [Diagnostic]
        /// How many were accepted. Counted rather than silently dropped: a
        /// suppressed finding nobody can see is a lie.
        public let accepted: Int
        /// Baseline entries that match nothing any more, because somebody
        /// fixed them.
        public let stale: [Accepted]

        public var isStale: Bool { !stale.isEmpty }
    }

    /// Accepts up to `count` findings of each recorded rule-and-file, and
    /// reports the rest.
    ///
    /// Findings beyond the recorded count are new, even though findings of the
    /// same rule in the same file were accepted. That is the case a baseline
    /// exists to catch: adding a sixteenth non-`@MainActor` view model to a
    /// file that had fifteen is still adding one.
    public func apply(to diagnostics: [Diagnostic]) -> Outcome {
        var budget: [String: Int] = [:]
        for entry in accepted { budget[entry.key] = entry.count }

        var remaining: [Diagnostic] = []
        var used: [String: Int] = [:]
        var acceptedCount = 0

        for diagnostic in diagnostics {
            let key = "\(diagnostic.rule)@\(Self.file(of: diagnostic))"
            if let allowance = budget[key], used[key, default: 0] < allowance {
                used[key, default: 0] += 1
                acceptedCount += 1
            } else {
                remaining.append(diagnostic)
            }
        }

        let stale = accepted.filter { used[$0.key, default: 0] < $0.count }

        return Outcome(remaining: remaining, accepted: acceptedCount, stale: stale)
    }

    // MARK: - Files

    public static func load(from root: URL) -> CheckBaseline? {
        let url = root.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CheckBaseline.self, from: data)
    }

    /// Written sorted and pretty-printed, so it diffs cleanly in review and two
    /// people recording it on the same day produce the same bytes.
    public func write(to root: URL) throws {
        let url = root.appendingPathComponent(Self.fileName)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
