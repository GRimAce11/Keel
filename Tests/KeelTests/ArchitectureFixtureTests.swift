import Foundation
import Testing
@testable import KeelKit

/// One small project per architecture, read end to end.
///
/// The other architecture suites test a rule at a time. These test a *shape*:
/// a whole project of a recognisable kind, with every verdict that shape
/// implies asserted together. That is what catches a change which fixes one
/// dimension by quietly breaking another — the failure mode a per-rule test
/// cannot see, because each rule still passes on its own.
@Suite("Architecture fixtures")
struct ArchitectureFixtureTests {

    // MARK: - Building a shape

    private static let app = Target(
        name: "App", productType: .application, bundleIdentifier: nil,
        deploymentTarget: nil, swiftVersion: nil, platform: nil, strictConcurrency: nil
    )

    private func read(
        modules: [Module] = [],
        features: [Feature] = [],
        _ sources: [String: String]
    ) -> (architecture: Architecture, graph: TypeGraph, dependencies: DependencyGraph) {
        let analyzer = SwiftSourceAnalyzer()
        let analysis = SourceAnalysis(
            files: sources.sorted { $0.key < $1.key }
                .map { analyzer.analyze(source: $0.value, path: $0.key) }
        )
        let targets = [Self.app]

        let typeGraph = TypeGraphBuilder(inputs: .init(
            targets: targets, modules: modules, features: features, analysis: analysis
        )).build()
        let importGraph = ImportGraphBuilder(model: .init(
            rootPath: "/tmp/App", targets: targets, modules: modules, features: features,
            packages: [], packageProducts: [], analysis: analysis
        )).build()
        let dependencies = DependencyGraphBuilder(inputs: .init(
            importGraph: importGraph, typeGraph: typeGraph, modules: modules
        )).build()

        return (
            ArchitectureDetector(
                modules: modules, features: features, analysis: analysis,
                typeGraph: typeGraph, dependencies: dependencies
            ).detect(),
            typeGraph,
            dependencies
        )
    }

    private func module(_ name: String, _ role: Module.Role) -> Module {
        Module(name: name, path: "App/\(name)", swiftFileCount: 1, role: role)
    }

    private func feature(_ name: String, layers: [String] = []) -> Feature {
        Feature(name: name, path: "App/Features/\(name)", layers: layers, swiftFileCount: 1)
    }

    // MARK: - Presentation shapes

    @Test("Pure SwiftUI with view models is MVVM, fed through them")
    func pureSwiftUIMVVM() {
        let read = read([
            "App/A.swift": """
                import SwiftUI
                import Observation

                @Observable @MainActor
                final class ProfileViewModel {
                    private let repository: ProfileRepository
                    init(repository: ProfileRepository) { self.repository = repository }
                }
                struct ProfileView: View {
                    @State private var model: ProfileViewModel
                    var body: some View { EmptyView() }
                }
                struct ProfileRepository {}
                """,
        ])

        #expect(read.architecture.presentation.value == .mvvm)
        #expect(read.architecture.presentationFlow.value == .throughViewModels)
        #expect(read.architecture.uiCoexistence.value == .swiftUIOnly)
        #expect(read.architecture.observation.value == .observationMacro)
    }

    @Test("Pure SwiftUI with no view models is model-view, not MVVM")
    func pureSwiftUINoViewModels() {
        let read = read([
            "App/A.swift": """
                import SwiftUI
                struct ProfileView: View {
                    @State private var name = ""
                    var body: some View { EmptyView() }
                }
                """,
        ])

        #expect(read.architecture.presentation.value == .modelView)
        #expect(read.architecture.presentationFlow.value == .unknown)
    }

    @Test("Pure UIKit is MVC, and says so from the superclass")
    func pureUIKit() {
        let read = read([
            "App/A.swift": """
                import UIKit
                final class ProfileViewController: UIViewController {
                    private let repository = ProfileRepository()
                }
                struct ProfileRepository {}
                """,
        ])

        #expect(read.architecture.presentation.value == .mvc)
        #expect(read.architecture.uiCoexistence.value == .uiKitOnly)
        #expect(read.graph.node(named: "ProfileViewController")?.roleSupport == .observed)
    }

