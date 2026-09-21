import Foundation
import Testing
@testable import KeelKit

/// `diff` exists to tell a regression from a change. Most of what matters is
/// that it puts things in the right one of those two piles, and that comparing
/// a project with itself finds nothing — a comparator with an unstable key
/// reports imaginary churn, which is worse than reporting nothing at all.
@Suite("keel diff")
struct DiffTests {

    private let console = Console(useColor: false)

    /// A generated project, optionally mutated before it is read.
    private func scan(_ mutate: (URL) throws -> Void = { _ in }) throws -> ProjectModel {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-diff-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let outcome = try ProjectGenerator(
            configuration: ProjectConfiguration(
                name: try ProjectName("Probe"),
                bundleIdentifierPrefix: "com.acme",
                components: Set(Component.allCases)
            ),
            console: console
        ).generate(in: destination, initializeGit: false)

        try mutate(outcome.projectDirectory)
        return try ProjectScanner(root: outcome.projectDirectory).scan()
    }

    private func write(_ source: String, to path: String, in root: URL) throws {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try source.write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: - Reading the argument

    @Test("A revision argument is read the way git users expect")
    func parsesComparisons() {
        typealias Comparison = GitRevision.Comparison

        // Nothing: this branch against its last commit.
        #expect(Comparison.parse(nil) == Comparison(before: "HEAD", after: nil))
        #expect(Comparison.parse("") == Comparison(before: "HEAD", after: nil))

        // One revision: uncommitted work against a branch, which is the thing
        // people want most often.
        #expect(Comparison.parse("main") == Comparison(before: "main", after: nil))

        // Two: what a pull request is.
        #expect(Comparison.parse("main..HEAD") == Comparison(before: "main", after: "HEAD"))
        #expect(Comparison.parse("main..") == Comparison(before: "main", after: nil))
        #expect(Comparison.parse("..HEAD") == Comparison(before: "HEAD", after: "HEAD"))
    }

    // MARK: - Stability

    @Test("A project compared with itself reports nothing")
    func findsNoChangeInNoChange() throws {
        let model = try scan()
        let delta = ArchitectureDelta(before: model, after: model)

        #expect(delta.isEmpty, "imaginary changes: \(delta.entries.map(\.headline))")
        #expect(!delta.hasRegressions)
    }

    @Test("A cycle found from a different starting node is the same cycle")
    func cycleIdentityIsStable() throws {
        // Two scans of the same project can enumerate a loop from either end.
        // Keyed on the traversal, `A → B → A` and `B → A → B` would look like
        // one cycle removed and another added on every single run.
        let cyclic = { (root: URL) throws -> Void in
            try self.write(
                "import Foundation\n\nstruct Bridge { let article: Article? }\n",
                to: "Probe/Features/Settings/Domain/Bridge.swift", in: root
            )
            try self.write(
                "import Foundation\n\nstruct BackBridge { let setting: Bridge? }\n",
                to: "Probe/Features/Articles/Domain/BackBridge.swift", in: root
            )
        }

        let delta = ArchitectureDelta(before: try scan(cyclic), after: try scan(cyclic))
        #expect(delta.isEmpty, "unstable: \(delta.entries.map(\.headline))")
    }

    @Test("One new cycle is one regression, not two")
    func countsANewCycleOnce() throws {
        // Cycles are compared directly, at every structural scope, and `check`
        // also has a feature-scope rule for them. Counting both reported one
        // loop twice and told the reader two things had gone wrong.
        let before = try scan()
        let after = try scan { root in
            try self.write(
                "import Foundation\n\nstruct Bridge { let article: Article? }\n",
                to: "Probe/Features/Settings/Domain/Bridge.swift", in: root
            )
            try self.write(
                "import Foundation\n\nstruct BackBridge { let setting: Bridge? }\n",
                to: "Probe/Features/Articles/Domain/BackBridge.swift", in: root
            )
        }

        let delta = ArchitectureDelta(before: before, after: after)
        let cycles = delta.regressions.filter { $0.subject.contains("Articles") }

        #expect(
            cycles.count == 1,
            "counted twice: \(cycles.map(\.headline))"
        )
        #expect(cycles.first?.headline.hasPrefix("New cycle at") == true)
    }

