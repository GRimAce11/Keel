import Foundation
import Testing
@testable import KeelKit

/// Built from synthetic sources through both real builders, so the join is
/// exercised rather than mocked. The integration against a generated project
/// is at the bottom.
@Suite("DependencyGraph")
struct DependencyGraphTests {

    // MARK: - Fixtures

    private static let app = Target(
        name: "App", productType: .application, bundleIdentifier: nil,
        deploymentTarget: nil, swiftVersion: nil, platform: nil, strictConcurrency: nil
    )

    private func target(_ name: String, _ type: ProductType = .application) -> Target {
        Target(
            name: name, productType: type, bundleIdentifier: nil,
            deploymentTarget: nil, swiftVersion: nil, platform: nil, strictConcurrency: nil
        )
    }

    private func file(_ path: String, _ source: String) -> FileAnalysis {
        SwiftSourceAnalyzer().analyze(source: source, path: path)
    }

    private func module(_ name: String, _ path: String, _ role: Module.Role = .other) -> Module {
        Module(name: name, path: path, swiftFileCount: 1, role: role)
    }

    private func feature(_ name: String, _ path: String, layers: [String] = []) -> Feature {
        Feature(name: name, path: path, layers: layers, swiftFileCount: 1)
    }

    /// Both graphs, then the join — exactly as `ProjectScanner` wires them,
    /// including that the type graph reads production code only.
    private func build(
        targets: [Target] = [app],
        modules: [Module] = [],
        features: [Feature] = [],
        packageProducts: Set<String> = [],
        files: [FileAnalysis]
    ) -> DependencyGraph {
        let analysis = SourceAnalysis(files: files)
        return DependencyGraphBuilder(inputs: .init(
            importGraph: ImportGraphBuilder(model: .init(
                rootPath: "/tmp/App",
                targets: targets,
                modules: modules,
                features: features,
                packages: [],
                packageProducts: packageProducts,
                analysis: analysis
            )).build(),
            typeGraph: TypeGraphBuilder(inputs: .init(
                targets: targets,
                modules: modules,
                features: features,
                analysis: analysis.excludingTests()
            )).build(),
            modules: modules
        )).build()
    }

    /// Two features, each with one type, the first naming the second.
    private func twoFeatures(crossing: Bool) -> DependencyGraph {
        build(
            features: [feature("Profile", "App/Features/Profile"), feature("Settings", "App/Features/Settings")],
            files: [
                file("App/Features/Profile/ProfileViewModel.swift", crossing ? """
                    final class ProfileViewModel {
                        let settings: SettingsStore
                    }
                    """ : "final class ProfileViewModel {}\n"),
                file("App/Features/Settings/SettingsStore.swift", "struct SettingsStore {}\n"),
            ]
        )
    }

    // MARK: - Direct dependencies

    @Test("A type in one feature naming a type in another is a feature dependency")
    func findsDirectDependencies() {
        let graph = twoFeatures(crossing: true)
        let edges = graph.edges(at: .feature)

        #expect(edges.count == 1)
        #expect(edges[0].from == "Profile")
        #expect(edges[0].to == "Settings")
        #expect(graph.dependencies(of: "Profile", at: .feature) == ["Settings"])
    }

    @Test("The same facts answer at whichever scope is asked for")
    func aggregatesAtEveryScope() {
        let graph = build(
            modules: [module("Features", "App/Features", .features)],
            features: [feature("Profile", "App/Features/Profile", layers: ["Domain", "Presentation"])],
            files: [
                file("App/Features/Profile/Presentation/ProfileView.swift", """
                    struct ProfileView {
                        let model: ProfileModel
                    }
                    """),
                file("App/Features/Profile/Domain/ProfileModel.swift", "struct ProfileModel {}\n"),
            ]
        )

        #expect(graph.edges(at: .type).map(\.to) == ["ProfileModel"])
        #expect(graph.edges(at: .file).map(\.to) == ["App/Features/Profile/Domain/ProfileModel.swift"])
        #expect(graph.edges(at: .layer).map { "\($0.from)→\($0.to)" } == ["Presentation→Domain"])
        // One feature, one module: nothing crosses either, so neither has an edge.
        #expect(graph.edges(at: .feature).isEmpty)
        #expect(graph.edges(at: .module).isEmpty)
    }