    @Test("SwiftUI and UIKit together, with the seam named")
    func mixedUIBridged() {
        let read = read([
            "App/A.swift": """
                import SwiftUI
                import UIKit
                struct MapView: UIViewRepresentable {}
                final class LegacyViewController: UIViewController {}
                struct HomeView: View { var body: some View { EmptyView() } }
                """,
        ])

        #expect(read.architecture.presentation.value == .mixed)
        #expect(read.architecture.uiCoexistence.value == .bridged)
    }

    @Test("SwiftUI and UIKit with nothing between them is side by side")
    func mixedUIUnbridged() {
        let read = read([
            "App/A.swift": "import SwiftUI\nstruct HomeView: View { var body: some View { EmptyView() } }\n",
            "App/B.swift": "import UIKit\nfinal class LegacyViewController: UIViewController {}\n",
        ])

        #expect(read.architecture.uiCoexistence.value == .sideBySide)
    }

    // MARK: - Layout shapes

    @Test("Feature folders make a project feature-based, and layers consistent")
    func featureBased() {
        let read = read(
            modules: [module("Features", .features)],
            features: [
                feature("Profile", layers: ["Data", "Domain", "Presentation"]),
                feature("Settings", layers: ["Data", "Domain", "Presentation"]),
            ],
            ["App/Features/Profile/Domain/Profile.swift": "struct Profile {}\n"]
        )

        #expect(read.architecture.organisation.value == .featureBased)
        #expect(read.architecture.featureLayering.value == .layered)
    }

    @Test("Top-level layer folders make a project layered rather than feature-based")
    func layered() {
        let read = read(
            modules: [module("Data", .other), module("Domain", .other), module("Presentation", .other)],
            [:]
        )

        #expect(read.architecture.organisation.value == .layered)
        #expect(read.architecture.featureLayering.value == .unknown)
    }

    @Test("Features divided differently from each other are inconsistent")
    func mixedLayering() {
        let read = read(
            modules: [module("Features", .features)],
            features: [
                feature("Profile", layers: ["Data", "Presentation"]),
                feature("Settings", layers: ["Domain"]),
            ],
            [:]
        )

        #expect(read.architecture.featureLayering.value == .inconsistent)
    }

    // MARK: - Wiring shapes

    @Test("A type that builds the app's services is the composition root")
    func dependencyInjection() {
        let read = read([
            "App/A.swift": """
                import Foundation
                protocol ProfileRepositoryProtocol {}
                protocol APIClientProtocol {}
                protocol KeychainProtocol {}
                struct ProfileRepository: ProfileRepositoryProtocol {}
                struct APIClient: APIClientProtocol {}
                struct Keychain: KeychainProtocol {}

                final class AppState {
                    let repository = ProfileRepository()
                    let client = APIClient()
                    let keychain = Keychain()
                }

                struct ProfileViewModel { init(repository: any ProfileRepositoryProtocol) {} }
                struct Loader { init(client: any APIClientProtocol) {} }
                struct Session { init(keychain: any KeychainProtocol) {} }
                """,
        ])

        #expect(read.architecture.wiring.value == .compositionRoot)
        #expect(read.architecture.compositionRoot == "AppState")
    }

    @Test("A project that wires nothing says so rather than guessing")
    func noWiring() {
        let read = read(["App/A.swift": "import Foundation\nstruct Article {}\n"])

        #expect(read.architecture.wiring.value == .unknown)
        #expect(read.architecture.wiring.support == .undetermined)
    }

    // MARK: - Boundary shapes

    @Test("A view reaching the network directly is visible in the flow and the checks")
    func directNetworkingFromViews() {
        let read = read([
            "App/A.swift": """
                import SwiftUI
                struct FeedView: View {
                    let client: APIClient
                    var body: some View { EmptyView() }
                }
                struct APIClient {}
                """,
        ])

        #expect(read.architecture.presentationFlow.value == .viewsReachData)
        #expect(read.architecture.networkingAccess.value == .views)
    }

    @Test("A view reaching persistence directly is reported as reaching it")
    func directPersistenceFromViews() {
        let read = read([
            "App/A.swift": """
                import SwiftUI
                import SwiftData
                @Model final class StoredItem {}
                struct ItemView: View {
                    let item: StoredItem
                    var body: some View { EmptyView() }
                }
                """,
        ])

        #expect(read.architecture.persistenceAccess.value == .views)
        #expect(read.architecture.persistence.value == .swiftData)
    }

