import Foundation
import Testing
@testable import KeelKit

/// A baseline is the only way a checker meets an existing codebase without
/// being switched off on day one. It has to accept exactly what was there and
/// not one finding more.
@Suite("Check baseline")
struct CheckBaselineTests {

    private func diagnostic(
        _ rule: String,
        _ location: String?,
        severity: Diagnostic.Severity = .warning
    ) -> Diagnostic {
        Diagnostic(rule: rule, severity: severity, message: "\(rule) at \(location ?? "-")", location: location)
    }

    // MARK: - What identifies a finding

    @Test("A finding is identified by rule and file, never by line")
    func ignoresLineNumbers() {
        // The whole design rests on this. Keyed on lines, a baseline goes
        // stale the first time somebody adds an import above the finding.
        #expect(CheckBaseline.file(of: diagnostic("r", "App/View.swift:12")) == "App/View.swift")
        #expect(CheckBaseline.file(of: diagnostic("r", "App/View.swift:9999")) == "App/View.swift")

        // A path with no line stays whole, and a finding about the project as
        // a whole gets a bucket rather than being dropped.
        #expect(CheckBaseline.file(of: diagnostic("r", "App/View.swift")) == "App/View.swift")
        #expect(CheckBaseline.file(of: diagnostic("r", nil)) == "-")
    }

    @Test("Moving a finding within its file keeps it accepted")
    func survivesLineMovement() {
        let baseline = CheckBaseline(recording: [diagnostic("r", "App/View.swift:12")])
        let afterAnEdit = baseline.apply(to: [diagnostic("r", "App/View.swift:48")])

        #expect(afterAnEdit.remaining.isEmpty)
        #expect(afterAnEdit.accepted == 1)
        #expect(!afterAnEdit.isStale)
    }

    // MARK: - Accepting exactly what was there

    @Test("One more of an already-accepted rule in the same file is new")
    func countsRatherThanBlanketAccepting() {
        // The case a baseline exists to catch. Accepting the rule for the file
        // outright would let a file quietly accumulate.
        let baseline = CheckBaseline(recording: [
            diagnostic("r", "App/View.swift:1"),
            diagnostic("r", "App/View.swift:2"),
        ])

        let outcome = baseline.apply(to: [
            diagnostic("r", "App/View.swift:1"),
            diagnostic("r", "App/View.swift:2"),
            diagnostic("r", "App/View.swift:3"),
        ])

        #expect(outcome.accepted == 2)
        #expect(outcome.remaining.count == 1)
    }

    @Test("The same rule in a different file is not accepted")
    func doesNotAcceptAcrossFiles() {
        let baseline = CheckBaseline(recording: [diagnostic("r", "App/A.swift:1")])
        let outcome = baseline.apply(to: [
            diagnostic("r", "App/A.swift:1"),
            diagnostic("r", "App/B.swift:1"),
        ])

        #expect(outcome.accepted == 1)
        #expect(outcome.remaining.count == 1)
        #expect(outcome.remaining[0].location == "App/B.swift:1")
    }

    @Test("A new rule is never accepted, whatever else the file carries")
    func doesNotAcceptNewRules() {
        let baseline = CheckBaseline(recording: [diagnostic("old", "App/A.swift:1")])
        let outcome = baseline.apply(to: [
            diagnostic("old", "App/A.swift:1"),
            diagnostic("new", "App/A.swift:1", severity: .error),
        ])

        #expect(outcome.accepted == 1)
        #expect(outcome.remaining.map(\.rule) == ["new"])
    }

    // MARK: - Going stale

    @Test("A fixed finding leaves the baseline stale, and that is not a failure")
    func reportsStaleEntries() {
        let baseline = CheckBaseline(recording: [
            diagnostic("r", "App/A.swift:1"),
            diagnostic("r", "App/B.swift:1"),
        ])
        let outcome = baseline.apply(to: [diagnostic("r", "App/A.swift:1")])

        #expect(outcome.isStale)
        #expect(outcome.stale.map(\.file) == ["App/B.swift"])
        // Nothing to report and nothing to fail on. Punishing somebody for
        // fixing something is how a tool gets turned off.
        #expect(outcome.remaining.isEmpty)
    }

    @Test("Partly fixing a file's findings is stale too")
    func noticesPartialFixes() {
        let baseline = CheckBaseline(recording: [
            diagnostic("r", "App/A.swift:1"),
            diagnostic("r", "App/A.swift:2"),
        ])
        let outcome = baseline.apply(to: [diagnostic("r", "App/A.swift:1")])

        #expect(outcome.accepted == 1)
        #expect(outcome.isStale)
        #expect(outcome.remaining.isEmpty)
    }

    // MARK: - The file

    @Test("The file round-trips and is byte-stable")
    func writesStably() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-baseline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Deliberately out of order: the file has to sort, or it churns in
        // review every time two people record it.
        let baseline = CheckBaseline(recording: [
            diagnostic("zulu", "App/Z.swift:1"),
            diagnostic("alpha", "App/A.swift:1"),
        ])

        try baseline.write(to: directory)
        let first = try Data(contentsOf: directory.appendingPathComponent(CheckBaseline.fileName))
        try baseline.write(to: directory)
        let second = try Data(contentsOf: directory.appendingPathComponent(CheckBaseline.fileName))

        #expect(first == second)

        let loaded = try #require(CheckBaseline.load(from: directory))
        #expect(loaded == baseline)
        #expect(loaded.accepted.map(\.rule) == ["alpha", "zulu"])
    }

    @Test("No baseline file is not an error")
    func absenceIsFine() {
        let nowhere = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-absent-\(UUID().uuidString)")
        #expect(CheckBaseline.load(from: nowhere) == nil)
    }
}
