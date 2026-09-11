import Foundation
import Testing
@testable import KeelKit

/// Detection is driven through the real parser rather than hand-built
/// `TypeDeclaration` values.
///
/// A fixture assembled by hand can assert whatever the test wants it to;
/// a fixture that went through SwiftSyntax can only assert what the parser
/// actually produces, which is the thing detection will see in a real project.
@Suite("ArchitectureDetector")
struct ArchitectureDetectorTests {

    private func detect(
        modules: [Module] = [],
        features: [Feature] = [],
        _ sources: [String: String] = [:]
    ) -> Architecture {
        let analyzer = SwiftSourceAnalyzer()
        let files = sources
            .sorted { $0.key < $1.key }
            .map { analyzer.analyze(source: $0.value, path: $0.key) }

        return ArchitectureDetector(
            modules: modules,
            features: features,
            analysis: SourceAnalysis(files: files)
        ).detect()
    }

    private func module(_ name: String, files: Int = 1) -> Module {
        Module(
            name: name,
            path: "App/\(name)",
            swiftFileCount: files,
            role: Module.Role(directoryName: name)
        )
    }

    private func feature(_ name: String, layers: [String]) -> Feature {
        Feature(name: name, path: "Features/\(name)", layers: layers, swiftFileCount: 1)
    }

    // MARK: - Presentation

    @Test("A view model that is @Observable is evidence from the code")
    func detectsMVVMFromCode() {
        let architecture = detect([
            "Articles/ArticleListView.swift": """
                import SwiftUI
                struct ArticleListView: View { var body: some View { EmptyView() } }
                """,
            "Articles/ArticleListViewModel.swift": """
                import Foundation
                @Observable @MainActor final class ArticleListViewModel {}
                """,
        ])

        #expect(architecture.presentation.value == .mvvm)
        #expect(architecture.presentation.support == .observed)
    }

    @Test("A view model that is only named one is evidence from naming")
    func detectsMVVMFromNaming() {
        // The name is a habit, not a design. Reporting it as proof would make
        // every project that suffixes a type MVVM.
        let architecture = detect([
            "Screen.swift": """
                import SwiftUI
                struct Screen: View { var body: some View { EmptyView() } }
                final class ScreenViewModel {}
                """,
        ])

        #expect(architecture.presentation.value == .mvvm)
        #expect(architecture.presentation.support == .conventional)
        #expect(architecture.presentation.evidence.contains { $0.contains("only evidence") })
    }

    @Test("SwiftUI with no view model layer is not called MVVM")
    func detectsModelView() {
        let architecture = detect([
            "Screen.swift": """
                import SwiftUI
                struct Screen: View { var body: some View { EmptyView() } }
                """,
        ])

        #expect(architecture.presentation.value == .modelView)
        #expect(architecture.presentation.support == .conventional)
    }

    @Test("View controllers with no SwiftUI are MVC")
    func detectsMVC() {
        let architecture = detect([
            "HomeViewController.swift": """
                import UIKit
                final class HomeViewController: UIViewController {}
                """,
        ])

        #expect(architecture.presentation.value == .mvc)
        #expect(architecture.presentation.support == .observed)
    }

    @Test("A codebase holding both is reported as both")
    func detectsMixedPresentation() {
        let architecture = detect([
            "Legacy.swift": "import UIKit\nfinal class LegacyViewController: UIViewController {}",
            "Screen.swift": "import SwiftUI\nstruct Screen: View { var body: some View { EmptyView() } }",
        ])

        #expect(architecture.presentation.value == .mixed)
    }

    @Test("A View conformance without SwiftUI imported proves nothing")
    func ignoresViewWithoutSwiftUI() {
        // Any project may declare a protocol called View. Counting it as a
        // screen would invent a SwiftUI app out of a name.
        let architecture = detect([
            "Render.swift": """
                import Foundation
                protocol View {}
                struct Banner: View {}
                """,
        ])

        #expect(architecture.presentation.value == .unknown)
        #expect(architecture.presentation.support == .undetermined)
    }

