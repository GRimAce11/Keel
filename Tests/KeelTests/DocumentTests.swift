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
        // Data, not prose to paste: Keel owns the Markdown.
        #expect(prompt.contains("single JSON object"))
        for field in ["overview", "dataFlow", "conventions", "risks", "onboarding"] {
            #expect(prompt.contains("\"\(field)\""), "prompt does not ask for \(field)")
        }
    }

    @Test("Undetermined findings reach the prompt marked as undetermined")
    func marksUndeterminedFindings() throws {
        // A minimal project has several. The agent must be told they are
        // unknown rather than simply not told about them.
        let prompt = try DocumentationPrompt(model: model(components: [])).text()
        #expect(prompt.contains("Undetermined (undetermined)"))
    }

    // MARK: Rendering

    @Test("An interpretation is fenced, attributed, and marked as unchecked")
    func fencesAndAttributes() throws {
        let interpretation = ProjectDocument.Interpretation(
            fields: ProjectInterpretation(overview: "A small application."),
            agentName: "Claude Code"
        )
        let markdown = try ProjectDocument(model: model(), interpretation: interpretation).markdown()

        #expect(markdown.contains(ProjectDocument.overviewStart))
        #expect(markdown.contains(ProjectDocument.overviewEnd))
        #expect(markdown.contains("Interpretation from Claude Code"))
        // Unattributed prose in a file of measured facts reads as another fact.
        #expect(markdown.contains("Keel checked its shape, not its claims"))
        #expect(markdown.contains("A small application."))
    }

    @Test("Keel writes the headings, not the agent")
    func keelOwnsTheStructure() throws {
        let interpretation = ProjectDocument.Interpretation(
            fields: ProjectInterpretation(
                overview: "Overview.",
                dataFlow: "Flow.",
                conventions: ["One convention."],
                risks: ["One risk."],
                onboarding: ["Start here."]
            ),
            agentName: "Agent"
        )
        let markdown = try ProjectDocument(model: model(), interpretation: interpretation).markdown()

        // The agent supplies field values; every heading around them is Keel's.
        for heading in ["### Data flow", "### Conventions noticed",
                        "### Worth being careful about", "### Where to start"] {
            #expect(markdown.contains(heading), "missing \(heading)")
        }
    }

    @Test("An interpretation adds a section and changes nothing else")
    func leavesDerivedSectionsAlone() throws {
        let model = try model()
        let plain = ProjectDocument(model: model).markdown()
        let withAI = ProjectDocument(
            model: model,
            interpretation: .init(fields: ProjectInterpretation(overview: "Prose."), agentName: "Agent")
        ).markdown()

        #expect(!plain.contains(ProjectDocument.overviewStart))

        let start = try #require(withAI.range(of: ProjectDocument.overviewStart))
        let end = try #require(withAI.range(of: ProjectDocument.overviewEnd))
        var cut = end.upperBound
        if withAI[cut...].hasPrefix("\n\n") {
            cut = withAI.index(cut, offsetBy: 2)
        }
        var stripped = withAI
        stripped.removeSubrange(start.lowerBound..<cut)

        #expect(stripped == plain)
    }

    @Test("Without an interpretation the document is byte-identical to before the AI layer")
    func defaultIsUnchanged() throws {
        let model = try model()
        // Determinism is the default; --ai is the only thing that breaks it,
        // and only inside its own fence.
        #expect(ProjectDocument(model: model).markdown()
                == ProjectDocument(model: model, interpretation: nil).markdown())
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
            #expect(result.standardOutput.contains("single JSON object"))
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

// MARK: - Validating what an agent hands back

/// The agent returns data and Keel writes the Markdown, so this is the layer
/// that has to survive an agent which ignores instructions.
@Suite("ProjectInterpretation")
struct ProjectInterpretationTests {

