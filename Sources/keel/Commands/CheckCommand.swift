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
        } else {
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
            let line = diagnostic.location.map { "\($0) — " } ?? ""
            switch diagnostic.severity {
            case .error:
                console.failure("\(line)\(diagnostic.message)")
            case .warning:
                console.warn("\(line)\(diagnostic.message)")
            }
            if let detail = diagnostic.detail {
                console.detail(detail)
            }
            console.detail("[\(diagnostic.rule)]")
            console.write()
        }

        let errors = diagnostics.errors.count
        let warnings = diagnostics.warnings.count
        console.heading("Summary")
        console.detail("\(count(errors, "error")), \(count(warnings, "warning"))")

        if errors == 0 && !strict {
            console.detail("Warnings do not fail this command. Use --strict if they should.")
        }
    }

    /// Named in the report so "nothing to report" says how hard Keel looked.
    private var ruleCount: Int { 8 }

    private func count(_ number: Int, _ singular: String) -> String {
        "\(number) \(singular)\(number == 1 ? "" : "s")"
    }
}
