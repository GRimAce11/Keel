import Foundation
import Testing
@testable import KeelKit

/// `document` is tested against projects Keel itself generates, for the same
/// reason inspection is: a real project that builds cannot drift from the
/// format Xcode actually writes.
@Suite("ProjectDocument")
struct ProjectDocumentTests {

    private let console = Console(useColor: false)

    private func document(
        components: Set<Component> = Set(Component.allCases)
    ) throws -> (markdown: String, model: ProjectModel) {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-document-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let configuration = ProjectConfiguration(
            name: try ProjectName("Probe"),
            bundleIdentifierPrefix: "com.acme",
            components: components
        )
        let outcome = try ProjectGenerator(configuration: configuration, console: console)
            .generate(in: destination, initializeGit: false)
        let model = try ProjectScanner(root: outcome.projectDirectory).scan()
        return (ProjectDocument(model: model).markdown(), model)
    }

    // MARK: - Identity

    @Test("The document marks itself as Keel's, so a rerun can replace it")
    func marksItsOwnOutput() throws {
        let (markdown, _) = try document()

        #expect(markdown.contains(ProjectDocument.marker))
        #expect(ProjectDocument.isGenerated(markdown))
        // A file someone wrote by hand must not be mistaken for Keel's.
        #expect(!ProjectDocument.isGenerated("# My project\n\nNotes I wrote."))
    }

    @Test("Rendering the same project twice produces the same bytes")
    func isDeterministic() throws {
        // No timestamp, by design: a document that changes on every run buries
        // the change that mattered, and re-running must produce an empty diff.
        let (first, model) = try document()
        let second = ProjectDocument(model: model).markdown()

        #expect(first == second)
        #expect(!first.contains("Generated on"))
    }

    // MARK: - Content

    @Test("The document opens with the architecture summary")
    func leadsWithTheSummary() throws {
        let (markdown, model) = try document()

        #expect(markdown.hasPrefix("# Probe\n"))
        #expect(markdown.contains(model.architecture.summary))
    }

    @Test("Every architecture finding reaches the document with its evidence")
    func carriesEveryFinding() throws {
        let (markdown, model) = try document()

        for finding in model.architecture.findings {
            #expect(markdown.contains(finding.dimension), "missing \(finding.dimension)")
            for line in finding.evidence {
                #expect(markdown.contains(line), "missing evidence: \(line)")
            }
        }
    }

    @Test("Structure, targets and schemes come from the model")
    func reportsStructure() throws {
        let (markdown, model) = try document()

        #expect(markdown.contains("| Articles |"))
        #expect(markdown.contains("Data, Domain, Presentation"))
        for target in model.allTargets {
            #expect(markdown.contains("| \(target.name) |"), "missing target \(target.name)")
        }
        #expect(markdown.contains("Test targets: ProbeTests"))
    }

    @Test("An empty dependency list is reported as a fact, not omitted")
    func reportsAbsenceOfDependencies() throws {
        // "No package dependencies" is derived from the project — the list is
        // empty — so it is stated rather than left to inference.
        let (markdown, _) = try document()
        #expect(markdown.contains("No package dependencies."))
    }

    // MARK: - Restraint

    @Test("A minimal project gets no claim the evidence does not support")
    func inventsNothingForAMinimalProject() throws {
        let (markdown, _) = try document(components: [])

        #expect(markdown.contains("SwiftUI, no view models"))
        #expect(!markdown.contains("MVVM"))
        // Where nothing settles the question the table says so.
        #expect(markdown.contains("| Observation | Undetermined |"))
        // And sections with no data are absent rather than empty.
        #expect(!markdown.contains("### Features"))
    }

    @Test("A project without tests is warned about rather than described as fine")
    func flagsMissingTests() throws {
        let (markdown, _) = try document(components: [])
        #expect(markdown.contains("No test target and no testing framework found."))
    }

    // MARK: - Markdown safety

