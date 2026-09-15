import Foundation
import Testing
@testable import KeelKit

/// Built from synthetic sources, so each case is exactly one thing. The
/// integration against a real generated project is at the bottom.
@Suite("TypeGraph")
struct TypeGraphTests {

    // MARK: - Fixtures

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
        files: [FileAnalysis]
    ) -> TypeGraph {
        TypeGraphBuilder(inputs: .init(
            targets: targets,
            modules: modules,
            features: features,
            analysis: SourceAnalysis(files: files)
        )).build()
    }

    private func module(_ name: String, _ path: String, _ role: Module.Role) -> Module {
        Module(name: name, path: path, swiftFileCount: 1, role: role)
    }

    private func feature(_ name: String, _ path: String) -> Feature {
        Feature(name: name, path: path, layers: [], swiftFileCount: 1)
    }

    /// How `from` reaches `to`, or nil if it does not.
    private func kind(_ graph: TypeGraph, _ from: String, _ to: String) -> ReferenceKind? {
        graph.references.first { $0.from == from && $0.to == to }?.kind
    }

    // MARK: - What a reference is

    @Test("A property's declared type is a reference to it")
    func findsPropertyTypes() {
        let graph = build(files: [
            file("App/A.swift", """
                struct ProfileView {
                    let viewModel: ProfileViewModel
                }
                struct ProfileViewModel {}
                """),
        ])

        #expect(kind(graph, "ProfileView", "ProfileViewModel") == .propertyType)
    }

    @Test("An initializer parameter is told apart from any other parameter")
    func separatesInitializerDependencies() {
        // Where most Swift dependency injection is written. "Cannot be built
        // without this" is a stronger claim than "some method takes one".
        let graph = build(files: [
            file("App/A.swift", """
                struct ProfileViewModel {
                    init(repository: ProfileRepository) {}
                    func refresh(using loader: ImageLoader) {}
                }
                struct ProfileRepository {}
                struct ImageLoader {}
                """),
        ])

        #expect(kind(graph, "ProfileViewModel", "ProfileRepository") == .initializerDependency)
        #expect(kind(graph, "ProfileViewModel", "ImageLoader") == .parameterType)
    }

    @Test("A return type is a reference")
    func findsReturnTypes() {
        let graph = build(files: [
            file("App/A.swift", """
                protocol ArticleRepositoryProtocol {
                    func fetch() async throws -> [Article]
                }
                struct Article {}
                """),
        ])

        #expect(kind(graph, "ArticleRepositoryProtocol", "Article") == .returnType)
    }

    @Test("A generic constraint is a reference")
    func findsGenericConstraints() {
        let graph = build(files: [
            file("App/A.swift", """
                struct Cache<Element: Persistable> {}
                struct Loader {
                    func load<T>(_ value: T) where T: Persistable {}
                }
                protocol Persistable {}
                """),
        ])

        #expect(kind(graph, "Cache", "Persistable") == .genericConstraint)
        #expect(kind(graph, "Loader", "Persistable") == .genericConstraint)
    }

    @Test("Constructing a type and reaching its static surface are both references")
    func findsExpressionReferences() {
        let graph = build(files: [
            file("App/A.swift", """
                struct RootView {
                    func makeBody() {
                        let child = ProfileView()
                        AppLogger.shared.log("shown")
                    }
                }
                struct ProfileView {}
                struct AppLogger {}
                """),
        ])

        #expect(kind(graph, "RootView", "ProfileView") == .constructorReference)
        #expect(kind(graph, "RootView", "AppLogger") == .memberReference)
    }

    @Test("A typealias, a cast and a local annotation all name a type")
    func findsIncidentalReferences() {
        let graph = build(files: [
            file("App/A.swift", """
                struct Screen {
                    typealias Item = Article
                    func show(_ any: Any) {
                        let local: Article? = any as? Article
                    }
                }
                struct Article {}
                """),
        ])

        #expect(kind(graph, "Screen", "Article") == .typeReference)
    }

    // MARK: - Inheritance and conformance

    @Test("A superclass is inheritance; a protocol is conformance")
    func tellsInheritanceFromConformance() {
        // The question syntax cannot answer and the project can: both names sit
        // in the same clause, and only a class can be inherited from.
        let graph = build(files: [
            file("App/A.swift", """
                class BaseViewController {}
                protocol Trackable {}
                class ProfileViewController: BaseViewController, Trackable {}
                struct ProfileState: Trackable {}
                """),
        ])

        #expect(kind(graph, "ProfileViewController", "BaseViewController") == .inheritance)
        #expect(kind(graph, "ProfileViewController", "Trackable") == .conformance)
        #expect(kind(graph, "ProfileState", "Trackable") == .conformance)
    }

    @Test("A class whose first inherited type is one of the project's protocols is conforming")
    func settlesAmbiguousFirstPosition() {
        let graph = build(files: [
            file("App/A.swift", """
                protocol Reloadable {}
                final class ArticleStore: Reloadable {}
                """),
        ])

        #expect(kind(graph, "ArticleStore", "Reloadable") == .conformance)
    }

    @Test("An extension's conformance belongs to the type it extends")
    func attributesExtensionConformance() {
        // How a great deal of Swift is organised, and invisible if the owner of
        // an extension's references is not the extended type.
        let graph = build(files: [
            file("App/A.swift", """
                struct APIError {}
                protocol AppErrorConvertible {}
                extension APIError: AppErrorConvertible {
                    var fallback: AppError { AppError() }
                }
                struct AppError {}
                """),
        ])

        #expect(kind(graph, "APIError", "AppErrorConvertible") == .conformance)
        #expect(kind(graph, "APIError", "AppError") == .propertyType)
    }

    // MARK: - Written forms

    @Test("A type wrapped in an optional, an array or a generic is still reached")
    func looksThroughWrappedTypes() {
        // A dependency inside an array is a dependency.
        let graph = build(files: [
            file("App/A.swift", """
                struct Feed {
                    let latest: Article?
                    let all: [Article]
                    let byID: [String: Article]
                    let outcome: Result<Article, APIError>
                    let source: any ArticleRepositoryProtocol
                }
                struct Article {}
                struct APIError {}
                protocol ArticleRepositoryProtocol {}
                """),
        ])

        let reached = Set(graph.references(from: "Feed").map(\.to))
        #expect(reached == ["Article", "APIError", "ArticleRepositoryProtocol"])
    }

    @Test("A property wrapper does not hide what the property holds")
    func looksThroughPropertyWrappers() {
        let graph = build(files: [
            file("App/A.swift", """
                struct ProfileView {
                    @State private var viewModel: ProfileViewModel
                    @StateObject private var session = SessionStore()
                }
                struct ProfileViewModel {}
                final class SessionStore {}
                """),
        ])

        #expect(kind(graph, "ProfileView", "ProfileViewModel") == .propertyType)
        // Written with no annotation at all — the relationship is in the
        // initializer, which is the commonest way SwiftUI code states it.
        #expect(kind(graph, "ProfileView", "SessionStore") == .constructorReference)
    }

    @Test("Observation, in either style, does not change what is found")
    func readsBothObservationStyles() {
        let graph = build(files: [
            file("App/A.swift", """
                @Observable
                final class ArticleListViewModel {
                    private let repository: ArticleRepository
                }
                final class LegacyViewModel: ObservableObject {
                    private let repository: ArticleRepository
                }
                struct ArticleRepository {}
                """),
        ])

        #expect(kind(graph, "ArticleListViewModel", "ArticleRepository") == .propertyType)
        #expect(kind(graph, "LegacyViewModel", "ArticleRepository") == .propertyType)
    }

    // MARK: - Resolution

    @Test("A name the project does not declare is left out, not reported weakly")
    func dropsForeignTypes() {
        // `URLSession` is Apple's. A graph of this project's types has nothing
        // to say about it, and saying it anyway would fill the report with
        // every framework the code touches.
        let graph = build(files: [
            file("App/A.swift", """
                struct APIClient {
                    let session: URLSession
                    let decoder: JSONDecoder
                    let endpoint: ArticleEndpoint
                }
                struct ArticleEndpoint {}
                """),
        ])

        #expect(graph.references(from: "APIClient").map(\.to) == ["ArticleEndpoint"])
    }

    @Test("A bare name does not reach a nested type it cannot see")
    func respectsNesting() {
        // The case this exists for: a project with an `L10n.App` would
        // otherwise have every `struct MyApp: App` reported as conforming to
        // it, because the last component matches.
        let graph = build(files: [
            file("App/A.swift", """
                enum L10n {
                    enum App {}
                }
                struct ProbeApp: App {}
                """),
        ])

        #expect(graph.references(from: "ProbeApp").isEmpty)
    }

    @Test("A bare name does reach a nested type from inside the type that nests it")
    func resolvesNestedFromWithin() {
        let graph = build(files: [
            file("App/A.swift", """
                final class AuthManager {
                    enum StorageKey {}
                    struct Session {
                        let key: StorageKey
                    }
                }
                """),
        ])

        #expect(kind(graph, "AuthManager.Session", "AuthManager.StorageKey") == .propertyType)
    }

    @Test("A type and its own nested types are one component, not a relationship")
    func ignoresSelfNesting() {
        // `AuthManager` naming its own `AuthManager.StorageKey` is internal
        // structure. Listing it would bury the relationships that matter.
        let graph = build(files: [
            file("App/A.swift", """
                final class AuthManager {
                    enum StorageKey { static let token = "t" }
                    func store() { _ = StorageKey.token }
                }
                """),
        ])

        #expect(graph.references.isEmpty)
    }

    @Test("A unique name resolves; a name two types share is a name match and says so")
    func gradesResolution() {
        let unique = build(files: [
            file("App/A.swift", "struct Feed { let item: Article }\nstruct Article {}\n"),
        ])
        #expect(unique.references.first?.support == .observed)

        // Two nested `Article`s and a reference from outside both: the edge is
        // real, but which one it reaches cannot be settled by syntax.
        let ambiguous = build(files: [
            file("App/A.swift", """
                struct Article {}
                struct Feed { let item: Article }
                """),
            file("App/B.swift", "struct Article {}\n"),
        ])
        #expect(ambiguous.references.first?.support == .conventional)
    }

    @Test("Which of two same-named types is chosen does not depend on file order")
    func resolvesDeterministically() {
        let forwards = build(files: [
            file("App/A.swift", "struct Item {}\n"),
            file("App/B.swift", "struct Item {}\n"),
            file("App/C.swift", "struct Feed { let item: Item }\n"),
        ])
        let backwards = build(files: [
            file("App/C.swift", "struct Feed { let item: Item }\n"),
            file("App/B.swift", "struct Item {}\n"),
            file("App/A.swift", "struct Item {}\n"),
        ])

        #expect(forwards.references == backwards.references)
    }

    @Test("A file that does not parse contributes what it can rather than failing")
    func survivesMalformedSource() {
        let graph = build(files: [
            file("App/Broken.swift", "struct Broken { let item: Article\nfunc ("),
            file("App/Fine.swift", "struct Article {}\n"),
        ])

        #expect(kind(graph, "Broken", "Article") == .propertyType)
    }

    // MARK: - Roles

    @Test("A SwiftUI view is a view because the code says so")
    func readsRolesFromTheCode() {
        let graph = build(files: [
            file("App/A.swift", """
                struct ProfileView: View {}
                class SettingsViewController: UIViewController {}
                @Model final class StoredArticle {}
                """),
        ])

        #expect(graph.node(named: "ProfileView")?.role == .view)
        #expect(graph.node(named: "ProfileView")?.roleSupport == .observed)
        #expect(graph.node(named: "SettingsViewController")?.role == .viewController)
        #expect(graph.node(named: "SettingsViewController")?.roleSupport == .observed)
        #expect(graph.node(named: "StoredArticle")?.role == .persistence)
        #expect(graph.node(named: "StoredArticle")?.roleSupport == .observed)
    }

    @Test("A role taken from a name says it came from the name")
    func marksNamingDerivedRoles() {
        let graph = build(files: [
            file("App/A.swift", """
                struct ArticleRepository {}
                protocol ArticleRepositoryProtocol {}
                final class ArticleListViewModel {}
                """),
        ])

        #expect(graph.node(named: "ArticleRepository")?.role == .repository)
        #expect(graph.node(named: "ArticleRepository")?.roleSupport == .conventional)
        // `Protocol` on the end says how it is declared, not what it is for.
        #expect(graph.node(named: "ArticleRepositoryProtocol")?.role == .repository)
        #expect(graph.node(named: "ArticleListViewModel")?.role == .viewModel)
    }

    @Test("A type nothing in the naming rules recognises is other, not a guess")
    func refusesToGuessRoles() {
        let graph = build(files: [file("App/A.swift", "struct Article {}\n")])

        #expect(graph.node(named: "Article")?.role == .other)
        #expect(graph.node(named: "Article")?.roleSupport == .undetermined)
    }

    // MARK: - Findings

    @Test("A view holding a repository or a client is reported")
    func findsViewsReachingData() {
        let graph = build(files: [
            file("App/A.swift", """
                struct ProfileView: View {
                    let repository: ProfileRepository
                    let client: APIClient
                }
                struct ProfileRepository {}
                struct APIClient {}
                """),
        ])

        let rules = Set(graph.findings.map(\.rule))
        #expect(rules == [.viewReachesRepository, .viewReachesClient])
    }

    @Test("A view model referring back to a view is reported")
    func findsPresentationFlowingBackwards() {
        let graph = build(files: [
            file("App/A.swift", """
                final class ProfileViewModel {
                    var presented: ProfileView?
                }
                struct ProfileView: View {}
                """),
        ])

        #expect(graph.findings.map(\.rule) == [.viewModelReachesView])
    }

    @Test("A finding is only as strong as the weaker half of it")
    func gradesFindingsByTheirWeakerEnd() {
        // The view is a view because it conforms to `View`; the repository is
        // one because of its name. The finding is naming-derived, and taking
        // the stronger end would let the solid half launder the guess.
        let graph = build(files: [
            file("App/A.swift", """
                struct ProfileView: View {
                    let repository: ProfileRepository
                }
                struct ProfileRepository {}
                """),
        ])

        #expect(graph.findings.first?.support == .conventional)
    }

    @Test("Shared code depending on a feature is reported")
    func findsCoreReachingFeature() {
        let graph = build(
            modules: [module("Core", "App/Core", .core), module("Features", "App/Features", .features)],
            features: [feature("Profile", "App/Features/Profile")],
            files: [
                file("App/Core/Analytics.swift", """
                    struct Analytics {
                        func track(_ screen: ProfileScreenState) {}
                    }
                    """),
                file("App/Features/Profile/ProfileScreenState.swift", "struct ProfileScreenState {}\n"),
            ]
        )

        #expect(graph.findings.map(\.rule) == [.coreReachesFeature])
    }

    @Test("One feature reaching into another is reported — the edge imports cannot show")
    func findsFeatureReachingFeature() {
        // In a single-target app both features compile into one module, so no
        // import crosses between them and the import graph is silent by
        // construction. This is the graph that can see it.
        let graph = build(
            features: [feature("Profile", "App/Features/Profile"), feature("Settings", "App/Features/Settings")],
            files: [
                file("App/Features/Profile/ProfileView.swift", """
                    struct ProfileView {
                        let settings: SettingsStore
                    }
                    """),
                file("App/Features/Settings/SettingsStore.swift", "struct SettingsStore {}\n"),
            ]
        )

        let finding = graph.findings.first
        #expect(finding?.rule == .featureReachesFeature)
        #expect(finding?.subject == "ProfileView")
        #expect(finding?.object == "SettingsStore")
    }

    @Test("An ordinary relationship produces no finding")
    func staysQuietWhenNothingIsWrong() {
        let graph = build(files: [
            file("App/A.swift", """
                final class ProfileViewModel {
                    let repository: ProfileRepository
                }
                struct ProfileRepository {}
                """),
        ])

        #expect(!graph.references.isEmpty)
        #expect(graph.findings.isEmpty)
    }

    // MARK: - Evidence and shape

    @Test("Every reference says which file and line said so")
    func carriesEvidence() {
        let graph = build(files: [
            file("App/Features/Profile/ProfileView.swift", """
                struct ProfileView {

                    let viewModel: ProfileViewModel
                }
                struct ProfileViewModel {}
                """),
        ])

        let reference = graph.references.first
        #expect(reference?.line == 3)
        #expect(reference?.location == "App/Features/Profile/ProfileView.swift:3")
    }

    @Test("A type named several times is one relationship with several pieces of evidence")
    func groupsRelationships() {
        let graph = build(files: [
            file("App/A.swift", """
                struct ProfileView {
                    let viewModel: ProfileViewModel
                    init(viewModel: ProfileViewModel) {}
                    func rebuild() { _ = ProfileViewModel() }
                }
                struct ProfileViewModel {}
                """),
        ])

        let relationships = graph.relationships()
        #expect(relationships.count == 1)
        #expect(relationships[0].evidence.count == 3)
        // The declared relationship outranks the body reference.
        #expect(relationships[0].principalKind == .propertyType)
    }

    @Test("Relationships can be read by the layer the referring type sits in")
    func groupsByLayer() {
        let graph = build(files: [
            file("App/A.swift", """
                struct ProfileView: View {
                    let viewModel: ProfileViewModel
                }
                final class ProfileViewModel {
                    let repository: ProfileRepository
                }
                struct ProfileRepository {
                    let client: APIClient
                }
                struct APIClient {}
                """),
        ])

        #expect(graph.relationships(inLayer: .presentation).map(\.from) == ["ProfileView", "ProfileViewModel"])
        #expect(graph.relationships(inLayer: .data).map(\.from) == ["ProfileRepository"])
    }

    @Test("A type nothing refers to is listed as unreferenced, which is not the same as unused")
    func listsUnreferencedTypes() {
        let graph = build(files: [
            file("App/A.swift", """
                struct ProbeApp {
                    let root: RootView
                }
                struct RootView {}
                """),
        ])

        // The entry point is unreferenced and entirely alive.
        #expect(graph.unreferencedTypes().map(\.name) == ["ProbeApp"])
    }

    @Test("Nodes and references come back in the same order every time")
    func isDeterministic() {
        let source = """
            struct Zebra { let a: Apple }
            struct Apple { let m: Mango }
            struct Mango {}
            """
        let first = build(files: [file("App/A.swift", source)])
        let second = build(files: [file("App/A.swift", source)])

        #expect(first == second)
        #expect(first.nodes.map(\.name) == ["Apple", "Mango", "Zebra"])
    }

    @Test("A project with no Swift at all yields an empty graph rather than failing")
    func survivesAnEmptyProject() {
        #expect(build(files: []) == .empty)
    }
}

