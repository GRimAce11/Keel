import ArgumentParser
import Foundation
import KeelKit

struct Explore: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "explore",
        abstract: "Walk through a project's architecture from the terminal.",
        discussion: """
            For a codebase you did not write. Everything it shows is read from \
            the project's own files — the same facts `inspect` and `check` \
            report, reachable without knowing which flag produces them. No \
            build, no network, and no agent unless you ask for one.

            Needs a terminal to ask questions in. Piped or redirected, it \
            prints the summary and stops rather than waiting for somebody who \
            is not there.
            """
    )

    @Argument(help: "Project directory. Defaults to the working directory.")
    var path: String?

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

        guard InteractivePrompt.isAvailable else {
            // Not a failure: a scripted run asking to explore gets the summary
            // it would have seen first, and every other command still works.
            Explorer(model: model, answers: DefaultAnswers(), console: console).run()
            console.write()
            console.detail("No terminal to ask questions in, so that is as far as this goes.")
            console.detail("Try `keel inspect`, `keel inspect --graph` or `keel check`.")
            return
        }

        Explorer(model: model, answers: InteractivePrompt(console: console), console: console).run()
    }
}
