import Foundation
import Testing
@testable import KeelKit

/// The phase-5 dimensions: the ones read from what types do to each other
/// rather than from what they are called.
///
/// Every fixture goes through the real parser and the real graphs, so a test
/// can only assert what the detector will actually see in a project.
@Suite("Architecture from relationships")
struct ArchitectureFlowTests {

    // MARK: - Fixtures

    private static let app = Target(
        name: "App", productType: .application, bundleIdentifier: nil,
        deploymentTarget: nil, swiftVersion: nil, platform: nil, strictConcurrency: nil
    )

    private func detect(
        modules: [Module] = [],
        features: [Feature] = [],
        _ sources: [String: String]
    ) -> Architecture {
        let analyzer = SwiftSourceAnalyzer()
        let analysis = SourceAnalysis(
            files: sources.sorted { $0.key < $1.key }.map { analyzer.analyze(source: $0.value, path: $0.key) }
        )
        let targets = [Self.app]

        let typeGraph = TypeGraphBuilder(inputs: .init(
            targets: targets, modules: modules, features: features, analysis: analysis
        )).build()
        let importGraph = ImportGraphBuilder(model: .init(
            rootPath: "/tmp/App", targets: targets, modules: modules, features: features,
            packages: [], packageProducts: [], analysis: analysis
        )).build()

        return ArchitectureDetector(
            modules: modules,
            features: features,
            analysis: analysis,
            typeGraph: typeGraph,
            dependencies: DependencyGraphBuilder(inputs: .init(
                importGraph: importGraph, typeGraph: typeGraph, modules: modules
            )).build()
        ).detect()
    }

    private func module(_ name: String, _ role: Module.Role) -> Module {
        Module(name: name, path: "App/\(name)", swiftFileCount: 1, role: role)
    }

    private func feature(_ name: String, layers: [String] = []) -> Feature {
        Feature(name: name, path: "App/Features/\(name)", layers: layers, swiftFileCount: 1)
    }

    // MARK: - Presentation flow

    @Test("A view holding a view model, with the data layer behind it")
    func detectsFlowThroughViewModels() {
        let architecture = detect([
            "App/A.swift": """
                import SwiftUI
                struct ProfileView: View {
                    @State private var model: ProfileViewModel
                    var body: some View { EmptyView() }
                }
                @Observable final class ProfileViewModel {
                    private let repository: ProfileRepository
                }
                struct ProfileRepository {}
                """,
        ])

        #expect(architecture.presentationFlow.value == .throughViewModels)
        #expect(architecture.presentationFlow.bases == [.structuralRelationship])
    }

    @Test("A view holding a repository is reported however many view models exist")
    func detectsViewsReachingData() {
        // The finding counting names cannot make. This project has a view
        // model; the view simply does not use one.
        let architecture = detect([
            "App/A.swift": """
                import SwiftUI
                struct ProfileView: View {
                    let repository: ProfileRepository
                    var body: some View { EmptyView() }
                }
                @Observable final class ProfileViewModel {}
                struct ProfileRepository {}
                """,
        ])

        #expect(architecture.presentationFlow.value == .viewsReachData)
        #expect(architecture.presentation.value == .mvvm)
    }

    @Test("Some screens one way and some the other is mixed")
    func detectsMixedFlow() {
        let architecture = detect([
            "App/A.swift": """
                import SwiftUI
                struct ProfileView: View {
                    let model: ProfileViewModel
                    var body: some View { EmptyView() }
                }
                struct SettingsView: View {
                    let client: APIClient
                    var body: some View { EmptyView() }
                }
                @Observable final class ProfileViewModel {}
                struct APIClient {}
                """,
        ])

        #expect(architecture.presentationFlow.value == .mixed)
    }

    @Test("A project whose views reach neither is undetermined, not assumed")
    func leavesFlowUndetermined() {
        let architecture = detect([
            "App/A.swift": """
                import SwiftUI
                struct ProfileView: View { var body: some View { EmptyView() } }
                """,
        ])

        #expect(architecture.presentationFlow.value == .unknown)
        #expect(architecture.presentationFlow.support == .undetermined)
    }

    // MARK: - Feature isolation