    @Test("A new cycle says where each hop of it is")
    func aNewCycleCarriesItsLocations() throws {
        // The rule used to carry the evidence. Now that it is not compared,
        // the cycle itself has to — a regression with nowhere to look is one
        // nobody can act on.
        let before = try scan()
        let after = try scan { root in
            try self.write(
                "import Foundation\n\nstruct Bridge { let article: Article? }\n",
                to: "Probe/Features/Settings/Domain/Bridge.swift", in: root
            )
            try self.write(
                "import Foundation\n\nstruct BackBridge { let setting: Bridge? }\n",
                to: "Probe/Features/Articles/Domain/BackBridge.swift", in: root
            )
        }

        let delta = ArchitectureDelta(before: before, after: after)
        let cycle = try #require(delta.regressions.first { $0.headline.hasPrefix("New cycle at") })

        #expect(!cycle.locations.isEmpty, "a cycle with nowhere to look")
        #expect(cycle.locations.allSatisfy { $0.contains(".swift:") })
    }

    // MARK: - Classification

    @Test("Shared code that starts depending on a feature is a regression")
    func newInversionIsARegression() throws {
        let before = try scan()
        let after = try scan { root in
            try self.write(
                """
                import SwiftUI

                struct ArticleBadge: View {
                    let article: Article
                    var body: some View { Text(article.title) }
                }

                """,
                to: "Probe/Shared/UI/ArticleBadge.swift", in: root
            )
        }

        let delta = ArchitectureDelta(before: before, after: after)

        #expect(delta.hasRegressions)
        #expect(delta.regressions.contains { $0.headline.contains("shared-code-depends-on-feature") })
        // And it says where, like every other Keel finding.
        #expect(delta.regressions.contains { !$0.locations.isEmpty })
    }

    @Test("Adding a feature is a change, not a regression")
    func newFeatureIsNotARegression() throws {
        let before = try scan()
        let after = try scan { root in
            try self.write(
                "import Foundation\n\nstruct Badge: Sendable { let label: String }\n",
                to: "Probe/Features/Badges/Domain/Badge.swift", in: root
            )
        }

        let delta = ArchitectureDelta(before: before, after: after)

        // A branch that adds a feature is not a problem, and a command that
        // said so would be switched off inside a week.
        #expect(!delta.hasRegressions, "regressions: \(delta.regressions.map(\.headline))")
        #expect(!delta.changes.isEmpty)
        #expect(delta.changes.contains { $0.headline.contains("Badges") })
    }

    @Test("Removing the problem is reported, and does not fail")
    func fixingIsReportedAndPasses() throws {
        let broken = try scan { root in
            try self.write(
                """
                import SwiftUI

                struct ArticleBadge: View {
                    let article: Article
                    var body: some View { Text(article.title) }
                }

                """,
                to: "Probe/Shared/UI/ArticleBadge.swift", in: root
            )
        }
        let delta = ArchitectureDelta(before: broken, after: try scan())

        #expect(!delta.hasRegressions)
        #expect(delta.fixed.contains { $0.headline.contains("shared-code-depends-on-feature") })
    }

    // MARK: - Failure that has to be actionable

    @Test("A shallow clone is told what to do, not handed a git error")
    func shallowCloneExplainsItself() {
        let failure = GitRevision.Failure.shallowRepository("main")

        // The most likely failure in CI by a wide margin: actions/checkout
        // defaults to fetch-depth 1, and the revision simply is not there.
        #expect(failure.description.contains("shallow"))
        #expect(failure.remedy?.contains("fetch-depth: 0") == true)
    }

    @Test("A directory outside a repository is a clear answer")
    func nonRepositoryExplainsItself() {
        let failure = GitRevision.Failure.notARepository("/tmp/somewhere")
        #expect(failure.description.contains("not inside a git repository"))
        #expect(failure.remedy?.contains("keel inspect") == true)
    }
}
