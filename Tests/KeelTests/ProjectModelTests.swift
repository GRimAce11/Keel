import Foundation
import Testing
@testable import KeelKit

/// Covers the structure Phase 9 adds on top of the raw scan: modules,
/// features, platforms and configurations.
@Suite("ProjectModel structure")
struct ProjectModelStructureTests {

    private let console = Console(useColor: false)

    private func withGeneratedProject<T>(
        name: String = "Probe",
        components: Set<Component> = Set(Component.allCases),
        _ body: (URL) throws -> T
    ) throws -> T {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let configuration = ProjectConfiguration(
            name: try ProjectName(name),
            bundleIdentifierPrefix: "com.acme",
            components: components
        )
        let outcome = try ProjectGenerator(configuration: configuration, console: console)
            .generate(in: destination, initializeGit: false)
        return try body(outcome.projectDirectory)
    }

    // MARK: - Modules

    @Test("Reports the app's top-level source groupings")
    func reportsModules() throws {
        try withGeneratedProject { root in
            let model = try ProjectScanner(root: root).scan()
            let names = model.modules.map(\.name)

            #expect(names.contains("App"))
            #expect(names.contains("Core"))
            #expect(names.contains("Shared"))
            #expect(model.modules.allSatisfy { $0.swiftFileCount > 0 || $0.role == .resources })
        }
    }

    @Test("Infers a role from a directory's name")
    func infersModuleRoles() throws {
        try withGeneratedProject { root in
            let model = try ProjectScanner(root: root).scan()
            let roles = Dictionary(
                uniqueKeysWithValues: model.modules.map { ($0.name, $0.role) }
            )
            #expect(roles["App"] == .app)
            #expect(roles["Core"] == .core)
            #expect(roles["Features"] == .features)
            #expect(roles["DesignSystem"] == .designSystem)
        }
    }

    @Test(
        "Role inference covers the names projects actually use",
        arguments: [
            ("Core", Module.Role.core),
            ("Infrastructure", Module.Role.core),
            ("Features", Module.Role.features),
            ("Screens", Module.Role.features),
            ("Shared", Module.Role.shared),
            ("Common", Module.Role.shared),
            ("DesignSystem", Module.Role.designSystem),
            ("Resources", Module.Role.resources),
            ("Whatever", Module.Role.other),
        ]
    )
    func inferRole(name: String, expected: Module.Role) {
        // Case-insensitive, because projects disagree about capitalisation.
        #expect(Module.Role(directoryName: name) == expected)
        #expect(Module.Role(directoryName: name.lowercased()) == expected)
    }

    @Test("A directory holding no Swift is not reported as a module")
    func skipsNonSourceDirectories() throws {
        try withGeneratedProject { root in
            let model = try ProjectScanner(root: root).scan()
            // Preview Content holds an asset catalog and nothing else.
            #expect(!model.modules.contains { $0.name == "Preview Content" })
        }
    }

    // MARK: - Features

    @Test("Reports feature folders with the layers they are divided into")
    func reportsFeatures() throws {
        try withGeneratedProject { root in
            let model = try ProjectScanner(root: root).scan()
            let articles = try #require(model.features.first { $0.name == "Articles" })

            #expect(articles.layers == ["Data", "Domain", "Presentation"])
            #expect(articles.swiftFileCount > 0)
            #expect(articles.path.contains("Features/Articles"))
        }
    }

    @Test("A project without a feature folder reports no features")
    func reportsNoFeatures() throws {
        try withGeneratedProject(name: "Plain", components: []) { root in
            let model = try ProjectScanner(root: root).scan()
            #expect(model.features.isEmpty)
        }
    }

    // MARK: - Platforms and configurations

    @Test("Reports the platform by the name a developer would use")
    func reportsPlatform() throws {
        try withGeneratedProject { root in
            // The build setting says "iphoneos"; nobody calls it that.
            let model = try ProjectScanner(root: root).scan()
            #expect(model.platforms == ["iOS"])
        }
    }

    @Test(
        "Maps each SDK onto its platform name",
        arguments: [
            ("iphoneos", "iOS"), ("iphonesimulator", "iOS"),
            ("macosx", "macOS"), ("watchos", "watchOS"),
            ("appletvos", "tvOS"), ("xros", "visionOS"),
        ]
    )
    func mapsSDKNames(sdk: String, expected: String) {
        #expect(Platform.displayName(forSDK: sdk) == expected)
    }

    @Test("An unrecognised SDK is passed through rather than guessed at")
    func passesThroughUnknownSDK() {
        #expect(Platform.displayName(forSDK: "somethingnew") == "somethingnew")
    }

    @Test("Reports the project's build configurations")
    func reportsConfigurations() throws {
        try withGeneratedProject { root in
            let model = try ProjectScanner(root: root).scan()
            #expect(Set(model.configurations.map(\.name)) == ["Debug", "Release"])
            #expect(model.configurations.allSatisfy { $0.projectName == "Probe" })
        }
    }

    // MARK: - Contract

    @Test("The whole model round-trips through Codable")
    func modelIsCodable() throws {
        // Everything downstream — document, check, the AI layer — consumes
        // this type, and --json serialises it.
        try withGeneratedProject { root in
            let model = try ProjectScanner(root: root).scan()
            let data = try JSONEncoder().encode(model)
            let decoded = try JSONDecoder().decode(ProjectModel.self, from: data)
            #expect(decoded == model)
        }
    }
}