    @Test("Infrastructure behind a repository reads as behind the data layer")
    func isolatedInfrastructure() {
        let read = read([
            "App/A.swift": """
                import SwiftUI
                import SwiftData
                @Model final class StoredItem {}
                struct ItemRepository { let item: StoredItem? }
                struct ItemView: View {
                    let repository: ItemRepository
                    var body: some View { EmptyView() }
                }
                """,
        ])

        #expect(read.architecture.persistenceAccess.value == .isolated)
    }

    // MARK: - Coupling shapes

    @Test("Cross-feature dependencies are coupling, reported and not judged")
    func crossFeature() {
        let read = read(
            features: [feature("Profile"), feature("Settings")],
            [
                "App/Features/Profile/ProfileViewModel.swift":
                    "final class ProfileViewModel { let settings: SettingsStore }\n",
                "App/Features/Settings/SettingsStore.swift": "struct SettingsStore {}\n",
            ]
        )

        #expect(read.architecture.featureIsolation.value == .coupled)
        #expect(read.dependencies.violations.isEmpty)
        #expect(read.dependencies.cycles(at: .feature).isEmpty)
    }

    @Test("A cycle between features is found where no import could show it")
    func featureCycle() {
        let read = read(
            features: [feature("Profile"), feature("Settings")],
            [
                "App/Features/Profile/ProfileViewModel.swift":
                    "final class ProfileViewModel { let settings: SettingsStore }\n",
                "App/Features/Settings/SettingsStore.swift":
                    "struct SettingsStore { let profile: ProfileViewModel? }\n",
            ]
        )

        #expect(read.architecture.featureIsolation.value == .coupled)
        #expect(Set(read.dependencies.cycles(at: .feature).first ?? []) == ["Profile", "Settings"])
    }

    @Test("Shared code depending on a feature inverts the direction the layout establishes")
    func invertedDirection() {
        let read = read(
            modules: [module("Core", .core), module("Features", .features)],
            features: [feature("Profile")],
            [
                "App/Core/Analytics.swift": "struct Analytics { let state: ProfileState }\n",
                "App/Features/Profile/ProfileState.swift": "struct ProfileState {}\n",
            ]
        )

        #expect(read.architecture.dependencyDirection.value == .sharedOnFeatures)
        #expect(read.dependencies.violations.map(\.rule) == [.sharedCodeDependsOnFeature])
    }

    // MARK: - The shapes that resist being named

    @Test("An ambiguous project reports undetermined rather than the likeliest answer")
    func ambiguous() {
        // Types with no recognisable role, no framework, no layout. Every
        // dimension that needs evidence has none.
        let read = read(["App/A.swift": "import Foundation\nstruct Thing { let other: Other? }\nstruct Other {}\n"])

        let architecture = read.architecture
        #expect(architecture.presentation.value == .unknown)
        #expect(architecture.presentationFlow.value == .unknown)
        #expect(architecture.organisation.value == .unknown)
        #expect(architecture.wiring.value == .unknown)
        #expect(architecture.summary == "Not enough in the project to describe its architecture.")

        // But the relationship it does have is still found.
        #expect(read.graph.references.contains { $0.from == "Thing" && $0.to == "Other" })
    }

    @Test("An empty project produces an empty model rather than failing")
    func incomplete() {
        let read = read([:])

        #expect(read.graph == .empty)
        #expect(read.dependencies == .empty)
        #expect(read.architecture.findings.allSatisfy { $0.support == .undetermined })
    }

    @Test("A project that does not parse still yields what it could")
    func broken() {
        // The promise the whole tool rests on: a project mid-refactor is
        // exactly when somebody needs to understand it.
        let read = read([
            "App/Broken.swift": "import SwiftUI\nstruct HomeView: View { var body: some View { EmptyView() }\nfunc (",
            "App/Fine.swift": "import Foundation\nstruct Article {}\n",
        ])

        #expect(read.graph.node(named: "HomeView") != nil)
        #expect(read.graph.node(named: "Article") != nil)
        #expect(read.architecture.presentation.value == .modelView)
    }
}