    @Test("Features that never name each other are isolated")
    func detectsIsolatedFeatures() {
        let architecture = detect(
            features: [feature("Profile"), feature("Settings")],
            [
                "App/Features/Profile/ProfileViewModel.swift": "final class ProfileViewModel {}\n",
                "App/Features/Settings/SettingsStore.swift": "struct SettingsStore {}\n",
            ]
        )

        #expect(architecture.featureIsolation.value == .isolated)
        #expect(architecture.featureIsolation.bases == [.structuralRelationship])
    }

    @Test("One feature naming another is coupled, and named — not judged")
    func detectsCoupledFeatures() {
        let architecture = detect(
            features: [feature("Profile"), feature("Settings")],
            [
                "App/Features/Profile/ProfileViewModel.swift": """
                    final class ProfileViewModel { let settings: SettingsStore }
                    """,
                "App/Features/Settings/SettingsStore.swift": "struct SettingsStore {}\n",
            ]
        )

        #expect(architecture.featureIsolation.value == .coupled)
        #expect(architecture.featureIsolation.evidence.contains {
            $0.statement.contains("Profile depends on Settings")
        })
    }

    @Test("One feature cannot be isolated from anything, so the answer is undetermined")
    func needsTwoFeaturesToJudgeIsolation() {
        let architecture = detect(
            features: [feature("Profile")],
            ["App/Features/Profile/A.swift": "struct A {}\n"]
        )

        #expect(architecture.featureIsolation.value == .unknown)
    }

    // MARK: - Layer boundaries

    @Test("Data depending on Domain is the arrangement working, not a crossing")
    func readsLayersAsAShapeNotAStack() {
        // The mistake worth not making: Domain is the innermost layer, so both
        // Presentation and Data depend on it. A repository returning a domain
        // model is correct.
        let architecture = detect(
            features: [feature("Profile", layers: ["Data", "Domain", "Presentation"])],
            [
                "App/Features/Profile/Data/ProfileRepository.swift": """
                    struct ProfileRepository { func load() -> Profile { Profile() } }
                    """,
                "App/Features/Profile/Domain/Profile.swift": "struct Profile {}\n",
                "App/Features/Profile/Presentation/ProfileView.swift": """
                    struct ProfileView { let profile: Profile }
                    """,
            ]
        )

        #expect(architecture.layerBoundaries.value == .respected)
    }

    @Test("Domain reaching back into Presentation is a crossing")
    func detectsCrossedLayers() {
        let architecture = detect(
            features: [feature("Profile", layers: ["Data", "Domain", "Presentation"])],
            [
                "App/Features/Profile/Domain/Profile.swift": """
                    struct Profile { let presenter: ProfileView? }
                    """,
                "App/Features/Profile/Presentation/ProfileView.swift": "struct ProfileView {}\n",
            ]
        )

        #expect(architecture.layerBoundaries.value == .crossed)
        #expect(architecture.layerBoundaries.evidence.contains {
            $0.statement.contains("Domain → Presentation points back outwards")
        })
    }

    @Test("Layers Keel cannot place are left undetermined rather than ranked")
    func refusesToRankUnfamiliarLayers() {
        let architecture = detect(
            features: [feature("Profile", layers: ["Adapters", "Engine"])],
            [
                "App/Features/Profile/Engine/Core.swift": "struct Core { let a: Adapter }\n",
                "App/Features/Profile/Adapters/Adapter.swift": "struct Adapter {}\n",
            ]
        )

        #expect(architecture.layerBoundaries.value == .unknown)
        #expect(architecture.layerBoundaries.support == .undetermined)
    }

    // MARK: - Dependency direction

    @Test("Shared code depending on a feature inverts the usual direction")
    func detectsInvertedDirection() {
        let architecture = detect(
            modules: [module("Core", .core), module("Features", .features)],
            features: [feature("Profile")],
            [
                "App/Core/Analytics.swift": "struct Analytics { let state: ProfileState }\n",
                "App/Features/Profile/ProfileState.swift": "struct ProfileState {}\n",
            ]
        )

        #expect(architecture.dependencyDirection.value == .sharedOnFeatures)
        #expect(architecture.dependencyDirection.evidence.contains {
            $0.statement.contains("Core depends on the Profile feature")
        })
    }

    @Test("Features depending on shared code is the usual direction")
    func detectsUsualDirection() {
        let architecture = detect(
            modules: [module("Core", .core), module("Features", .features)],
            features: [feature("Profile")],
            [
                "App/Core/Analytics.swift": "struct Analytics {}\n",
                "App/Features/Profile/ProfileState.swift": "struct ProfileState { let a: Analytics }\n",
            ]
        )

        #expect(architecture.dependencyDirection.value == .featuresOnShared)
    }

    @Test("A project with no shared folder has no direction to judge")
    func leavesDirectionUndetermined() {
        #expect(detect(["App/A.swift": "struct A {}\n"]).dependencyDirection.value == .unknown)
    }

    // MARK: - Reach

    @Test("Persistence behind a repository is reported as behind the data layer")
    func detectsIsolatedPersistence() {
        let architecture = detect([
            "App/A.swift": """
                import SwiftData
                import SwiftUI
                @Model final class StoredItem {}
                struct ItemRepository { let item: StoredItem? }
                struct ItemView: View {
                    let repository: ItemRepository
                    var body: some View { EmptyView() }
                }
                """,
        ])

        #expect(architecture.persistenceAccess.value == .isolated)
    }

    @Test("A view touching a model type directly is reported as reaching it")
    func detectsViewsReachingPersistence() {
        let architecture = detect([
            "App/A.swift": """
                import SwiftData
                import SwiftUI
                @Model final class StoredItem {}
                struct ItemView: View {
                    let item: StoredItem
                    var body: some View { EmptyView() }
                }
                """,
        ])

        #expect(architecture.persistenceAccess.value == .views)
    }

    @Test("A view model touching the client, with no view doing so, is reported as such")
    func detectsViewModelsReachingNetworking() {
        let architecture = detect([
            "App/A.swift": """
                import SwiftUI
                struct APIClient {}
                @Observable final class FeedViewModel { let client: APIClient }
                struct FeedView: View {
                    let model: FeedViewModel
                    var body: some View { EmptyView() }
                }
                """,
        ])

        #expect(architecture.networkingAccess.value == .viewModels)
    }

    @Test("A project with no client of its own says none was found")
    func reportsNoNetworkingRatherThanGuessing() {
        let architecture = detect(["App/A.swift": "import Foundation\nstruct Article {}\n"])

        #expect(architecture.networkingAccess.value == .unknown)
        #expect(architecture.networkingAccess.support == .undetermined)
    }

    // MARK: - UI coexistence

    @Test("A project with both frameworks says where they meet")
    func detectsTheBridge() {
        let architecture = detect([
            "App/A.swift": """
                import SwiftUI
                import UIKit
                struct MapView: UIViewRepresentable {}
                class LegacyController: UIViewController {}
                """,
        ])

        #expect(architecture.uiCoexistence.value == .bridged)
        #expect(architecture.uiCoexistence.evidence.contains { $0.statement.contains("MapView") })
    }

    @Test("Both frameworks and no bridge is side by side, and says so")
    func detectsSideBySide() {
        let architecture = detect([
            "App/A.swift": "import SwiftUI\nstruct A: View { var body: some View { EmptyView() } }\n",
            "App/B.swift": "import UIKit\nclass B: UIViewController {}\n",
        ])

        #expect(architecture.uiCoexistence.value == .sideBySide)
        #expect(architecture.uiCoexistence.evidence.contains {
            $0.stance == .qualifying && $0.statement.contains("No type bridges")
        })
    }

    @Test("One framework is named plainly")
    func detectsASingleFramework() {
        #expect(detect(["A.swift": "import SwiftUI\nstruct A {}\n"]).uiCoexistence.value == .swiftUIOnly)
        #expect(detect(["A.swift": "import UIKit\nclass A {}\n"]).uiCoexistence.value == .uiKitOnly)
        #expect(detect(["A.swift": "import Foundation\nstruct A {}\n"]).uiCoexistence.value == .unknown)
    }

    // MARK: - The evidence model

    @Test("A conclusion resting only on names can never come back as observed")
    func namingNeverBecomesObserved() {
        // The one thing about this analysis that must not drift, so it is
        // asserted against the derivation rather than against any one rule.
        let naming = Finding(
            value: Organisation.featureBased,
            evidence: [.init("A folder is called Features.", basis: .namingConvention)]
        )
        #expect(naming.support == .conventional)
        #expect(naming.sourceSummary == "from naming")

        let related = Finding(
            value: Organisation.featureBased,
            evidence: [
                .init("A folder is called Features.", basis: .namingConvention),
                .init("One feature refers to another.", basis: .structuralRelationship),
            ]
        )
        #expect(related.support == .observed)
        #expect(related.sourceSummary == "from relationships")
    }

    @Test("Evidence that undercuts a conclusion is printed and not counted as support")
    func qualifyingEvidenceDoesNotSupport() {
        let finding = Finding(
            value: PresentationPattern.mvvm,
            evidence: [
                .init("Two types are named with a ViewModel suffix.", basis: .namingConvention),
                .qualifying("Neither is @Observable.", basis: .observedFact),
            ]
        )

        #expect(finding.support == .conventional)
        #expect(finding.bases == [.namingConvention])
        #expect(finding.evidence.count == 2)
    }

    @Test("Evidence that sets the scene does not support the verdict either")
    func contextDoesNotSupport() {
        let finding = Finding(
            value: PresentationPattern.mvvm,
            evidence: [
                .context("Six SwiftUI views are declared.", basis: .observedFact),
                .init("Two types are named with a ViewModel suffix.", basis: .namingConvention),
            ]
        )

        #expect(finding.support == .conventional)
        #expect(finding.bases == [.namingConvention])
    }

    @Test("A verdict of unknown is undetermined however much was read to get there")
    func unknownIsAlwaysUndetermined() {
        let finding = Finding(
            value: PersistenceStyle.unknown,
            evidence: [.init("Neither framework is imported.", basis: .observedFact)]
        )

        #expect(finding.support == .undetermined)
    }

    @Test("Relationship evidence carries the lines it was read from")
    func carriesSourceLocations() {
        let architecture = detect([
            "App/Profile/ProfileView.swift": """
                import SwiftUI
                struct ProfileView: View {
                    let model: ProfileViewModel
                    var body: some View { EmptyView() }
                }
                @Observable final class ProfileViewModel {}
                """,
        ])

        let relationship = architecture.presentation.evidence
            .first { $0.basis == .structuralRelationship }
        #expect(relationship?.locations == ["App/Profile/ProfileView.swift:3"])
    }

    @Test("A location list is capped rather than printing a page of them")
    func capsLocations() {
        let evidence = ArchitectureEvidence(
            "Many.", basis: .structuralRelationship,
            locations: (1...20).map { "A.swift:\($0)" }
        )

        #expect(evidence.locations.count == ArchitectureEvidence.locationLimit)
    }

    // MARK: - Summary

    @Test("The flow summary states only what the relationships settled")
    func summarisesFlow() {
        let architecture = detect(
            modules: [module("Core", .core), module("Features", .features)],
            features: [feature("Profile"), feature("Settings")],
            [
                "App/Core/Logger.swift": "struct Logger {}\n",
                "App/Features/Profile/ProfileView.swift": """
                    import SwiftUI
                    struct ProfileView: View {
                        let model: ProfileViewModel
                        var body: some View { EmptyView() }
                    }
                    @Observable final class ProfileViewModel { let logger: Logger }
                    """,
                "App/Features/Settings/SettingsStore.swift": "struct SettingsStore {}\n",
            ]
        )

        #expect(architecture.flowSummary == [
            "Screens get their data through view models.",
            "No feature depends on another.",
            "Dependencies run from features towards shared code.",
        ])
    }

    @Test("An empty project says so on every dimension rather than inventing one")
    func staysUndeterminedWithNothingToRead() {
        let architecture = detect([:])

        #expect(architecture.findings.allSatisfy { $0.support == .undetermined })
        #expect(architecture.summary == "Not enough in the project to describe its architecture.")
        #expect(architecture.flowSummary.isEmpty)
    }
}
