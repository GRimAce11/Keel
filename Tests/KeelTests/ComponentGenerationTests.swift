import Foundation
import Testing
@testable import KeelKit

/// Asserts the promise each component makes: enabling it writes its files,
/// disabling it writes none of them.
///
/// "Networking = No" must not leave an APIClient.swift behind for someone to
/// delete — that is the difference between a generator and a template you
/// clone and prune.
@Suite("Component generation")
struct ComponentGenerationTests {

    private let console = Console(useColor: false)

    /// One file that exists if and only if the component was selected.
    private static let signatureFile: [Component: String] = [
        .networking: "MyApp/Core/Networking/APIClient.swift",
        .dependencyInjection: "MyApp/App/AppContainer.swift",
        .persistence: "MyApp/Core/Persistence/PersistenceController.swift",
        .authentication: "MyApp/Core/Authentication/AuthManager.swift",
        .keychain: "MyApp/Core/Storage/KeychainService.swift",
        .localization: "MyApp/Core/Localization/L10n.swift",
        .testing: "MyAppTests/MyAppTests.swift",
        .designSystem: "MyApp/DesignSystem/DSColors.swift",
    ]

    private func withGenerated<T>(
        components: Set<Component>,
        _ body: (URL) throws -> T
    ) throws -> T {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-components-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let configuration = ProjectConfiguration(
            name: try ProjectName("MyApp"),
            bundleIdentifierPrefix: "com.acme",
            components: components
        )
        let generator = try ProjectGenerator(configuration: configuration, console: console)
        let outcome = try generator.generate(in: destination, initializeGit: false)
        return try body(outcome.projectDirectory)
    }

    private func exists(_ path: String, in root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
    }

    // MARK: - Inclusion

    @Test(
        "Enabling a component writes its files",
        arguments: ComponentGenerationTests.signatureFile.keys.sorted { $0.rawValue < $1.rawValue }
    )
    func componentIsWrittenWhenEnabled(component: Component) throws {
        // Dependencies come along, or resolution would drop the component.
        var components: Set<Component> = [component]
        components.formUnion(component.requires)

        try withGenerated(components: components) { root in
            let path = try #require(Self.signatureFile[component])
            #expect(exists(path, in: root), "\(component.rawValue) should write \(path)")
        }
    }

    // MARK: - Exclusion

    @Test(
        "Disabling a component writes none of its files",
        arguments: ComponentGenerationTests.signatureFile.keys.sorted { $0.rawValue < $1.rawValue }
    )
    func componentIsAbsentWhenDisabled(component: Component) throws {
        var components = Set(Component.allCases)
        components.remove(component)
        // Anything depending on it goes too, which resolution handles.

        try withGenerated(components: components) { root in
            let path = try #require(Self.signatureFile[component])
            #expect(!exists(path, in: root), "\(component.rawValue) should not write \(path)")
        }
    }

    @Test("A project with no components writes no component files at all")
    func minimalProjectHasNoComponentFiles() throws {
        try withGenerated(components: []) { root in
            for (component, path) in Self.signatureFile {
                #expect(!exists(path, in: root), "\(component.rawValue) leaked into a bare project")
            }
        }
    }

    // MARK: - Cross-module wiring

    @Test("The container only references services that were generated")
    func containerMatchesSelectedComponents() throws {
        // A container referring to a type that was never written would not
        // compile, and it is the file most likely to drift.
        try withGenerated(components: [.dependencyInjection]) { root in
            let container = String(
                decoding: try Data(contentsOf: root.appendingPathComponent("MyApp/App/AppContainer.swift")),
                as: UTF8.self
            )
            #expect(!container.contains("APIClient("))
            #expect(!container.contains("KeychainService("))
            #expect(!container.contains("PersistenceController"))
            #expect(!container.contains("AuthManager("))
        }
    }

    @Test("The container wires up every service that was generated")
    func containerWiresSelectedComponents() throws {
        try withGenerated(components: Set(Component.allCases)) { root in
            let container = String(
                decoding: try Data(contentsOf: root.appendingPathComponent("MyApp/App/AppContainer.swift")),
                as: UTF8.self
            )
            #expect(container.contains("APIClient("))
            #expect(container.contains("KeychainService("))
            #expect(container.contains("AuthManager("))
            // Auth must own the token provider — otherwise every request goes
            // out unauthenticated and nothing says why.
            #expect(container.contains("setTokenProvider"))
            #expect(container.contains("setUnauthorizedHandler"))
        }
    }

    @Test("The app entry point injects the container only when DI is selected")
    func appEntryInjectsContainerConditionally() throws {
        try withGenerated(components: [.dependencyInjection]) { root in
            let entry = String(
                decoding: try Data(contentsOf: root.appendingPathComponent("MyApp/App/MyAppApp.swift")),
                as: UTF8.self
            )
            #expect(entry.contains(".environment(container)"))
        }

        try withGenerated(components: []) { root in
            let entry = String(
                decoding: try Data(contentsOf: root.appendingPathComponent("MyApp/App/MyAppApp.swift")),
                as: UTF8.self
            )
            #expect(!entry.contains("AppContainer"))
            #expect(!entry.contains("SwiftData"))
        }
    }
}
