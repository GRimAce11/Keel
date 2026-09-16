import Foundation
import Testing
@testable import KeelKit

/// The claims the model makes about itself.
///
/// Every command reads one `ProjectModel`, so two of them cannot describe the
/// same project differently — that is the promise, and these are the tests
/// that would catch it being broken. They assert relationships between
/// outputs rather than the outputs themselves, so they keep working when the
/// wording changes and fail when the facts come apart.
@Suite("Model coherence")
struct ModelCoherenceTests {

    private let console = Console(useColor: false)

    private func scan(damage: (URL) throws -> Void = { _ in }) throws -> ProjectModel {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let configuration = ProjectConfiguration(
            name: try ProjectName("Probe"),
            bundleIdentifierPrefix: "com.acme",
            components: Set(Component.allCases)
        )
        let outcome = try ProjectGenerator(configuration: configuration, console: console)
            .generate(in: destination, initializeGit: false)
        try damage(outcome.projectDirectory)
        return try ProjectScanner(root: outcome.projectDirectory).scan()
    }

    private func write(_ source: String, to path: String, in root: URL) throws {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try source.write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: - One source of truth

    @Test("What `document` writes is what the model holds")
    func documentMatchesTheModel() throws {
        let model = try scan()
        let markdown = ProjectDocument(model: model).markdown()

        // Every architecture verdict, with the basis it was reached on.
        for finding in model.architecture.findings {
            #expect(markdown.contains(finding.value), "missing verdict: \(finding.value)")
            if finding.support != .undetermined {
                #expect(markdown.contains(finding.sourceSummary),
                        "missing basis for \(finding.dimension)")
            }
        }
        for feature in model.features {
            #expect(markdown.contains(feature.name))
        }
    }

