import Foundation
import Testing
@testable import KeelKit

@Suite("ProjectConfiguration")
struct ProjectConfigurationTests {

    private func makeName(_ value: String = "MyApp") throws -> ProjectName {
        try ProjectName(value)
    }

    // MARK: - Defaults

    @Test("Defaults to every component and iOS 17")
    func defaults() throws {
        let configuration = ProjectConfiguration(name: try makeName())

        #expect(configuration.minimumIOSVersion == "17.0")
        #expect(configuration.components.count == Component.allCases.count)
        #expect(configuration.adjustments.isEmpty)
    }

    @Test("Builds the bundle identifier from the prefix and the name slug")
    func buildsBundleIdentifier() throws {
        let configuration = ProjectConfiguration(
            name: try makeName("My Cool App"),
            bundleIdentifierPrefix: "com.acme"
        )
        #expect(configuration.bundleIdentifier == "com.acme.my-cool-app")
    }

    @Test("Uses com.example when no prefix is given")
    func defaultBundlePrefix() throws {
        let configuration = ProjectConfiguration(name: try makeName())
        #expect(configuration.bundleIdentifier == "com.example.my-app")
    }

    // MARK: - Dependency resolution

    @Test("Keeps components whose requirements are met")
    func keepsSatisfiedComponents() throws {
        let configuration = ProjectConfiguration(
            name: try makeName(),
            components: [.networking, .exampleFeature]
        )
        #expect(configuration.includes(.exampleFeature))
        #expect(configuration.adjustments.isEmpty)
    }

    @Test("Drops the example feature when networking is absent")
    func dropsExampleFeatureWithoutNetworking() throws {
        // Its screens call the API client directly, so keeping it would emit a
        // project that does not compile.
        let configuration = ProjectConfiguration(
            name: try makeName(),
            components: [.exampleFeature, .testing]
        )
        #expect(configuration.includes(.exampleFeature) == false)
        #expect(configuration.adjustments.count == 1)
        #expect(configuration.adjustments.first?.component == .exampleFeature)
    }

    @Test("Drops authentication when either of its dependencies is absent")
    func dropsAuthenticationWithoutDependencies() throws {
        let withoutKeychain = ProjectConfiguration(
            name: try makeName(),
            components: [.authentication, .networking]
        )
        #expect(withoutKeychain.includes(.authentication) == false)

        let withBoth = ProjectConfiguration(
            name: try makeName(),
            components: [.authentication, .networking, .keychain]
        )
        #expect(withBoth.includes(.authentication))
    }

    @Test("Resolution cascades through chained dependencies")
    func resolutionCascades() throws {
        // Removing networking must take out both the example feature and
        // authentication, each for its own reason.
        let configuration = ProjectConfiguration(
            name: try makeName(),
            components: [.exampleFeature, .authentication, .keychain]
        )
        #expect(configuration.includes(.exampleFeature) == false)
        #expect(configuration.includes(.authentication) == false)
        #expect(configuration.includes(.keychain))
        #expect(configuration.adjustments.count == 2)
    }

    @Test("An empty selection is valid")
    func allowsNoComponents() throws {
        let configuration = ProjectConfiguration(name: try makeName(), components: [])
        #expect(configuration.components.isEmpty)
        #expect(configuration.adjustments.isEmpty)
    }

    @Test("Every default component set resolves without adjustment")
    func defaultsAreSelfConsistent() throws {
        // If the full set needed adjusting, the dependency graph would be wrong.
        let configuration = ProjectConfiguration(
            name: try makeName(),
            components: Set(Component.allCases)
        )
        #expect(configuration.adjustments.isEmpty)
    }

    // MARK: - Serialization

    @Test("Round-trips through Codable")
    func roundTripsThroughCodable() throws {
        let original = ProjectConfiguration(
            name: try makeName("My Cool App"),
            bundleIdentifierPrefix: "com.acme",
            minimumIOSVersion: "18.0",
            components: [.networking, .testing]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProjectConfiguration.self, from: data)

        #expect(decoded == original)
        #expect(decoded.components == [.networking, .testing])
        #expect(decoded.bundleIdentifier == "com.acme.my-cool-app")
    }
}

@Suite("Component")
struct ComponentTests {

    @Test("Every component has a title and a summary")
    func hasDescriptions() {
        for component in Component.allCases {
            #expect(!component.title.isEmpty)
            #expect(!component.summary.isEmpty)
        }
    }

    @Test("Disable flags are kebab-cased and unique")
    func disableFlags() {
        #expect(Component.networking.disableFlag == "--no-networking")
        #expect(Component.dependencyInjection.disableFlag == "--no-dependency-injection")
        #expect(Component.exampleFeature.disableFlag == "--no-example-feature")

        let flags = Component.allCases.map(\.disableFlag)
        #expect(Set(flags).count == flags.count)
    }

    @Test("No component requires itself, directly or otherwise")
    func requirementsAreAcyclic() {
        for component in Component.allCases {
            #expect(!component.requires.contains(component))
        }
    }
}
