import Foundation
import Testing
@testable import KeelKit

/// The graph is built from synthetic inputs here, so each case is exactly one
/// thing. Integration against a real generated project is at the bottom.
@Suite("ImportGraph")
struct ImportGraphTests {

    // MARK: - Fixtures

    private func target(_ name: String, _ type: ProductType = .application) -> Target {
        Target(
            name: name, productType: type, bundleIdentifier: nil,
            deploymentTarget: nil, swiftVersion: nil, platform: nil, strictConcurrency: nil
        )
    }

    private func file(_ path: String, _ source: String) -> FileAnalysis {
        SwiftSourceAnalyzer().analyze(source: source, path: path)
    }

    private func build(
        targets: [Target] = [Target(
            name: "App", productType: .application, bundleIdentifier: nil,
            deploymentTarget: nil, swiftVersion: nil, platform: nil, strictConcurrency: nil
        )],
        modules: [Module] = [],
        features: [Feature] = [],
        packages: [PackageDependency] = [],
        packageProducts: Set<String> = [],
        files: [FileAnalysis]
    ) -> ImportGraph {
        ImportGraphBuilder(model: .init(
            rootPath: "/tmp/App",
            targets: targets,
            modules: modules,
            features: features,
            packages: packages,
            packageProducts: packageProducts,
            analysis: SourceAnalysis(files: files)
        )).build()
    }

    private func module(_ name: String, _ path: String, _ role: Module.Role = .other) -> Module {
        Module(name: name, path: path, swiftFileCount: 1, role: role)
    }

    private func feature(_ name: String, _ path: String, layers: [String] = []) -> Feature {
        Feature(name: name, path: path, layers: layers, swiftFileCount: 1)
    }

    // MARK: - What an import names

    @Test("An Apple framework is system; the project's own target is project")
    func classifiesFrameworksAndProject() {
        let graph = build(files: [
            file("AppTests/X.swift", "import Foundation\nimport App\n"),
        ])

        let kinds = Dictionary(
            graph.edges.map { ($0.module, $0.kind) }, uniquingKeysWith: { first, _ in first }
        )
        #expect(kinds["Foundation"] == .system)
        #expect(kinds["App"] == .project)
    }

    @Test("A package is recognised by the product name the project links")
    func classifiesPackagesByProduct() {
        // The real case this exists for: the package is `socket.io-client-swift`
        // and the import says `SocketIO`. Matching the package name misses it.
        let graph = build(
            packages: [PackageDependency(
                name: "socket.io-client-swift", url: nil, requirement: nil, isLocal: false
            )],
            packageProducts: ["SocketIO"],
            files: [file("App/Net.swift", "import SocketIO\n")]
        )

        #expect(graph.edges.first?.kind == .package)
    }

    @Test("A module Keel cannot place is unknown, not assumed to be Apple's")
    func refusesToGuessUnknownModules() {
        // Defaulting to system would quietly relabel every in-house framework.
        let graph = build(files: [file("App/X.swift", "import SomeVendorSDK\n")])
        #expect(graph.edges.first?.kind == .unknown)
    }

    @Test("A target whose name needs sanitising is still recognised as project")
    func matchesSanitisedTargetNames() {
        // Swift cannot have spaces in a module name, so `Watch App` is imported
        // as `Watch_App`. Comparing raw names reports a project import as
        // unknown.
        let graph = build(
            targets: [target("App"), target("HitsRadio Watch App")],
            files: [file("App/X.swift", "import HitsRadio_Watch_App\n")]
        )

        #expect(graph.edges.first?.kind == .project)
    }

    @Test("A submodule import is classified by its root")
    func classifiesSubmodules() {
        let graph = build(files: [file("App/X.swift", "import os.log\n")])
        #expect(graph.edges.first?.kind == .system)
    }

    // MARK: - Evidence

    @Test("Every edge says which file and line said so")
    func carriesEvidence() {
        let graph = build(files: [
            file("App/Core/Client.swift", "import Foundation\n\nimport Network\n"),
        ])

        let network = try? #require(graph.edges.first { $0.module == "Network" })
        #expect(network?.line == 3)
        #expect(network?.location == "App/Core/Client.swift:3")
    }

    @Test("The same module imported twice in one file is two pieces of evidence")
    func keepsDuplicateImports() {
        // Not deduplicated: a duplicate import is a fact about the file, and
        // collapsing it would lose a line number.
        let graph = build(files: [
            file("App/X.swift", "import Foundation\nimport Foundation\n"),
        ])

        #expect(graph.edges.count == 2)
        #expect(graph.edges.map(\.line) == [1, 2])
    }

    // MARK: - Ownership