    @Test("What `check` reports is read from the same graphs `inspect` prints")
    func checkMatchesTheModel() throws {
        // A finding naming a type the type graph does not have would mean the
        // checker built its own view of the project.
        let model = try scan { root in
            try write(
                """
                import SwiftUI
                import SwiftData

                struct StoredItemView: View {
                    let item: StoredItem
                    var body: some View { Text("x") }
                }
                """,
                to: "Probe/Features/Articles/Presentation/StoredItemView.swift",
                in: root
            )
        }

        let diagnostics = ProjectChecker(model: model).check()
        let relationship = try #require(diagnostics.first { $0.rule == "view-reaches-persistence" })

        #expect(model.typeGraph.node(named: "StoredItemView") != nil)
        for item in relationship.evidence {
            #expect(model.typeGraph.references.contains { $0.location == item.location },
                    "evidence not in the type graph: \(item.location)")
        }
    }

    @Test("The document's rules and the checker's rules describe the same types")
    func documentAndCheckerAgree() throws {
        // The guarantee these two make together: following PROJECT.md and
        // passing `keel check` cannot come apart. They can only keep it if
        // they are talking about the same set of types — so both ask the type
        // graph rather than each deriving a set from a suffix.
        let model = try scan { root in
            try write(
                """
                import Foundation

                @MainActor
                @Observable
                final class ArticlePresenter {
                    var title = ""
                }
                """,
                to: "Probe/Features/Articles/Presentation/ArticlePresenter.swift",
                in: root
            )
        }

        // A presenter is a view model by role and not by suffix, which is
        // exactly the case that used to split the two apart.
        #expect(model.typeGraph.node(named: "ArticlePresenter")?.role == .viewModel)

        let rules = ProjectContext(model: model).architectureRules()
        let diagnostics = ProjectChecker(model: model).check()

        // The document promises view models are @MainActor, and this one is —
        // so the checker must have nothing to say about it.
        #expect(rules.contains("View models are `@MainActor`."))
        #expect(!diagnostics.contains {
            $0.rule.hasPrefix("view-model") && $0.message.contains("ArticlePresenter")
        })
    }

    @Test("The architecture verdict and the roles behind it agree about the project")
    func architectureAgreesWithRoles() throws {
        let model = try scan()

        // The detector reports MVVM because views reach view models. If the
        // graph had no view models, the two would be describing different
        // projects.
        #expect(model.architecture.presentation.value == .mvvm)
        #expect(!model.typeGraph.types(inRole: .viewModel).isEmpty)
        #expect(!model.typeGraph.types(inRole: .view).isEmpty)
    }

    @Test("Every architecture location points at a file the scan actually read")
    func evidenceIsTraceable() throws {
        let model = try scan()
        let known = Set(model.analysis.files.map(\.path))

        for finding in model.architecture.findings {
            for item in finding.evidence {
                for location in item.locations {
                    let file = String(location.split(separator: ":").dropLast().joined(separator: ":"))
                    #expect(known.contains(file), "\(finding.dimension): unknown file \(file)")
                }
            }
        }
    }

    @Test("Every finding says what kind of evidence it rests on")
    func everyFindingCarriesItsBasis() throws {
        let model = try scan()

        for finding in model.architecture.findings {
            if finding.support == .undetermined {
                #expect(finding.bases.isEmpty, "\(finding.dimension) is undetermined but has a basis")
            } else {
                #expect(!finding.bases.isEmpty, "\(finding.dimension) has support but no basis")
                #expect(!finding.evidence.isEmpty, "\(finding.dimension) has support but no evidence")
            }
        }
    }

    // MARK: - Determinism

    @Test("Two scans of the same project produce the same model")
    func scanningIsDeterministic() throws {
        // Files are parsed in parallel, so nothing may depend on the order
        // they finish in.
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-determinism-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let outcome = try ProjectGenerator(
            configuration: ProjectConfiguration(
                name: try ProjectName("Probe"),
                bundleIdentifierPrefix: "com.acme",
                components: Set(Component.allCases)
            ),
            console: console
        ).generate(in: destination, initializeGit: false)

        let first = try ProjectScanner(root: outcome.projectDirectory).scan()
        let second = try ProjectScanner(root: outcome.projectDirectory).scan()

        #expect(first.typeGraph == second.typeGraph)
        #expect(first.importGraph == second.importGraph)
        #expect(first.architecture == second.architecture)
        #expect(first.dependencyGraph() == second.dependencyGraph())
    }

    @Test("JSON is byte-identical across runs")
    func serialisationIsStable() throws {
        let model = try scan()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let first = try encoder.encode(model)
        let second = try encoder.encode(model)
        #expect(first == second)

        // And what `--json` prints decodes back to the same model.
        #expect(try JSONDecoder().decode(ProjectModel.self, from: first) == model)
    }

    // MARK: - Fingerprint

    @Test("An unchanged project produces an unchanged fingerprint")
    func fingerprintIsStable() throws {
        let model = try scan()
        let first = DocumentFingerprint(model: model)
        let second = DocumentFingerprint(model: model)

        #expect(first == second)
        #expect(first.changes(to: second).isEmpty)
        #expect(first.embedded() == second.embedded())
    }

    @Test("A new dependency between features is a change worth regenerating for")
    func fingerprintNoticesCoupling() throws {
        let before = DocumentFingerprint(model: try scan())
        let after = DocumentFingerprint(model: try scan { root in
            try write(
                "import Foundation\n\nstruct SettingsState { var last: Article? }\n",
                to: "Probe/Features/Settings/SettingsState.swift",
                in: root
            )
        })

        #expect(before.changes(to: after).contains { $0.contains("Settings → Articles") })
    }

    @Test("A new dependency between modules is a change worth regenerating for")
    func fingerprintNoticesModuleCoupling() throws {
        // The diagram in "How it fits together" draws module edges, so a
        // document whose diagram no longer matches the project has to come
        // back stale. Before these were fingerprinted it did not.
        let before = DocumentFingerprint(model: try scan())
        let after = DocumentFingerprint(model: try scan { root in
            try write(
                "import SwiftUI\n\nstruct ArticleBadge: View {\n"
                    + "    let article: Article\n"
                    + "    var body: some View { Text(article.title) }\n}\n",
                to: "Probe/Shared/UI/ArticleBadge.swift",
                in: root
            )
        })

        #expect(before.changes(to: after).contains { $0.contains("Shared → Features") })
    }

    @Test("A fingerprint from an older Keel still reads, as stale rather than unreadable")
    func fingerprintDecodesOlderDocuments() throws {
        // Written before featureDependencies existed. Refusing it would turn
        // "this document is out of date" into "this document is broken".
        let older = """
            <!-- keel:fingerprint {"architecture":{"Presentation":"MVVM"},"dependencies":[],\
            "features":["Articles"],"modules":["App"],"swiftFileCount":10,"targets":["Probe"]} -->
            """

        let decoded = try #require(DocumentFingerprint.extract(from: older))
        #expect(decoded.features == ["Articles"])
        #expect(decoded.featureDependencies.isEmpty)
        // Added later still, when the document started drawing them.
        #expect(decoded.moduleDependencies.isEmpty)
        #expect(decoded.layerDependencies.isEmpty)
    }

    // MARK: - The line AI may not cross

    @Test("Nothing in the deterministic model can have come from an agent")
    func noAIFactReachesTheModel() throws {
        // The rule the whole tool rests on. A scan takes a directory and
        // nothing else — no policy, no agent, no network — so there is no
        // route for an interpretation to arrive in these fields.
        let model = try scan()
        let json = String(decoding: try JSONEncoder().encode(model), as: UTF8.self)

        for marker in ["interpretation", "overview", "agent", "claude", "codex", "gemini", "ollama"] {
            #expect(!json.lowercased().contains(marker), "\(marker) reached the deterministic model")
        }
    }
}