    @Test("A well-formed reply parses into fields")
    func parsesFields() throws {
        let parsed = try ProjectInterpretation.parse("""
            {"overview": "A small app.", "dataFlow": "View to view model.",
             "conventions": ["One."], "risks": ["Two."], "onboarding": ["Three."]}
            """)

        #expect(parsed.overview == "A small app.")
        #expect(parsed.dataFlow == "View to view model.")
        #expect(parsed.conventions == ["One."])
        #expect(parsed.risks == ["Two."])
        #expect(parsed.onboarding == ["Three."])
    }

    @Test("A fenced reply with preamble still parses")
    func toleratesWrapping() throws {
        // Wrapping JSON in a code block and a sentence is a formatting habit,
        // not a refusal, and failing on it would make the feature unusable.
        let parsed = try ProjectInterpretation.parse("""
            Sure! Here is the JSON:
            ```json
            {"overview": "A small app."}
            ```
            Let me know if you need more.
            """)

        #expect(parsed.overview == "A small app.")
    }

    @Test("Markdown an agent adds is stripped, because Keel owns the structure")
    func stripsMarkdown() throws {
        let parsed = try ProjectInterpretation.parse("""
            {"overview": "## Injected heading", "conventions": ["- bulleted", "**bold**"]}
            """)

        // A `##` arriving in a field would open a section indistinguishable
        // from one Keel wrote.
        #expect(parsed.overview == "Injected heading")
        #expect(parsed.conventions == ["bulleted", "bold"])
    }

    @Test("Blank and whitespace-only entries are dropped rather than rendered")
    func dropsEmptyEntries() throws {
        let parsed = try ProjectInterpretation.parse("""
            {"overview": "   ", "conventions": ["Real.", "   ", ""]}
            """)

        #expect(parsed.overview == nil)
        #expect(parsed.conventions == ["Real."])
    }

    @Test("One field cannot become the whole document")
    func enforcesLimits() throws {
        let long = String(repeating: "a", count: 5_000)
        let many = (1...40).map { "\"item \($0)\"" }.joined(separator: ",")
        let parsed = try ProjectInterpretation.parse(
            "{\"overview\": \"\(long)\", \"risks\": [\(many)]}"
        )

        let overview = try #require(parsed.overview)
        #expect(overview.count <= ProjectInterpretation.Limit.prose + 1)
        #expect(overview.hasSuffix("…"))
        #expect(parsed.risks.count == ProjectInterpretation.Limit.items)
    }

    @Test("A partial reply is a partial answer, not a failure")
    func acceptsPartialReplies() throws {
        let parsed = try ProjectInterpretation.parse("{\"risks\": [\"Only this.\"]}")

        #expect(parsed.overview == nil)
        #expect(parsed.risks == ["Only this."])
        #expect(!parsed.isEmpty)
    }

    @Test("A reply that is not the requested object is refused")
    func refusesProse() {
        #expect(throws: ProjectInterpretation.ParseError.notJSON) {
            try ProjectInterpretation.parse("Sure, here is a nice paragraph about your project.")
        }
        #expect(throws: ProjectInterpretation.ParseError.notJSON) {
            try ProjectInterpretation.parse("{ not json at all }")
        }
    }

    @Test("A reply with nothing usable in it is refused rather than rendered empty")
    func refusesEmptyObjects() {
        #expect(throws: ProjectInterpretation.ParseError.empty) {
            try ProjectInterpretation.parse("{}")
        }
        #expect(throws: ProjectInterpretation.ParseError.empty) {
            try ProjectInterpretation.parse("{\"overview\": \"\", \"risks\": []}")
        }
    }

    @Test("Fields round-trip through Codable")
    func isCodable() throws {
        let original = ProjectInterpretation(
            overview: "A.", dataFlow: "B.", conventions: ["C."], risks: ["D."], onboarding: ["E."]
        )
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(ProjectInterpretation.self, from: data) == original)
    }
}

// MARK: - Freshness

/// A Markdown diff says lines moved; it cannot say a feature was added. The
/// fingerprint is what lets `--check` answer the second question.
@Suite("DocumentFingerprint")
struct DocumentFingerprintTests {

    private let console = Console(useColor: false)