    // MARK: - Organisation

    @Test("Feature folders make a project feature-based")
    func detectsFeatureOrganisation() {
        let architecture = detect(
            modules: [module("App"), module("Features")],
            features: [feature("Articles", layers: ["Data", "Presentation"])]
        )

        #expect(architecture.organisation.value == .featureBased)
        #expect(architecture.organisation.evidence.contains { $0.contains("1 feature folder") })
    }

    @Test("Top-level layer folders make a project layered")
    func detectsLayeredOrganisation() {
        let architecture = detect(modules: [module("Data"), module("Domain"), module("Presentation")])

        #expect(architecture.organisation.value == .layered)
        #expect(architecture.organisation.support == .conventional)
    }

    @Test("Role folders make a project grouped by role")
    func detectsGroupedOrganisation() {
        let architecture = detect(modules: [module("App"), module("Core"), module("Shared")])

        #expect(architecture.organisation.value == .grouped)
    }

    @Test("A layout Keel cannot name is left undetermined")
    func undeterminedOrganisation() {
        #expect(detect().organisation.value == .unknown)
        #expect(detect(modules: [module("Stuff")]).organisation.value == .unknown)
    }

    // MARK: - Feature layers

    @Test("Features divided alike are consistent")
    func detectsConsistentLayers() {
        let architecture = detect(
            modules: [module("Features")],
            features: [
                feature("Articles", layers: ["Data", "Domain", "Presentation"]),
                feature("Profile", layers: ["Data", "Domain", "Presentation"]),
            ]
        )

        #expect(architecture.featureLayering.value == .layered)
        #expect(architecture.featureLayering.evidence == [
            "All 2 features are divided into Data, Domain and Presentation."
        ])
    }

    @Test("One feature divided and one flat is the inconsistency worth reporting")
    func detectsPartialLayering() {
        let architecture = detect(
            modules: [module("Features")],
            features: [
                feature("Articles", layers: ["Data", "Presentation"]),
                feature("Profile", layers: []),
            ]
        )

        #expect(architecture.featureLayering.value == .inconsistent)
        #expect(architecture.featureLayering.evidence.contains { $0.contains("Profile") })
    }

    @Test("Features divided into different layers are inconsistent too")
    func detectsDisagreeingLayers() {
        let architecture = detect(
            modules: [module("Features")],
            features: [
                feature("Articles", layers: ["Data", "Presentation"]),
                feature("Profile", layers: ["Views", "Models"]),
            ]
        )

        #expect(architecture.featureLayering.value == .inconsistent)
    }

    @Test("Features with no subfolders are flat")
    func detectsFlatFeatures() {
        let architecture = detect(
            modules: [module("Features")],
            features: [feature("Articles", layers: [])]
        )

        #expect(architecture.featureLayering.value == .flat)
    }

    @Test("Without feature folders there is nothing to say about layers")
    func undeterminedLayering() {
        #expect(detect(modules: [module("App")]).featureLayering.value == .unknown)
        #expect(detect(modules: [module("App")]).featureLayering.support == .undetermined)
    }

    // MARK: - Observation

    @Test(
        "Observation is read from attributes and conformances",
        arguments: [
            ("@Observable final class A {}", ObservationStyle.observationMacro),
            ("final class A: ObservableObject {}", .observableObject),
            ("@Observable final class A {}\nfinal class B: ObservableObject {}", .mixed),
            ("final class A {}", .unknown),
        ]
    )
    func detectsObservation(source: String, expected: ObservationStyle) {
        let architecture = detect(["A.swift": "import Foundation\n\(source)"])
        #expect(architecture.observation.value == expected)
    }

    // MARK: - Concurrency

    @Test("async functions are async/await; Combine alongside them is mixed")
    func detectsConcurrency() {
        let asyncOnly = detect(["A.swift": "import Foundation\nfunc load() async {}"])
        #expect(asyncOnly.concurrency.value == .asyncAwait)

        let combineOnly = detect(["A.swift": "import Combine\nfinal class A {}"])
        #expect(combineOnly.concurrency.value == .combine)

        let both = detect(["A.swift": "import Combine\nfunc load() async {}"])
        #expect(both.concurrency.value == .mixed)
    }

    @Test("Actors and @MainActor stay in the evidence even when they settle nothing")
    func keepsIsolationEvidence() {
        // Neither decides between async/await and Combine, but dropping them
        // would throw away the only concurrency facts the project has.
        let architecture = detect(["A.swift": "import Foundation\n@MainActor final class A {}\nactor B {}"])

        #expect(architecture.concurrency.value == .unknown)
        #expect(architecture.concurrency.evidence.contains("1 actor declared."))
        #expect(architecture.concurrency.evidence.contains("1 type isolated to @MainActor."))
    }

    // MARK: - Persistence

    @Test("Persistence is read from the framework import, not from a guess")
    func detectsPersistence() {
        let swiftData = detect(["A.swift": "import SwiftData\n@Model final class Item {}"])
        #expect(swiftData.persistence.value == .swiftData)
        #expect(swiftData.persistence.evidence.contains("1 type marked @Model."))

        let coreData = detect(["A.swift": "import CoreData\nfinal class Item: NSManagedObject {}"])
        #expect(coreData.persistence.value == .coreData)

        // Absent is absent: a project storing to UserDefaults leaves no import.
        let neither = detect(["A.swift": "import Foundation\nstruct Item {}"])
        #expect(neither.persistence.value == .unknown)
        #expect(neither.persistence.support == .undetermined)
    }

    // MARK: - Wiring

    @Test("A container type is a composition root, on the strength of its name")
    func detectsCompositionRoot() {
        let architecture = detect([
            "AppContainer.swift": "import Foundation\n@Observable final class AppContainer {}",
        ])

        #expect(architecture.wiring.value == .compositionRoot)
        #expect(architecture.wiring.support == .conventional)
        #expect(architecture.wiring.evidence.first == "AppContainer declared in AppContainer.swift.")
    }

    @Test("Conforming to a protocol the project declares is evidence from the code")
    func detectsProtocolBoundaries() {
        let architecture = detect([
            "Repository.swift": """
                import Foundation
                protocol ArticleRepositoryProtocol {}
                struct ArticleRepository: ArticleRepositoryProtocol {}
                """,
        ])

        #expect(architecture.wiring.value == .protocolBoundaries)
        #expect(architecture.wiring.support == .observed)
    }

    @Test("Conforming to a protocol from elsewhere says nothing about wiring")
    func ignoresForeignConformances() {
        // Identifiable is not the project's own abstraction, so conforming to
        // it is not a dependency boundary.
        let architecture = detect(["A.swift": "import Foundation\nstruct Article: Identifiable {}"])

        #expect(architecture.wiring.value == .unknown)
    }

    // MARK: - Summary

    @Test("The summary states only what the evidence settled")
    func summarisesSettledFindings() {
        let architecture = detect(
            modules: [module("Features")],
            features: [feature("Articles", layers: ["Data", "Presentation"])],
            [
                "Screen.swift": """
                    import SwiftUI
                    struct Screen: View { var body: some View { EmptyView() } }
                    @Observable final class ScreenViewModel { func load() async {} }
                    """,
            ]
        )

        #expect(architecture.summary == """
            SwiftUI MVVM, organised by feature, built on @Observable and async/await.
            """)
    }

    @Test("A project with nothing to go on gets no sentence invented for it")
    func refusesToSummariseNothing() {
        #expect(detect().summary == "Not enough in the project to describe its architecture.")
    }
}

// MARK: - Test sources

@Suite("Excluding test sources")
struct TestSourceExclusionTests {

    @Test(
        "Test files are recognised by their path",
        arguments: [
            ("ProbeTests/Support/StubAPIClient.swift", true),
            ("ProbeUITests/LaunchTests.swift", true),
            ("Probe/Features/ArticleTests.swift", true),
            ("Probe/Features/Articles/ArticleRepository.swift", false),
            ("Probe/Core/Networking/APIClient.swift", false),
        ]
    )
    func recognisesTestPaths(path: String, isTest: Bool) {
        #expect(SourceAnalysis.isTestPath(path) == isTest)
    }

    @Test("A stub in the test target does not become part of the architecture")
    func excludesTestDoubles() {
        let analyzer = SwiftSourceAnalyzer()
        let analysis = SourceAnalysis(files: [
            analyzer.analyze(
                source: "import Foundation\nprotocol APIClientProtocol {}",
                path: "Probe/Core/APIClient.swift"
            ),
            analyzer.analyze(
                source: "import Foundation\nstruct StubAPIClient: APIClientProtocol {}",
                path: "ProbeTests/Support/StubAPIClient.swift"
            ),
        ])

        #expect(analysis.declaredTypes.count == 2)
        #expect(analysis.excludingTests().declaredTypes.map(\.name) == ["APIClientProtocol"])
    }
}

// MARK: - Generated projects

/// Detection run over projects Keel itself generates.
///
/// The unit tests above prove each rule in isolation; these prove the rules
/// still agree when pointed at a whole real project — and that changing what
/// `keel new` writes cannot silently change what `keel inspect` concludes.
@Suite("Architecture of generated projects")
struct GeneratedArchitectureTests {

    private let console = Console(useColor: false)

    private func architecture(
        components: Set<Component> = Set(Component.allCases)
    ) throws -> Architecture {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-architecture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let configuration = ProjectConfiguration(
            name: try ProjectName("Probe"),
            bundleIdentifierPrefix: "com.acme",
            components: components
        )
        let outcome = try ProjectGenerator(configuration: configuration, console: console)
            .generate(in: destination, initializeGit: false)
        return try ProjectScanner(root: outcome.projectDirectory).scan().architecture
    }

    @Test("A full project is read as the architecture Keel generated")
    func readsFullProject() throws {
        let architecture = try architecture()

        #expect(architecture.presentation.value == .mvvm)
        #expect(architecture.presentation.support == .observed)
        #expect(architecture.organisation.value == .featureBased)
        #expect(architecture.featureLayering.value == .layered)
        #expect(architecture.observation.value == .observationMacro)
        #expect(architecture.concurrency.value == .asyncAwait)
        #expect(architecture.persistence.value == .swiftData)
        #expect(architecture.wiring.value == .compositionRoot)
    }

    @Test("A minimal project claims nothing it does not contain")
    func readsMinimalProject() throws {
        let architecture = try architecture(components: [])

        // No example feature means no view models, and saying MVVM anyway is
        // exactly the invention this is built to avoid.
        #expect(architecture.presentation.value == .modelView)
        #expect(architecture.organisation.value == .grouped)
        #expect(architecture.featureLayering.value == .unknown)
        #expect(architecture.persistence.value == .unknown)
        #expect(architecture.wiring.value == .unknown)
    }

    @Test("Dropping the container drops the composition root, not the protocols")
    func readsProjectWithoutContainer() throws {
        let architecture = try architecture(
            components: Set(Component.allCases).subtracting([.dependencyInjection])
        )

        #expect(architecture.wiring.value == .protocolBoundaries)
        #expect(architecture.wiring.support == .observed)
    }

    @Test("Test doubles are left out of what the architecture is read from")
    func ignoresTestTarget() throws {
        // ProbeTests declares StubAPIClient, which conforms to the app's own
        // APIClientProtocol. Counting it would inflate every protocol boundary
        // Keel reports.
        let withTests = try architecture()
        let withoutTests = try architecture(
            components: Set(Component.allCases).subtracting([.testing])
        )

        #expect(withTests.wiring.evidence == withoutTests.wiring.evidence)
    }
}
