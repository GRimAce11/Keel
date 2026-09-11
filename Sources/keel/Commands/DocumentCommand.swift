import ArgumentParser
import Foundation
import KeelKit

struct Document: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "document",
        abstract: "Generate PROJECT.md from an existing iOS project.",
        discussion: """
            Writes what static analysis found — structure, targets, \
            dependencies and the architecture it implies — with the evidence \
            behind each conclusion. No build, no network, no AI, and nothing \
            in the output that could not be derived from the project itself.
            """
    )

    @Argument(help: "Project directory. Defaults to the working directory.")
    var path: String?

    @Option(name: .shortAndLong, help: "Where to write. Defaults to PROJECT.md in the project.")
    var output: String?

    @Flag(name: .customLong("stdout"), help: "Print the document instead of writing a file.")
    var toStandardOutput = false

    @Flag(name: .shortAndLong, help: "Overwrite a file Keel did not write.")
    var force = false

    @Flag(name: .customLong("ai"), help: "Add an interpretation from the agent you selected.")
    var useAI = false

    @Flag(name: .customLong("show-prompt"), help: "Print what --ai would send, and send nothing.")
    var showPrompt = false

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

        if showPrompt {
            print(DocumentationPrompt(model: model).text())
            return
        }

        let markdown = ProjectDocument(
            model: model,
            interpretation: useAI ? try interpretation(for: model, console: console) : nil
        ).markdown()

        if toStandardOutput {
            print(markdown, terminator: "")
            return
        }

        let destination = output.map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: model.rootPath).appendingPathComponent("PROJECT.md")

        try guardAgainstOverwriting(destination, console: console)

        do {
            try markdown.write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            console.error("Could not write \(destination.path): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        console.success("Wrote \(displayPath(of: destination, from: model))")
        console.detail(model.architecture.summary)
    }

    // MARK: - Interpretation

    /// Asks the selected agent to describe the project, and treats anything it
    /// cannot do as a missing paragraph rather than a failed command.
    ///
    /// The document is the thing being produced. Losing it because a network
    /// call failed would punish someone for asking for a bonus, so an agent
    /// that errors costs the overview and nothing else.
    private func interpretation(
        for model: ProjectModel,
        console: Console
    ) throws -> ProjectDocument.Interpretation? {
        let provider: CommandLineAgent
        do {
            provider = try CommandLineAgent.resolve()
        } catch let error as AIError {
            // No agent selected is a mistake worth stopping for: the user asked
            // for something Keel cannot do, and writing the plain document
            // instead would quietly ignore the flag.
            console.error(error.description)
            throw ExitCode.failure
        }

        let name = Agent.known(id: provider.selection.agentID)?.name
            ?? provider.selection.agentID

        console.step("Asking \(name) to interpret the facts")
        console.detail("Runs    \(provider.invocation)")
        // Worth stating plainly: this is the one command that sends anything
        // anywhere, and what it sends is the analysis, not the code.
        console.detail("Sends   the facts in this document — no source code")

        let reply: String
        do {
            reply = try provider.complete(prompt: DocumentationPrompt(model: model).text())
        } catch let error as AIError {
            console.warn("No interpretation: \(error.description)")
            console.detail("The rest of the document is unaffected.")
            return nil
        }

        // Keel validates the shape before anything reaches the document. An
        // agent that ignored the format costs its section, not the file.
        do {
            let fields = try ProjectInterpretation.parse(reply)
            return ProjectDocument.Interpretation(fields: fields, agentName: name)
        } catch let error as ProjectInterpretation.ParseError {
            console.warn("No interpretation: \(error.description)")
            console.detail("The rest of the document is unaffected.")
            return nil
        }
    }

    // MARK: - Overwriting

    /// Keel replaces its own output without asking, and refuses to replace
    /// anyone else's.
    ///
    /// Regenerating a document is routine and should not need a flag. Silently
    /// destroying a `PROJECT.md` someone wrote by hand is a different act, and
    /// the marker Keel leaves in its own files is what tells the two apart.
    private func guardAgainstOverwriting(_ destination: URL, console: Console) throws {
        guard let existing = try? String(contentsOf: destination, encoding: .utf8) else { return }
        guard !ProjectDocument.isGenerated(existing), !force else { return }

        console.error("\(destination.lastPathComponent) already exists and was not written by Keel.")
        console.detail("Pass --force to overwrite it, or --output to write somewhere else.")
        throw ExitCode.failure
    }

    private func displayPath(of destination: URL, from model: ProjectModel) -> String {
        let prefix = model.rootPath + "/"
        return destination.path.hasPrefix(prefix)
            ? String(destination.path.dropFirst(prefix.count))
            : destination.path
    }
}