    @Test("A dependency reached through something else is still a dependency")
    func findsTransitiveDependencies() {
        let graph = build(
            features: [
                feature("Profile", "App/Features/Profile"),
                feature("Session", "App/Features/Session"),
                feature("Storage", "App/Features/Storage"),
            ],
            files: [
                file("App/Features/Profile/ProfileViewModel.swift", """
                    final class ProfileViewModel { let session: SessionService }
                    """),
                file("App/Features/Session/SessionService.swift", """
                    final class SessionService { let store: TokenStore }
                    """),
                file("App/Features/Storage/TokenStore.swift", "struct TokenStore {}\n"),
            ]
        )

        #expect(graph.dependencies(of: "Profile", at: .feature) == ["Session"])
        #expect(graph.transitiveDependencies(of: "Profile", at: .feature) == ["Session", "Storage"])
    }

    // MARK: - Self dependencies

    @Test("A feature whose own files refer to each other does not depend on itself")
    func dropsSelfDependencies() {
        // It has more than one file, which is not the same as having a
        // dependency. The links are still there to read at file scope.
        let graph = build(
            features: [feature("Profile", "App/Features/Profile")],
            files: [
                file("App/Features/Profile/ProfileView.swift", """
                    struct ProfileView { let model: ProfileViewModel }
                    """),
                file("App/Features/Profile/ProfileViewModel.swift", "final class ProfileViewModel {}\n"),
            ]
        )

        #expect(graph.edges(at: .feature).isEmpty)
        #expect(graph.edges(at: .file).count == 1)
    }

    @Test("A type referring to itself is not a dependency at any scope")
    func ignoresSelfReference() {
        let graph = build(files: [
            file("App/A.swift", """
                struct Node {
                    let next: Node?
                }
                """),
        ])

        #expect(graph.edges(at: .type).isEmpty)
    }

    // MARK: - Cycles

    @Test("Two features referring to each other are a cycle imports cannot see")
    func findsCyclesImportsCannotSee() {
        // The whole reason this graph exists. Both features compile into one
        // module, so no import crosses between them and an import-only graph
        // is silent by construction.
        let graph = build(
            features: [feature("Profile", "App/Features/Profile"), feature("Session", "App/Features/Session")],
            files: [
                file("App/Features/Profile/ProfileViewModel.swift", """
                    final class ProfileViewModel { let session: SessionService }
                    """),
                file("App/Features/Session/SessionService.swift", """
                    final class SessionService { let profile: ProfileViewModel }
                    """),
            ]
        )

        let cycles = graph.cycles(at: .feature)
        #expect(cycles.count == 1)
        #expect(Set(cycles[0]) == ["Profile", "Session"])
    }

    @Test("A one-way dependency is not a cycle")
    func doesNotInventCycles() {
        #expect(twoFeatures(crossing: true).cycles(at: .feature).isEmpty)
    }

    @Test("A cycle shows up at module scope too, when modules are what cross")
    func findsModuleCycles() {
        let graph = build(
            modules: [module("Core", "App/Core", .core), module("Chat", "App/Chat")],
            files: [
                file("App/Core/Logger.swift", "struct Logger { let room: ChatRoom }\n"),
                file("App/Chat/ChatRoom.swift", "struct ChatRoom { let logger: Logger }\n"),
            ]
        )

        #expect(Set(graph.cycles(at: .module).first ?? []) == ["Core", "Chat"])
    }

    // MARK: - Cross-feature

    @Test("A cross-feature dependency is an edge, not a fault")
    func refusesToJudgeCrossFeature() {
        // Nothing in a project layout establishes that one feature may not use
        // another. Calling every such edge a violation would be a guess
        // dressed as a rule.
        let graph = twoFeatures(crossing: true)

        #expect(!graph.edges(at: .feature).isEmpty)
        #expect(graph.violations.isEmpty)
    }

