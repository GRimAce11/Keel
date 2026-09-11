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
