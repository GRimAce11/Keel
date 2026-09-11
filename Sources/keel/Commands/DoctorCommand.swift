import ArgumentParser
import Foundation
import KeelKit

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Diagnose the toolchain and the project in the working directory.",
        discussion: """
            Checks that this machine can build what Keel generates: Swift, a \
            full Xcode rather than only the Command Line Tools, and git. When \
            there is a project here, it also checks the toolchain against what \
            that project asks for.
            """
    )

    @Argument(help: "Project directory. Defaults to the working directory.")
    var path: String?

    @Flag(name: .customLong("json"), help: "Emit JSON instead of a report.")
    var json = false

    func run() throws {
        let console = Console.shared
        let root = URL(fileURLWithPath: path ?? FileManager.default.currentDirectoryPath)

        // A project is optional: `keel doctor` in an empty directory is a
        // reasonable way to ask whether the machine is ready at all.
        let model = try? ProjectScanner(root: root).scan()
        let diagnostics = KeelKit.Doctor(model: model).diagnose()

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(diagnostics), as: UTF8.self))
            if !diagnostics.errors.isEmpty { throw ExitCode.failure }
            return
        }

        console.heading("Toolchain")
        console.detail("Keel              \(KeelVersion.current)")
        if let swift = KeelKit.Doctor.swiftVersion() {
            console.detail("Swift             \(swift)")
        }
        if let model {
            console.detail("Project           \(model.name)")
        } else {
            console.detail("Project           none in this directory")
        }

        console.heading("Diagnosis")
        guard !diagnostics.isEmpty else {
            console.success("Everything Keel checks is in order.")
            return
        }

        for diagnostic in diagnostics {
            switch diagnostic.severity {
            case .error: console.error(diagnostic.message)
            case .warning: console.warn(diagnostic.message)
            }
            if let detail = diagnostic.detail { console.detail(detail) }
        }

        if !diagnostics.errors.isEmpty { throw ExitCode.failure }
    }
}