    @Test("Shared code depending on a feature is a fault, and the reverse is not")
    func judgesOnlyWhereDirectionIsEstablished() {
        let wrongWay = build(
            modules: [module("Core", "App/Core", .core), module("Features", "App/Features", .features)],
            features: [feature("Profile", "App/Features/Profile")],
            files: [
                file("App/Core/Analytics.swift", "struct Analytics { let state: ProfileState }\n"),
                file("App/Features/Profile/ProfileState.swift", "struct ProfileState {}\n"),
            ]
        )
        #expect(wrongWay.violations.map(\.rule) == [.sharedCodeDependsOnFeature])
        #expect(wrongWay.violations[0].from == "Core")
        #expect(wrongWay.violations[0].to == "Profile")

        let rightWay = build(
            modules: [module("Core", "App/Core", .core), module("Features", "App/Features", .features)],
            features: [feature("Profile", "App/Features/Profile")],
            files: [
                file("App/Core/Analytics.swift", "struct Analytics {}\n"),
                file("App/Features/Profile/ProfileState.swift", "struct ProfileState { let analytics: Analytics }\n"),
            ]
        )
        #expect(rightWay.violations.isEmpty)
    }

    // MARK: - Imports

    @Test("A test bundle importing the app is a target dependency")
    func findsTargetDependencies() {
        let graph = build(
            targets: [target("App"), target("AppTests", .unitTestBundle)],
            files: [
                file("AppTests/ProfileTests.swift", "@testable import App\n"),
                file("App/Profile.swift", "struct Profile {}\n"),
            ]
        )

        let edges = graph.edges(at: .target)
        #expect(edges.map { "\($0.from)→\($0.to)" } == ["AppTests→App"])
        #expect(edges[0].origins == [.importStatement])
    }

    @Test("Test sources contribute imports but no type references")
    func keepsTestsOutOfTheTypeSide() {
        // The type graph is production-only so a stub cannot invent
        // architecture. The import side keeps tests, because "what does the
        // test bundle link" is a real question.
        let graph = build(
            targets: [target("App"), target("AppTests", .unitTestBundle)],
            files: [
                file("AppTests/ProfileTests.swift", """
                    import Foundation
                    struct StubRepository { let profile: Profile }
                    """),
                file("App/Profile.swift", "struct Profile {}\n"),
            ]
        )

        #expect(graph.links.allSatisfy { $0.origin == .importStatement })
        #expect(graph.edges(at: .type).isEmpty)
    }

    @Test("A module Keel cannot place is still a node, not a silence")
    func keepsUnknownModules() {
        let graph = build(files: [file("App/Net.swift", "import SomeVendorSDK\n")])

        let external = graph.edges(at: .target, includingExternal: true)
        #expect(external.map(\.to) == ["SomeVendorSDK"])
        // Outside the project, so left out unless asked for.
        #expect(graph.edges(at: .target).isEmpty)
    }

    @Test("Something outside the project is one node at every scope")
    func namesExternalDependenciesConsistently() {
        // An import is the whole of what Keel knows about `SwiftData`. It has
        // no file, no feature and no layer, and inventing one would be worse
        // than naming it plainly.
        let graph = build(
            features: [feature("Profile", "App/Features/Profile")],
            files: [file("App/Features/Profile/Store.swift", "import SwiftData\nstruct Store {}\n")]
        )

        #expect(graph.edges(at: .feature, includingExternal: true).map(\.to) == ["SwiftData"])
        #expect(graph.edges(at: .module, includingExternal: true).isEmpty)
    }

    // MARK: - The join

    @Test("An import and a type reference to the same place are one edge with two origins")
    func joinsBothSources() {
        let graph = build(
            targets: [target("App"), target("Core", .framework)],
            modules: [module("App", "App", .app), module("Core", "Core", .core)],
            files: [
                file("App/Root.swift", "import Core\nstruct Root { let logger: Logger }\n"),
                file("Core/Logger.swift", "struct Logger {}\n"),
            ]
        )

        let edges = graph.edges(at: .module).filter { $0.from == "App" && $0.to == "Core" }
        #expect(edges.count == 1)
        #expect(edges[0].origins == [.importStatement, .typeReference])
    }

    // MARK: - Evidence

    @Test("Every edge can be unfolded into the lines that produced it")
    func carriesEvidence() {
        let graph = twoFeatures(crossing: true)
        let edge = graph.edges(at: .feature)[0]

        #expect(edge.evidence.count == 1)
        #expect(edge.evidence[0].location == "App/Features/Profile/ProfileViewModel.swift:2")
        #expect(edge.evidence[0].describedInFull == "ProfileViewModel → SettingsStore  property")
        #expect(edge.evidence[0].support == .observed)
    }

