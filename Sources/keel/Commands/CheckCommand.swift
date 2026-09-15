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

    @Flag(name: .customLong("explain"), help: "Say why each finding exists and why it carries its severity.")
    var explain = false

    @Flag(name: .customLong("interactive"), help: "Walk the findings one at a time.")
    var interactive = false

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

        let diagnostics = ProjectChecker(model: model).check()

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(diagnostics), as: UTF8.self))
        } else if interactive, InteractivePrompt.isAvailable {
            walk(diagnostics, for: model, console: console)
        } else {
            // `--interactive` without a terminal falls through to the report
            // rather than waiting for somebody who is not there. A CI log is
            // the commonest place for a stray flag to end up.
            render(diagnostics, for: model, console: console)
        }

        // A gate is only useful if it can fail. Warnings do not fail a build by
        // default, because most of them are inferences.
        let failed = !diagnostics.errors.isEmpty || (strict && !diagnostics.isEmpty)
        if failed { throw ExitCode.failure }
    }

    // MARK: - Report

    private func render(_ diagnostics: [Diagnostic], for model: ProjectModel, console: Console) {
        console.heading(model.name)

        guard !diagnostics.isEmpty else {
            console.success("Nothing to report.")
            console.detail("Checked \(model.source.swiftFileCount) Swift files against \(ruleCount) rules.")
            return
        }

        for diagnostic in diagnostics {
            headline(diagnostic, console: console)
            if let detail = diagnostic.detail {
                console.detail(detail)
            }
            renderEvidence(diagnostic, console: console)
            if explain { renderExplanation(diagnostic, console: console) }
            console.detail("[\(diagnostic.rule)]")
            console.write()
        }

        summarise(diagnostics, console: console)
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
        for item in diagnostic.evidence {
            console.detail("  \(item.location)  \(item.statement)")
        }
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
            console.detail("  \(rule.explanation)")
        }
        console.detail("Why it is a \(diagnostic.severity.displayName):")
        console.detail("  \(rule.severityPolicy)")
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