    @Test("A pipe in a value cannot break the table it sits in")
    func escapesTableCells() {
        let model = ProjectModel(
            name: "Odd",
            rootPath: "/tmp/Odd",
            workspacePath: nil,
            projects: [],
            schemes: [],
            dependencies: [
                PackageDependency(name: "a|b", url: nil, requirement: "1.0|2.0", isLocal: false)
            ],
            configurations: [],
            modules: [],
            features: [],
            source: SourceSummary(
                swiftFileCount: 0, lineCount: 0,
                importsSwiftUI: false, importsUIKit: false,
                usesObservationMacro: false, usesObservableObject: false,
                usesAsyncAwait: false, usesCombine: false,
                usesSwiftData: false, usesCoreData: false,
                usesSwiftTesting: false, usesXCTest: false
            ),
            analysis: SourceAnalysis(files: []),
            architecture: ArchitectureDetector(
                modules: [], features: [], analysis: SourceAnalysis(files: [])
            ).detect()
        )

        let markdown = ProjectDocument(model: model).markdown()
        #expect(markdown.contains("a\\|b"))
        #expect(markdown.contains("1.0\\|2.0"))
    }

    @Test("A project with nothing determinable still produces a valid document")
    func survivesAnEmptyModel() {
        let empty = ProjectModel(
            name: "Empty",
            rootPath: "/tmp/Empty",
            workspacePath: nil,
            projects: [],
            schemes: [],
            dependencies: [],
            configurations: [],
            modules: [],
            features: [],
            source: SourceSummary(
                swiftFileCount: 0, lineCount: 0,
                importsSwiftUI: false, importsUIKit: false,
                usesObservationMacro: false, usesObservableObject: false,
                usesAsyncAwait: false, usesCombine: false,
                usesSwiftData: false, usesCoreData: false,
                usesSwiftTesting: false, usesXCTest: false
            ),
            analysis: SourceAnalysis(files: []),
            architecture: ArchitectureDetector(
                modules: [], features: [], analysis: SourceAnalysis(files: [])
            ).detect()
        )

        let markdown = ProjectDocument(model: empty).markdown()

        #expect(markdown.hasPrefix("# Empty\n"))
        #expect(markdown.contains("Not enough in the project to describe its architecture."))
        #expect(markdown.hasSuffix("\n"))
    }
}

// MARK: - Command

/// Drives the real binary, because the part of `document` that can destroy
/// someone's work is the file handling, and that lives in the command.
@Suite("keel document")
struct DocumentCommandTests {

    private let console = Console(useColor: false)

    private func withGeneratedProject<T>(_ body: (URL) throws -> T) throws -> T {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-document-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let configuration = ProjectConfiguration(
            name: try ProjectName("Probe"),
            bundleIdentifierPrefix: "com.acme",
            components: Set(Component.allCases)
        )
        let outcome = try ProjectGenerator(configuration: configuration, console: console)
            .generate(in: destination, initializeGit: false)
        return try body(outcome.projectDirectory)
    }

    @Test("Writes PROJECT.md into the project")
    func writesTheDocument() throws {
        try withGeneratedProject { root in
            let result = try CLIRunner.run(["document", root.path])
            #expect(result.succeeded)

            let document = root.appendingPathComponent("PROJECT.md")
            let contents = try String(contentsOf: document, encoding: .utf8)
            #expect(ProjectDocument.isGenerated(contents))
        }
    }

    @Test("Replaces its own output without needing a flag")
    func regeneratesInPlace() throws {
        try withGeneratedProject { root in
            let first = try CLIRunner.run(["document", root.path])
            #expect(first.succeeded)
            // Regenerating is routine; requiring --force for it would make the
            // command annoying enough to stop using.
            let second = try CLIRunner.run(["document", root.path])
            #expect(second.succeeded)
        }
    }

