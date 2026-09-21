import ArgumentParser
import Foundation
import KeelKit

struct Check: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Validate a project against its architecture rules.",
        discussion: """
            Reads the project's own files — no build, no network, no AI. Errors \
            are things Keel established structurally; warnings rest on a naming \
            convention or on something syntax cannot fully see, and say so. \
            Exits non-zero when there are errors, or with --strict when there is \
            anything at all.
            """
    )

    @Argument(help: "Project directory. Defaults to the working directory.")
    var path: String?

    @Flag(name: .shortAndLong, help: "Treat warnings as failures too.")
    var strict = false

    @Flag(name: .customLong("json"), help: "Emit JSON instead of a report.")
    var json = false

    @Flag(
        name: .customLong("github"),
        help: "Emit GitHub Actions annotations, so findings land on the changed lines."
    )
    var github = false

    @Flag(name: .customLong("explain"), help: "Say why each finding exists and why it carries its severity.")
    var explain = false

    @Flag(name: .customLong("interactive"), help: "Walk the findings one at a time.")
    var interactive = false

    @Flag(
        name: .customLong("write-baseline"),
        help: "Record today's findings as accepted, and report only new ones from now on."
    )
    var writeBaseline = false

    @Flag(name: .customLong("no-baseline"), help: "Report everything, ignoring any baseline.")
    var noBaseline = false

    func run() throws {
        let console = Console.shared
        let root = URL(fileURLWithPath: path ?? FileManager.default.currentDirectoryPath)

        let model: ProjectModel
        do {
            model = try ProjectScanner(root: root).scan()
        } catch let error as ProjectScanner.ScanError {
            console.error(error.description)
            throw ExitCode.failure
        }

        let everything = ProjectChecker(model: model).check()

        if writeBaseline {
            try record(everything, at: root, console: console)
            return
        }

        // A baseline is found, not configured. A project either has one or it
        // does not, which keeps the common case flagless.
        let baseline = noBaseline ? nil : CheckBaseline.load(from: root)
        let outcome = baseline?.apply(to: everything)
        let diagnostics = outcome?.remaining ?? everything

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(diagnostics), as: UTF8.self))
        } else if github {
            for line in GitHubAnnotations.lines(for: diagnostics) { print(line) }
        } else if interactive, InteractivePrompt.isAvailable {
            walk(diagnostics, for: model, console: console)
        } else {
            // `--interactive` without a terminal falls through to the report
            // rather than waiting for somebody who is not there. A CI log is
            // the commonest place for a stray flag to end up.
            render(diagnostics, for: model, console: console)
        }

        // Neither machine format gets the baseline note: JSON has a shape to
        // keep, and an annotation stream is read by GitHub, not by a person.
        if let outcome, !json, !github { reportBaseline(outcome, console: console) }

        // A gate is only useful if it can fail. Warnings do not fail a build by
        // default, because most of them are inferences. A stale baseline never
        // fails: punishing somebody for fixing something is how a tool gets
        // switched off.
        let failed = !diagnostics.errors.isEmpty || (strict && !diagnostics.isEmpty)
        if failed { throw ExitCode.failure }
    }

    // MARK: - Baseline

    private func record(
        _ diagnostics: [Diagnostic],
        at root: URL,
        console: Console
    ) throws {
        let baseline = CheckBaseline(recording: diagnostics)
        do {
            try baseline.write(to: root)
        } catch {
            console.error("Could not write \(CheckBaseline.fileName): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        console.success("Wrote \(CheckBaseline.fileName)")
        console.detail(
            "\(count(diagnostics.count, "finding")) accepted across "
                + "\(count(baseline.accepted.count, "file-and-rule pair")). "
                + "New findings will be reported."
        )
        console.detail("Commit it, so everyone gates on the same starting point.")
    }

    private func reportBaseline(_ outcome: CheckBaseline.Outcome, console: Console) {
        guard outcome.accepted > 0 || outcome.isStale else { return }

        if outcome.accepted > 0 {
            // Counted, never silent. A suppressed finding nobody can see is a
            // lie about the state of the project.
            console.detail("\(count(outcome.accepted, "finding")) accepted by the baseline.")
        }
        if outcome.isStale {
            console.detail(
                "\(count(outcome.stale.count, "baseline entry")) no longer matches — "
                    + "fixed since it was recorded."
            )
            console.detail("Run `keel check --write-baseline` to record that.")
        }
    }

    // MARK: - Report

    private func render(_ diagnostics: [Diagnostic], for model: ProjectModel, console: Console) {
        console.heading(model.name)

        guard !diagnostics.isEmpty else {
            console.success("Nothing to report.")
            console.detail("Checked \(model.source.swiftFileCount) Swift files against \(ruleCount) rules.")
            return
        }

        // A rule that fires forty times should not print forty copies of its
        // own rationale. Findings are ordered by rule, so the paragraph goes
        // at the head of each run and the `[rule-id]` tag on every finding
        // says which run this one belongs to.
        var explained: Set<String> = []

        for (index, diagnostic) in diagnostics.enumerated() {
            // A rule between findings rather than only after them: once a
            // finding runs to six lines, a blank line stops separating
            // anything.
            if index > 0 { console.rule() }

            headline(diagnostic, console: console)
            if let detail = diagnostic.detail,
               !isRepeatedRationale(detail, for: diagnostic, seen: &explained) {
                console.paragraph(detail)
            }
            renderEvidence(diagnostic, console: console)
            if explain { renderExplanation(diagnostic, console: console) }
            console.detail("[\(diagnostic.rule)]")
            // No trailing blank: `heading` opens with one of its own, and two
            // in a row read as a gap rather than a separator.
            if index < diagnostics.count - 1 { console.write() }
        }

        summarise(diagnostics, console: console)
    }

    /// Whether this detail is the rule's own rationale, already printed.
    ///
    /// Only the shared rationale is suppressed. A detail written for one
    /// finding — "Add `import SwiftData` to this file" — names that file and
    /// is printed every time.
    private func isRepeatedRationale(
        _ detail: String,
        for diagnostic: Diagnostic,
        seen: inout Set<String>
    ) -> Bool {
        guard detail == CheckRules.rule(diagnostic.rule)?.explanation else { return false }
        return !seen.insert(diagnostic.rule).inserted
    }

    private func headline(_ diagnostic: Diagnostic, console: Console) {
        let line = diagnostic.location.map { "\($0) — " } ?? ""
        switch diagnostic.severity {
        case .error: console.failure("\(line)\(diagnostic.message)")
        case .warning: console.warn("\(line)\(diagnostic.message)")
        }
    }

    /// The lines the finding was read from.
    ///
    /// Printed for relationship findings and absent for the rest, because a
    /// rule that already names one file and line has nothing to add by
    /// repeating it.
    private func renderEvidence(_ diagnostic: Diagnostic, console: Console) {
        if let path = diagnostic.path, path.count > 1 {
            console.detail("Path: \(path.joined(separator: " → "))")
        }
        guard !diagnostic.evidence.isEmpty else { return }

        console.detail("Evidence:")
        // Locations and statements as two columns, so the statements line up
        // however long the paths are.
        console.table(
            diagnostic.evidence.map { [$0.location, $0.statement] },
            indent: 4
        )
    }

    /// Why the rule exists, and why it carries the severity it does.
    private func renderExplanation(_ diagnostic: Diagnostic, console: Console) {
        guard let rule = CheckRules.rule(diagnostic.rule) else { return }
        console.write()
        // Several findings already carry the rule's explanation as their
        // detail, and printing the same paragraph twice under a new heading
        // teaches people to skip both.
        if rule.explanation != diagnostic.detail {
            console.detail("Why this rule exists:")
            console.paragraph(rule.explanation, indent: 4)
        }
        console.detail("Why it is a \(diagnostic.severity.displayName):")
        console.paragraph(rule.severityPolicy, indent: 4)
    }

    // MARK: - Interactive

    /// Walks the findings one at a time.
    ///
    /// Only reached with a terminal attached, and it changes nothing about the
    /// exit code: a gate that behaved differently depending on whether someone
    /// was watching would be useless in CI and misleading everywhere else.
    private func walk(_ diagnostics: [Diagnostic], for model: ProjectModel, console: Console) {
        console.heading(model.name)

        guard !diagnostics.isEmpty else {
            console.success("Nothing to report.")
            console.detail("Checked \(model.source.swiftFileCount) Swift files against \(ruleCount) rules.")
            return
        }

        let answers = InteractivePrompt(console: console)

        for (index, diagnostic) in diagnostics.enumerated() {
            console.write()
            console.detail("\(index + 1) of \(diagnostics.count)")
            headline(diagnostic, console: console)

            var showing = true
            while showing {
                switch answers.choice(
                    "What next?",
                    options: ["Continue", "Show evidence", "Show dependency path", "Explain rule", "Skip the rest"],
                    default: 0
                ) {
                case 1:
                    if diagnostic.evidence.isEmpty {
                        console.detail("No line-level evidence: this finding is about the project as a whole.")
                    } else {
                        renderEvidence(diagnostic, console: console)
                    }
                case 2:
                    if let path = diagnostic.path, path.count > 1 {
                        console.detail("Path: \(path.joined(separator: " → "))")
                    } else {
                        console.detail("No path: this finding is about one place, not a chain.")
                    }
                case 3:
                    renderExplanation(diagnostic, console: console)
                case 4:
                    console.write()
                    summarise(diagnostics, console: console)
                    return
                default:
                    showing = false
                }
            }
        }

        console.write()
        summarise(diagnostics, console: console)
    }

    private func summarise(_ diagnostics: [Diagnostic], console: Console) {
        let errors = diagnostics.errors.count
        let warnings = diagnostics.warnings.count
        console.heading("Summary")
        console.detail("\(count(errors, "error")), \(count(warnings, "warning"))")

        if errors == 0 && !strict {
            console.detail("Warnings do not fail this command. Use --strict if they should.")
        }
    }

    /// Named in the report so "nothing to report" says how hard Keel looked.
    ///
    /// Read from the catalogue rather than written down again, so adding a rule
    /// cannot leave the count behind.
    private var ruleCount: Int { CheckRules.count }

    private func count(_ number: Int, _ singular: String) -> String {
        "\(number) \(singular)\(number == 1 ? "" : "s")"
    }
}
