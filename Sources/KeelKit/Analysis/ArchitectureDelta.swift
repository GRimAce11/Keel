import Foundation

/// What changed architecturally between two revisions, and which of it is
/// worse rather than merely different.
///
/// The split is the whole point. `keel check` answers "what is wrong with this
/// codebase", which on an inherited project is forty findings and no action.
/// This answers "what did this branch make worse", which is what a pull
/// request is asking.
///
/// It invents no new opinion to do it. Keel's stated position is that the only
/// directions it will call wrong are the ones the project itself establishes —
/// shared code depended on by a feature, a layer pointing back outwards — plus
/// cycles, which need no rule to be wrong. Regressions here are exactly that
/// set, read from the rules `check` already enforces, so the two commands
/// cannot come to different conclusions about the same code.
public struct ArchitectureDelta: Sendable, Equatable {

    /// Rules whose appearance is a regression whatever severity they carry.
    ///
    /// A feature cycle is a `warning` in `check`, because what counts as a
    /// feature comes from folder names. But *newly* introducing one is still
    /// the thing this command exists to catch, so the classification here is
    /// by rule rather than by severity.
    static let structuralHarm: Set<String> = [
        "feature-dependency-cycle",
        "shared-code-depends-on-feature",
        "layer-inversion",
    ]

    public enum Standing: String, Sendable, Equatable {
        /// Worse than it was. Fails the command.
        case regression
        /// Different, with no direction Keel is entitled to judge.
        case change
        /// Better than it was.
        case fixed
    }

    public struct Entry: Sendable, Equatable {
        public let standing: Standing
        public let headline: String
        /// The thing itself — a cycle path, an edge, a rule id.
        public let subject: String
        public let locations: [String]

        public init(
            standing: Standing,
            headline: String,
            subject: String,
            locations: [String] = []
        ) {
            self.standing = standing
            self.headline = headline
            self.subject = subject
            self.locations = locations
        }
    }

    public let entries: [Entry]

    public var regressions: [Entry] { entries.filter { $0.standing == .regression } }
    public var changes: [Entry] { entries.filter { $0.standing == .change } }
    public var fixed: [Entry] { entries.filter { $0.standing == .fixed } }

    public var isEmpty: Bool { entries.isEmpty }
    public var hasRegressions: Bool { !regressions.isEmpty }

    // MARK: - Building

    public init(before: ProjectModel, after: ProjectModel) {
        var entries: [Entry] = []
        entries += Self.cycleEntries(before: before, after: after)
        entries += Self.findingEntries(before: before, after: after)
        entries += Self.inventoryEntries(before: before, after: after)
        self.entries = entries
    }

    init(entries: [Entry]) {
        self.entries = entries
    }

    // MARK: Cycles

    /// A cycle is the one finding that needs no rule to be wrong, so it is
    /// compared directly rather than through the checker.
    private static func cycleEntries(before: ProjectModel, after: ProjectModel) -> [Entry] {
        let old = cycles(in: before)
        let new = cycles(in: after)

        var entries: [Entry] = []
        for (key, cycle) in new.sorted(by: { $0.key < $1.key }) where old[key] == nil {
            entries.append(Entry(
                standing: .regression,
                headline: "New cycle at \(cycle.scope.displayName.lowercased()) scope",
                subject: cycle.path
            ))
        }
        for (key, cycle) in old.sorted(by: { $0.key < $1.key }) where new[key] == nil {
            entries.append(Entry(
                standing: .fixed,
                headline: "Cycle removed at \(cycle.scope.displayName.lowercased()) scope",
                subject: cycle.path
            ))
        }
        return entries
    }

    private struct Cycle {
        let scope: DependencyScope
        let path: String
    }

    /// Keyed so the same loop found from a different starting node matches
    /// itself. `A → B → A` and `B → A → B` are one cycle, and reporting the
    /// second as new because the traversal began elsewhere would make the
    /// command untrustworthy on its first real use.
    private static func cycles(in model: ProjectModel) -> [String: Cycle] {
        let graph = model.dependencyGraph()
        var found: [String: Cycle] = [:]

        for scope in DependencyScope.structural {
            for cycle in graph.cycles(at: scope) {
                let nodes = cycle.last == cycle.first ? Array(cycle.dropLast()) : cycle
                guard !nodes.isEmpty else { continue }
                let key = "\(scope.rawValue):\(nodes.sorted().joined(separator: ","))"
                found[key] = Cycle(
                    scope: scope,
                    path: (nodes + [nodes[0]]).joined(separator: " → ")
                )
            }
        }
        return found
    }

    // MARK: Findings

    /// Findings keyed by rule and file, never by line.
    ///
    /// Line numbers move on every unrelated edit. Keyed on them, a finding that
    /// did not change would be reported as fixed and reintroduced on the same
    /// run — the same reason `document --check` leaves reference counts out of
    /// its fingerprint.
    private static func findingEntries(before: ProjectModel, after: ProjectModel) -> [Entry] {
        let old = findings(in: before)
        let new = findings(in: after)

        var entries: [Entry] = []

        for (key, diagnostic) in new.sorted(by: { $0.key < $1.key }) where old[key] == nil {
            let harmful = structuralHarm.contains(diagnostic.rule)
                || diagnostic.severity == .error
            entries.append(Entry(
                // A new warning that is not structural harm is reported and
                // does not fail, exactly as in `check`. A convention never
                // gets to break a build.
                standing: harmful ? .regression : .change,
                headline: harmful ? "New \(diagnostic.rule)" : "New warning: \(diagnostic.rule)",
                subject: diagnostic.message,
                locations: diagnostic.evidence.map(\.location)
            ))
        }

        for (key, diagnostic) in old.sorted(by: { $0.key < $1.key }) where new[key] == nil {
            entries.append(Entry(
                standing: .fixed,
                headline: "Fixed \(diagnostic.rule)",
                subject: diagnostic.message
            ))
        }

        return entries
    }

    private static func findings(in model: ProjectModel) -> [String: Diagnostic] {
        var found: [String: Diagnostic] = [:]
        for diagnostic in ProjectChecker(model: model).check() {
            let file = diagnostic.location.map { location -> String in
                guard let colon = location.lastIndex(of: ":") else { return location }
                return String(location[location.startIndex..<colon])
            } ?? "-"
            // Several findings of one rule in one file collapse to one entry.
            // Counting them would make an unrelated refactor inside the file
            // read as a regression.
            found["\(diagnostic.rule)@\(file)"] = diagnostic
        }
        return found
    }

    // MARK: Inventory

    /// Features, modules, targets, packages and the edges between them.
    ///
    /// Taken from `DocumentFingerprint`, which already computes and phrases
    /// exactly this for `document --check`. A second comparator would be free
    /// to disagree with the first about the same project.
    private static func inventoryEntries(before: ProjectModel, after: ProjectModel) -> [Entry] {
        DocumentFingerprint(model: before)
            .changes(to: DocumentFingerprint(model: after))
            .map { Entry(standing: .change, headline: $0, subject: "") }
    }
}