    @Test("Refuses to destroy a PROJECT.md somebody wrote by hand")
    func refusesToOverwriteHandwrittenFiles() throws {
        try withGeneratedProject { root in
            let document = root.appendingPathComponent("PROJECT.md")
            let mine = "# Probe\n\nNotes I wrote myself.\n"
            try mine.write(to: document, atomically: true, encoding: .utf8)

            let result = try CLIRunner.run(["document", root.path])
            #expect(result.succeeded == false)
            #expect(result.combinedOutput.contains("--force"))
            // The refusal is only worth anything if the file really survives.
            let survived = try String(contentsOf: document, encoding: .utf8)
            #expect(survived == mine)

            let forced = try CLIRunner.run(["document", root.path, "--force"])
            #expect(forced.succeeded)
            let replaced = try String(contentsOf: document, encoding: .utf8)
            #expect(ProjectDocument.isGenerated(replaced))
        }
    }

    @Test("--stdout prints the document and writes nothing")
    func printsWithoutWriting() throws {
        try withGeneratedProject { root in
            let result = try CLIRunner.run(["document", root.path, "--stdout"])
            #expect(result.succeeded)
            #expect(result.standardOutput.contains("## Architecture"))
            #expect(
                !FileManager.default.fileExists(
                    atPath: root.appendingPathComponent("PROJECT.md").path
                )
            )
        }
    }
}

// MARK: - Interpretation

/// The AI layer may interpret facts the deterministic core established. These
/// tests are mostly about what it is not allowed to do.
@Suite("AI-assisted documentation")
struct AIDocumentationTests {

    private let console = Console(useColor: false)

    private func model(
        components: Set<Component> = Set(Component.allCases)
    ) throws -> ProjectModel {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-aidoc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let configuration = ProjectConfiguration(
            name: try ProjectName("Probe"),
            bundleIdentifierPrefix: "com.acme",
            components: components
        )
        let outcome = try ProjectGenerator(configuration: configuration, console: console)
            .generate(in: destination, initializeGit: false)
        return try ProjectScanner(root: outcome.projectDirectory).scan()
    }

    // MARK: Prompt

    @Test("The prompt carries derived facts and no source code")
    func sendsFactsNotCode() throws {
        let model = try model()
        let prompt = DocumentationPrompt(model: model).text()

        // Facts the document already shows.
        #expect(prompt.contains(model.architecture.summary))
        #expect(prompt.contains("Presentation: MVVM"))
        #expect(prompt.contains("Articles"))

        // Nothing that would only be in the source itself. Keel sends what it
        // derived, which is the whole privacy claim.
        #expect(!prompt.contains("import SwiftUI"))
        #expect(!prompt.contains("var body: some View"))
        #expect(!prompt.contains("func "))
    }

    @Test("The prompt forbids inventing and forbids guessing at undetermined facts")
    func instructsAgainstInvention() throws {
        let prompt = try DocumentationPrompt(model: model()).text()

        #expect(prompt.contains("do not invent"))
        #expect(prompt.contains("undetermined"))
    }

    @Test("Undetermined findings reach the prompt marked as undetermined")
    func marksUndeterminedFindings() throws {
        // A minimal project has several. The agent must be told they are
        // unknown rather than simply not told about them.
        let prompt = try DocumentationPrompt(model: model(components: [])).text()
        #expect(prompt.contains("Undetermined (undetermined)"))
    }

    // MARK: Rendering

    @Test("An overview is fenced, attributed, and marked as unchecked")
    func fencesAndAttributes() throws {
        let overview = ProjectDocument.Overview(
            prose: "A small application.", agentName: "Claude Code"
        )
        let markdown = try ProjectDocument(model: model(), overview: overview).markdown()

        #expect(markdown.contains(ProjectDocument.overviewStart))
        #expect(markdown.contains(ProjectDocument.overviewEnd))
        #expect(markdown.contains("Written by Claude Code"))
        // Unattributed prose in a file of measured facts reads as another fact.
        #expect(markdown.contains("not checked by Keel"))
        #expect(markdown.contains("A small application."))
    }

