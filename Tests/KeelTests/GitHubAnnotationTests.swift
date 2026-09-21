import Foundation
import Testing
@testable import KeelKit

/// Annotations are a rephrasing of findings Keel already has, so the tests are
/// about the rephrasing: that severities survive it, that a location becomes
/// the two properties GitHub wants, and that nothing in a message can end the
/// command early or corrupt the one after it.
@Suite("GitHub annotations")
struct GitHubAnnotationTests {

    private func diagnostic(
        rule: String = "feature-dependency-cycle",
        severity: Diagnostic.Severity = .warning,
        message: String = "Articles → Settings → Articles is a dependency cycle.",
        location: String? = "Probe/Features/Articles/ArticleListViewModel.swift:13"
    ) -> Diagnostic {
        Diagnostic(rule: rule, severity: severity, message: message, location: location)
    }

    // MARK: - Shape

    @Test("A finding becomes one annotation naming its file and line")
    func writesFileAndLine() {
        let lines = GitHubAnnotations.lines(for: [diagnostic()])

        #expect(lines == [
            "::warning file=Probe/Features/Articles/ArticleListViewModel.swift,line=13,"
                + "title=feature-dependency-cycle::"
                + "Articles → Settings → Articles is a dependency cycle."
        ])
    }

    @Test("Severity carries across unchanged")
    func keepsSeverity() {
        // An annotation that softened an error would disagree with the exit
        // code, and the exit code is what actually gates the build.
        let error = GitHubAnnotations.lines(for: [diagnostic(severity: .error)])
        #expect(error.first?.hasPrefix("::error ") == true)

        let warning = GitHubAnnotations.lines(for: [diagnostic(severity: .warning)])
        #expect(warning.first?.hasPrefix("::warning ") == true)
    }

    @Test("A finding with nowhere to point is still emitted")
    func keepsPlacelessFindings() {
        // `no-test-target` is about the project, not a line. Dropping it would
        // make the annotation stream quietly disagree with the report.
        let lines = GitHubAnnotations.lines(for: [
            diagnostic(rule: "no-test-target", message: "The project has no test target.", location: nil)
        ])

        #expect(lines == ["::warning title=no-test-target::The project has no test target."])
    }

    @Test("A path that is not a location is not split")
    func toleratesAnUnsplittableLocation() {
        let lines = GitHubAnnotations.lines(for: [diagnostic(location: "Probe/App")])

        #expect(lines.first?.contains("file=") == false)
        #expect(lines.first?.contains("line=") == false)
    }

    // MARK: - Escaping

    @Test("Nothing in a message can end the annotation early")
    func escapesData() throws {
        // A raw newline ends a workflow command. A message carrying one would
        // truncate its own annotation and leave the rest as stray log output.
        let lines = GitHubAnnotations.lines(for: [
            diagnostic(message: "100% of\nthem\r, really")
        ])
        let line = try #require(lines.first)

        #expect(!line.contains("\n"))
        #expect(!line.contains("\r"))
        #expect(line.hasSuffix("::100%25 of%0Athem%0D, really"))
    }

    @Test("A property value escapes the separators it sits between")
    func escapesProperties() {
        // Properties are comma-separated `key=value`, so a title carrying a
        // comma or a colon would invent a property that is not there.
        let lines = GitHubAnnotations.lines(for: ArchitectureDelta(entries: [
            .init(
                standing: .change,
                headline: "Feature isolation changed from Undetermined to Coupled, again: yes",
                subject: "something"
            ),
        ]))

        #expect(lines.first?.contains("%2C") == true)
        #expect(lines.first?.contains("%3A") == true)
    }

    // MARK: - Deltas

    @Test("A regression annotates as an error and a change as a warning")
    func mapsStandingToSeverity() {
        // A regression is what failed the command, whatever severity the rule
        // behind it carries.
        let lines = GitHubAnnotations.lines(for: ArchitectureDelta(entries: [
            .init(
                standing: .regression,
                headline: "New cycle at feature scope",
                subject: "Articles → Settings → Articles",
                locations: ["Probe/Features/Articles/ArticleListViewModel.swift:11"]
            ),
            .init(standing: .change, headline: "Added feature Settings", subject: ""),
        ]))

        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("::error file=Probe/Features/Articles/ArticleListViewModel.swift,line=11,"))
        #expect(lines[1].hasPrefix("::warning "))
    }

    @Test("A fix is not annotated")
    func leavesFixesOut() {
        // There is no line to put it on, and good news does not need marking
        // on a diff.
        let lines = GitHubAnnotations.lines(for: ArchitectureDelta(entries: [
            .init(standing: .fixed, headline: "Cycle removed at feature scope", subject: "A → B → A"),
        ]))

        #expect(lines.isEmpty)
    }

    @Test("An entry with no subject falls back to its headline")
    func neverEmitsAnEmptyMessage() {
        // Inventory changes carry the whole fact in the headline. An
        // annotation with an empty message renders as a blank box.
        let lines = GitHubAnnotations.lines(for: ArchitectureDelta(entries: [
            .init(standing: .change, headline: "Added feature Settings", subject: ""),
        ]))

        #expect(lines.first?.hasSuffix("::Added feature Settings") == true)
    }
}