// MARK: - Against a real project

@Suite("Type graph of generated projects")
struct GeneratedTypeGraphTests {

    private let console = Console(useColor: false)

    private func model() throws -> ProjectModel {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-types-\(UUID().uuidString)")
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

    @Test("The generated app's presentation stack is found, with evidence")
    func findsTheRealStack() throws {
        let graph = try model().typeGraph

        #expect(graph.references.contains {
            $0.from == "ArticleListView" && $0.to == "ArticleListViewModel"
        })
        #expect(graph.references.contains {
            $0.from == "ArticleListViewModel" && $0.to == "ArticleRepositoryProtocol"
        })
        #expect(graph.references.contains {
            $0.from == "ArticleRepository" && $0.to == "APIClientProtocol"
        })
        #expect(graph.references.allSatisfy { $0.line > 0 && !$0.file.isEmpty })
    }

    @Test("Roles are read from the generated code where the code says so")
    func readsRealRoles() throws {
        let graph = try model().typeGraph

        let view = graph.node(named: "ArticleListView")
        #expect(view?.role == .view)
        #expect(view?.roleSupport == .observed)
        #expect(view?.owner.feature == "Articles")
    }

    @Test("Nothing in the graph refers to a type the project does not declare")
    func staysInsideTheProject() throws {
        let graph = try model().typeGraph
        let declared = Set(graph.nodes.map(\.name))

        #expect(graph.references.allSatisfy { declared.contains($0.from) && declared.contains($0.to) })
    }

    @Test("Test sources are left out, so a stub cannot invent a relationship")
    func excludesTests() throws {
        let graph = try model().typeGraph

        #expect(!graph.nodes.contains { $0.path.contains("ProbeTests") })
    }

    @Test("The model carries the resolved graph and not the raw mentions")
    func dropsWorkingMaterial() throws {
        // What `--json` prints is the whole of what the model holds. The
        // unresolved mentions are an intermediate and would roughly double it.
        let model = try model()

        #expect(model.analysis.references.isEmpty)
        #expect(!model.typeGraph.references.isEmpty)
    }

    @Test("The graph round-trips through Codable, for --json")
    func isCodable() throws {
        let graph = try model().typeGraph
        let data = try JSONEncoder().encode(graph)
        #expect(try JSONDecoder().decode(TypeGraph.self, from: data) == graph)
    }
}