    @Test("An overview adds a section and changes nothing else")
    func leavesDerivedSectionsAlone() throws {
        let model = try model()
        let plain = ProjectDocument(model: model).markdown()
        let withOverview = ProjectDocument(
            model: model,
            overview: .init(prose: "Prose.", agentName: "Agent")
        ).markdown()

        #expect(!plain.contains(ProjectDocument.overviewStart))

        // Removing the fenced block must give back exactly the plain document,
        // which is what "interpretation cannot override facts" means in bytes.
        let start = try #require(withOverview.range(of: ProjectDocument.overviewStart))
        let end = try #require(withOverview.range(of: ProjectDocument.overviewEnd))

        // The block and the separator inserted with it, and nothing else.
        var cut = end.upperBound
        if withOverview[cut...].hasPrefix("\n\n") {
            cut = withOverview.index(cut, offsetBy: 2)
        }
        var stripped = withOverview
        stripped.removeSubrange(start.lowerBound..<cut)

        #expect(stripped == plain)
    }

    @Test("Without an overview the document is byte-identical to before the AI layer")
    func defaultIsUnchanged() throws {
        let model = try model()
        // Determinism is the default; --ai is the only thing that breaks it,
        // and only inside its own fence.
        #expect(ProjectDocument(model: model).markdown()
                == ProjectDocument(model: model, overview: nil).markdown())
    }
}

// MARK: - Command, with the AI flags

/// These run the real binary, so they point `XDG_CONFIG_HOME` at a temporary
/// directory. Reading the real config could find a selected agent and then run
/// it, which would spend someone's quota to satisfy a test suite.
@Suite("keel document --ai")
struct DocumentAICommandTests {

    private let console = Console(useColor: false)

    private func withProject<T>(_ body: (URL, [String: String]) throws -> T) throws -> T {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-aicli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let configuration = ProjectConfiguration(
            name: try ProjectName("Probe"),
            bundleIdentifierPrefix: "com.acme",
            components: Set(Component.allCases)
        )
        let outcome = try ProjectGenerator(configuration: configuration, console: console)
            .generate(in: root, initializeGit: false)

        let emptyConfig = root.appendingPathComponent("config")
        return try body(outcome.projectDirectory, ["XDG_CONFIG_HOME": emptyConfig.path])
    }

    @Test("--show-prompt prints what would be sent and sends nothing")
    func showsPromptWithoutSending() throws {
        try withProject { root, environment in
            let result = try CLIRunner.run(
                ["document", root.path, "--show-prompt"], environment: environment
            )

            #expect(result.succeeded)
            #expect(result.standardOutput.contains("FACTS"))
            #expect(result.standardOutput.contains("do not invent"))
            // It is a dry run in both directions: no agent, and no file.
            #expect(!FileManager.default.fileExists(
                atPath: root.appendingPathComponent("PROJECT.md").path
            ))
        }
    }

    @Test("--ai without a selected agent stops rather than quietly writing the plain document")
    func refusesWithoutAnAgent() throws {
        try withProject { root, environment in
            let result = try CLIRunner.run(
                ["document", root.path, "--ai"], environment: environment
            )

            // Ignoring the flag would be worse than failing: the user asked for
            // something and would get a file that does not contain it.
            #expect(result.succeeded == false)
            #expect(result.combinedOutput.contains("No AI agent is selected"))
        }
    }

    @Test("Without --ai nothing about the AI layer is reachable")
    func defaultTouchesNoAgent() throws {
        try withProject { root, environment in
            let result = try CLIRunner.run(["document", root.path], environment: environment)

            #expect(result.succeeded)
            let contents = try String(
                contentsOf: root.appendingPathComponent("PROJECT.md"), encoding: .utf8
            )
            #expect(!contents.contains(ProjectDocument.overviewStart))
        }
    }
}
