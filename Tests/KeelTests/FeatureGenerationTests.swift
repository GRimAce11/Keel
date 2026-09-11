import Foundation
import Testing
@testable import KeelKit

/// `add feature` writes into a project that already exists, so every test here
/// generates a real project first and then adds to it.
@Suite("FeatureGenerator")
struct FeatureGeneratorTests {

    private let console = Console(useColor: false)

    private func withProject<T>(
        components: Set<Component> = Set(Component.allCases),
        _ body: (URL, ProjectModel) throws -> T
    ) throws -> T {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-addfeature-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let configuration = ProjectConfiguration(
            name: try ProjectName("Probe"),
            bundleIdentifierPrefix: "com.acme",
            components: components
        )
        let outcome = try ProjectGenerator(configuration: configuration, console: console)
            .generate(in: destination, initializeGit: false)
        let model = try ProjectScanner(root: outcome.projectDirectory).scan()
        return try body(outcome.projectDirectory, model)
    }

    private func contents(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: - Shape

    @Test("A feature lands beside the ones already there, in the plan's shape")
    func writesTheExpectedTree() throws {
        try withProject { root, model in
            let outcome = try FeatureGenerator(model: model, console: console)
                .generate(named: "Profile")

            #expect(outcome.featurePath == "Probe/Features/Profile")
            #expect(outcome.writtenFiles == [
                "Probe/Features/Profile/Data/ProfileRepository.swift",
                "Probe/Features/Profile/Domain/Profile.swift",
                "Probe/Features/Profile/Presentation/ProfileView.swift",
                "Probe/Features/Profile/Presentation/ProfileViewModel.swift",
                "ProbeTests/Features/ProfileTests.swift",
            ])
            // The existing feature is untouched.
            #expect(FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Probe/Features/Articles").path
            ))
        }
    }

    @Test("The project's own feature folder is reused, not a folder Keel prefers")
    func reusesTheProjectsFeatureDirectory() throws {
        try withProject { root, model in
            let generator = FeatureGenerator(model: model, console: console)
            #expect(generator.featuresDirectoryPath() == "Probe/Features")
        }
    }

    // MARK: - Respecting the project

    @Test("A project without networking does not get a networking stack")
    func respectsMissingNetworking() throws {
        // The rule the plan states outright: adding a feature must not
        // introduce infrastructure the project deliberately omitted.
        try withProject(components: [.testing]) { root, model in
            let generator = FeatureGenerator(model: model, console: console)
            let inferred = try generator.inferredConfiguration()
            #expect(!inferred.includes(.networking))

            _ = try generator.generate(named: "Profile")
            let repository = try contents(
                root, "Probe/Features/Profile/Data/ProfileRepository.swift"
            )

            #expect(!repository.contains("APIClientProtocol"))
            #expect(repository.contains("no networking layer"))
        }
    }

    @Test("A project with networking gets a repository wired to its API client")
    func usesNetworkingWhenItExists() throws {
        try withProject { root, model in
            _ = try FeatureGenerator(model: model, console: console).generate(named: "Profile")
            let repository = try contents(
                root, "Probe/Features/Profile/Data/ProfileRepository.swift"
            )

            #expect(repository.contains("any APIClientProtocol"))
        }
    }

    @Test("A project with no test target gets no test file")
    func skipsTestsWhenThereIsNoTarget() throws {
        try withProject(components: []) { root, model in
            let outcome = try FeatureGenerator(model: model, console: console)
                .generate(named: "Profile")

            #expect(!outcome.writtenFiles.contains { $0.contains("Tests") })
        }
    }

    @Test("Generated features satisfy the checker, like generated projects do")
    func passesCheck() throws {
        try withProject { root, _ in
            let before = try ProjectScanner(root: root).scan()
            _ = try FeatureGenerator(model: before, console: console).generate(named: "Profile")

            // Adding a feature must not introduce a finding — otherwise `keel
            // add` and `keel check` disagree about the same project.
            let after = try ProjectScanner(root: root).scan()
            #expect(ProjectChecker(model: after).check().isEmpty)
        }
    }

    @Test("The new feature keeps the project's layering consistent")
    func keepsLayeringConsistent() throws {
        try withProject { root, model in
            _ = try FeatureGenerator(model: model, console: console).generate(named: "Profile")
            let after = try ProjectScanner(root: root).scan()

            #expect(after.features.map(\.name) == ["Articles", "Profile"])
            #expect(after.architecture.featureLayering.value == .layered)
        }
    }

    // MARK: - Refusals

    @Test("A feature that already exists is refused rather than merged into")
    func refusesToOverwrite() throws {
        try withProject { root, model in
            let generator = FeatureGenerator(model: model, console: console)
            _ = try generator.generate(named: "Profile")

            // Asserting the error *type* would let a name error satisfy this
            // test, which is the failure it exists to catch.
            #expect {
                try generator.generate(named: "Profile")
            } throws: { error in
                guard case FeatureGenerator.GenerationError.alreadyExists = error else {
                    return false
                }
                return true
            }
        }
    }

    @Test(
        "A name that cannot be a Swift type is refused",
        arguments: ["", "   ", "My Feature", "9Lives", "Pro-file", "emoji🙂"]
    )
    func refusesUnusableNames(name: String) throws {
        try withProject { _, model in
            // The name becomes a type in five files; catching it here beats
            // five compile errors.
            #expect {
                try FeatureGenerator(model: model, console: console).generate(named: name)
            } throws: { error in
                guard case FeatureGenerator.GenerationError.invalidName = error else {
                    return false
                }
                return true
            }
        }
    }

    @Test("A lowercase name is capitalised rather than rejected")
    func capitalisesNames() throws {
        try withProject { _, model in
            let outcome = try FeatureGenerator(model: model, console: console)
                .generate(named: "profile")
            #expect(outcome.name == "Profile")
        }
    }

    @Test("A project whose layout Keel cannot read is refused, not guessed at")
    func refusesWhenThereIsNoSourceDirectory() throws {
        try withProject { root, model in
            // Rename the source directory so nothing matches a target name.
            // Keel has no idea where features belong now, and inventing a
            // location would scatter files into a project at random.
            try FileManager.default.moveItem(
                at: root.appendingPathComponent("Probe"),
                to: root.appendingPathComponent("SomewhereElse")
            )

            let rescanned = try ProjectScanner(root: root).scan()
            #expect {
                try FeatureGenerator(model: rescanned, console: console).generate(named: "Profile")
            } throws: { error in
                guard case FeatureGenerator.GenerationError.noSourceDirectory = error else {
                    return false
                }
                return true
            }
        }
    }

    @Test("Keel-generated projects are picked up from the folder tree")
    func reportsSynchronizedFolders() throws {
        try withProject { _, model in
            // Without this, written files would be invisible in Xcode and the
            // command would look like it had done nothing.
            let outcome = try FeatureGenerator(model: model, console: console)
                .generate(named: "Profile")
            #expect(outcome.usesSynchronizedFolders)
        }
    }
}