    private func withProject<T>(_ body: (URL) throws -> T) throws -> T {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-fresh-\(UUID().uuidString)")
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

    @Test("A document carries a fingerprint that survives a round trip")
    func embedsAndExtracts() throws {
        try withProject { root in
            let model = try ProjectScanner(root: root).scan()
            let markdown = ProjectDocument(model: model).markdown()

            let extracted = try #require(DocumentFingerprint.extract(from: markdown))
            #expect(extracted == DocumentFingerprint(model: model))
            // Invisible when rendered: it lives in a comment.
            #expect(markdown.contains("<!-- keel:fingerprint "))
        }
    }

    @Test("An unchanged project reports no changes")
    func detectsNoChange() throws {
        try withProject { root in
            let model = try ProjectScanner(root: root).scan()
            let fingerprint = DocumentFingerprint(model: model)
            #expect(fingerprint.changes(to: fingerprint).isEmpty)
        }
    }

    @Test("Adding a feature is reported as adding that feature")
    func namesWhatChanged() throws {
        try withProject { root in
            let before = DocumentFingerprint(model: try ProjectScanner(root: root).scan())

            _ = try FeatureGenerator(
                model: try ProjectScanner(root: root).scan(), console: console
            ).generate(named: "Profile")

            let after = DocumentFingerprint(model: try ProjectScanner(root: root).scan())
            #expect(before.changes(to: after).contains("Added feature Profile"))
        }
    }

    @Test("Removals are reported too, not only additions")
    func reportsRemovals() throws {
        try withProject { root in
            let before = DocumentFingerprint(model: try ProjectScanner(root: root).scan())

            try FileManager.default.removeItem(
                at: root.appendingPathComponent("Probe/Features/Articles")
            )

            let after = DocumentFingerprint(model: try ProjectScanner(root: root).scan())
            #expect(before.changes(to: after).contains("Removed feature Articles"))
        }
    }

    @Test("An architecture verdict changing is a reason to re-read the document")
    func reportsArchitectureChanges() throws {
        let before = DocumentFingerprint(model: try model(architecture: "MVVM"))
        let after = DocumentFingerprint(model: try model(architecture: "UIKit MVC"))

        #expect(before.changes(to: after).contains {
            $0.contains("Presentation changed from MVVM to UIKit MVC")
        })
    }

    /// A model differing only in its presentation verdict.
    private func model(architecture value: String) throws -> ProjectModel {
        ProjectModel(
            name: "Probe", rootPath: "/tmp/Probe", workspacePath: nil,
            projects: [], schemes: [], dependencies: [], configurations: [],
            modules: [], features: [],
            source: SourceSummary(
                swiftFileCount: 1, lineCount: 1,
                importsSwiftUI: value == "MVVM", importsUIKit: value != "MVVM",
                usesObservationMacro: false, usesObservableObject: false,
                usesAsyncAwait: false, usesCombine: false,
                usesSwiftData: false, usesCoreData: false,
                usesSwiftTesting: false, usesXCTest: false
            ),
            analysis: SourceAnalysis(files: []),
            architecture: Architecture(
                presentation: Finding(value: value == "MVVM" ? .mvvm : .mvc,
                                      support: .observed, evidence: []),
                organisation: Finding(value: .unknown, support: .undetermined, evidence: []),
                featureLayering: Finding(value: .unknown, support: .undetermined, evidence: []),
                observation: Finding(value: .unknown, support: .undetermined, evidence: []),
                concurrency: Finding(value: .unknown, support: .undetermined, evidence: []),
                persistence: Finding(value: .unknown, support: .undetermined, evidence: []),
                wiring: Finding(value: .unknown, support: .undetermined, evidence: [])
            )
        )
    }

    @Test("A document with no fingerprint yields nothing rather than a guess")
    func refusesToGuess() {
        // Hand-written, or from a Keel too old to leave one. "Cannot tell" is
        // the honest answer and the command says so.
        #expect(DocumentFingerprint.extract(from: "# My notes\n\nWritten by hand.") == nil)
        #expect(DocumentFingerprint.extract(from: "<!-- keel:fingerprint not json -->") == nil)
    }
}