    @Test("A file inside a feature belongs to the feature, not the folder above it")
    func attributesToTheDeepestOwner() {
        let graph = build(
            modules: [module("Features", "App/Features", .features)],
            features: [feature("Profile", "App/Features/Profile", layers: ["Data", "Presentation"])],
            files: [file("App/Features/Profile/Data/Repo.swift", "import Foundation\n")]
        )

        let owner = graph.edges.first?.owner
        #expect(owner?.feature == "Profile")
        #expect(owner?.module == "Features")
        #expect(owner?.layer == "Data")
        #expect(owner?.owner == "Profile")
    }

    @Test("A file Keel cannot place still appears, owned by its target")
    func fallsBackToTheTarget() {
        // Without this a test bundle's `@testable import` vanishes, and that is
        // a real project edge.
        let graph = build(
            targets: [target("App"), target("AppTests", .unitTestBundle)],
            files: [file("AppTests/Support/Stub.swift", "import App\n")]
        )

        #expect(graph.edges.first?.owner.owner == "AppTests")
        #expect(graph.edges.first?.owner.feature == nil)
    }

    @Test("A file belonging to nothing at all is reported, not dropped")
    func toleratesUnknownOwnership() {
        let graph = build(files: [file("Scripts/Tool.swift", "import Foundation\n")])

        #expect(graph.edges.count == 1)
        #expect(graph.edges.first?.owner.owner == nil)
        // It has no owner, so it cannot appear under one.
        #expect(graph.dependencies().isEmpty)
    }

    @Test("A file that does not parse contributes nothing rather than failing")
    func survivesMalformedSource() {
        let graph = build(files: [
            file("App/Broken.swift", "import Foundation\nstruct Broken { func ("),
            file("App/Fine.swift", "import SwiftUI\n"),
        ])

        // SwiftParser recovers, so the import before the break is still found.
        #expect(graph.edges.map(\.module).sorted() == ["Foundation", "SwiftUI"])
    }

    // MARK: - Cycles

    @Test("A cycle between modules is found and named")
    func findsCycles() {
        let graph = build(
            targets: [target("Core"), target("Feature")],
            modules: [module("Core", "Core"), module("Feature", "Feature")],
            files: [
                file("Core/A.swift", "import Feature\n"),
                file("Feature/B.swift", "import Core\n"),
            ]
        )

        let cycles = graph.cycles()
        #expect(cycles.count == 1)
        #expect(Set(cycles[0]) == ["Core", "Feature"])
    }

    @Test("A one-way dependency is not a cycle")
    func doesNotInventCycles() {
        let graph = build(
            targets: [target("Core"), target("Feature")],
            modules: [module("Core", "Core"), module("Feature", "Feature")],
            files: [file("Feature/B.swift", "import Core\n")]
        )

        #expect(graph.cycles().isEmpty)
        #expect(graph.projectEdges().count == 1)
    }

    @Test("A single-module project says so, because it cannot have feature edges")
    func reportsSingleModule() {
        // The distinction that stops silence being read as "no coupling".
        let single = build(
            targets: [target("App"), target("AppTests", .unitTestBundle)],
            files: [file("App/X.swift", "import Foundation\n")]
        )
        #expect(single.isSingleModule)

        let modular = build(
            targets: [target("App"), target("Core", .framework)],
            files: [file("App/X.swift", "import Core\n")]
        )
        #expect(!modular.isSingleModule)
    }
}

// MARK: - Against a real project

@Suite("Import graph of generated projects")
struct GeneratedImportGraphTests {

    private let console = Console(useColor: false)

    private func model(
        components: Set<Component> = Set(Component.allCases)
    ) throws -> ProjectModel {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-graph-\(UUID().uuidString)")
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

    @Test("Features and modules are attributed, with evidence")
    func attributesRealFiles() throws {
        let graph = try model().importGraph
        let owners = Set(graph.dependencies().map(\.owner))

        #expect(owners.contains("Articles"))
        #expect(owners.contains("Core"))
        #expect(graph.edges.allSatisfy { $0.line > 0 })
    }

    @Test("The test bundle's @testable import is a project edge")
    func findsTheTestableImport() throws {
        let graph = try model().importGraph

        #expect(graph.projectEdges().contains { $0.from == "ProbeTests" && $0.to == "Probe" })
    }

    @Test("A generated project has no import cycles")
    func hasNoCycles() throws {
        #expect(try model().importGraph.cycles().isEmpty)
    }

    @Test("A generated project is one module, and says so")
    func isSingleModule() throws {
        #expect(try model().importGraph.isSingleModule)
    }

    @Test("The graph round-trips through Codable, for --json")
    func isCodable() throws {
        let graph = try model().importGraph
        let data = try JSONEncoder().encode(graph)
        #expect(try JSONDecoder().decode(ImportGraph.self, from: data) == graph)
    }
}