    @Test("A tree gives each node its direct dependencies, in order")
    func drawsATree() {
        let graph = build(
            features: [
                feature("Profile", "App/Features/Profile"),
                feature("Session", "App/Features/Session"),
                feature("Storage", "App/Features/Storage"),
            ],
            files: [
                file("App/Features/Profile/ProfileViewModel.swift", """
                    final class ProfileViewModel {
                        let session: SessionService
                        let store: TokenStore
                    }
                    """),
                file("App/Features/Session/SessionService.swift", "struct SessionService {}\n"),
                file("App/Features/Storage/TokenStore.swift", "struct TokenStore {}\n"),
            ]
        )

        let tree = graph.tree(at: .feature)
        #expect(tree.map(\.name) == ["Profile"])
        #expect(tree[0].dependencies.map(\.to) == ["Session", "Storage"])
    }

    // MARK: - Contract

    @Test("The graph comes back in the same order every time")
    func isDeterministic() {
        #expect(twoFeatures(crossing: true) == twoFeatures(crossing: true))
    }

    @Test("A project with nothing in it yields an empty graph rather than failing")
    func survivesAnEmptyProject() {
        #expect(build(files: []) == .empty)
        #expect(DependencyGraph.empty.cycles(at: .feature).isEmpty)
        #expect(DependencyGraph.empty.tree(at: .module).isEmpty)
    }

    @Test("The graph round-trips through Codable, for --graph --json")
    func isCodable() throws {
        let graph = twoFeatures(crossing: true)
        let data = try JSONEncoder().encode(graph)
        #expect(try JSONDecoder().decode(DependencyGraph.self, from: data) == graph)
    }
}

// MARK: - Against a real project

@Suite("Dependency graph of generated projects")
struct GeneratedDependencyGraphTests {

    private let console = Console(useColor: false)

    private func model() throws -> ProjectModel {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-deps-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let configuration = ProjectConfiguration(
            name: try ProjectName("Probe"),
            bundleIdentifierPrefix: "com.acme",
            components: Set(Component.allCases)
        )
        let outcome = try ProjectGenerator(configuration: configuration, console: console)
            .generate(in: destination, initializeGit: false)
        return try ProjectScanner(root: outcome.projectDirectory).scan()
    }

    @Test("The generated project's modules depend on each other the way it is built")
    func readsTheRealProject() throws {
        let graph = try model().dependencyGraph()
        let edges = Set(graph.edges(at: .module).map { "\($0.from)→\($0.to)" })

        #expect(edges.contains("Features→Core"))
        #expect(edges.contains("App→Core"))
        // Shared code is used by features, not the other way round.
        #expect(!edges.contains("Core→Features"))
    }

    @Test("A generated project has no cycles in its architecture")
    func hasNoCycles() throws {
        let graph = try model().dependencyGraph()

        for scope in DependencyScope.structural {
            #expect(graph.cycles(at: scope).isEmpty, "cycle at \(scope.displayName) scope")
        }
    }

    @Test("A loop between a protocol and its conformer is ordinary, not architecture")
    func doesNotTreatTypeLoopsAsArchitecture() throws {
        // The generated project has one: `APIClient` conforms to
        // `APIClientProtocol`, whose methods take an `APIEndpoint`, whose
        // timeout reads `APIClient.Defaults`. Perfectly normal Swift — types
        // in one module refer to each other and the compiler does not mind.
        //
        // So cycles are only reported at the scopes where a loop means
        // something went wrong. Reporting this one would teach people to
        // ignore the section that also carries the real ones.
        let graph = try model().dependencyGraph()

        #expect(!graph.cycles(at: .type).isEmpty)
        #expect(!DependencyScope.structural.contains(.type))
    }

    @Test("A generated project runs with the grain")
    func hasNoViolations() throws {
        #expect(try model().dependencyGraph().violations.isEmpty)
    }

    @Test("Every link points at a line in a file")
    func carriesRealEvidence() throws {
        let graph = try model().dependencyGraph()

        #expect(!graph.links.isEmpty)
        #expect(graph.links.allSatisfy { $0.line > 0 && !$0.file.isEmpty })
    }

    @Test("The graph is derived, so it is not in the model's own JSON")
    func staysOutOfTheModel() throws {
        // It is a join of two graphs the model already holds. Storing it would
        // put the same facts in `--json` three times, with room to disagree.
        let model = try model()
        let encoded = String(decoding: try JSONEncoder().encode(model), as: UTF8.self)

        #expect(!encoded.contains("\"violations\""))
        #expect(!model.dependencyGraph().links.isEmpty)
    }
}
