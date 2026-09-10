import Foundation
import Testing
@testable import KeelKit

@Suite("ProjectGenerator")
struct ProjectGeneratorTests {

    private let console = Console(useColor: false)

    /// A scratch directory, removed when the test finishes.
    private func withTemporaryDirectory<T>(_ body: (URL) throws -> T) rethrows -> T {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-generate-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        return try body(url)
    }

    private func generate(
        name: String = "MyApp",
        components: Set<Component> = Set(Component.allCases),
        into destination: URL
    ) throws -> ProjectGenerator.Outcome {
        let configuration = ProjectConfiguration(
            name: try ProjectName(name),
            bundleIdentifierPrefix: "com.acme",
            components: components
        )
        let generator = try ProjectGenerator(configuration: configuration, console: console)
        // git is left out: these tests assert about files, and a commit needs
        // an identity the machine may not have configured.
        return try generator.generate(in: destination, initializeGit: false)
    }

    private func contents(of url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    // MARK: - Structure

    @Test("Creates a project directory named after the project")
    func createsProjectDirectory() throws {
        try withTemporaryDirectory { directory in
            let outcome = try generate(into: directory)

            #expect(outcome.projectDirectory.lastPathComponent == "MyApp")
            #expect(FileManager.default.fileExists(atPath: outcome.projectDirectory.path))
            #expect(outcome.fileCount > 0)
        }
    }

    @Test("Writes an Xcode project, a scheme and an app entry point")
    func writesEssentialFiles() throws {
        try withTemporaryDirectory { directory in
            let root = try generate(into: directory).projectDirectory

            let expected = [
                "MyApp.xcodeproj/project.pbxproj",
                "MyApp.xcodeproj/project.xcworkspace/contents.xcworkspacedata",
                "MyApp.xcodeproj/xcshareddata/xcschemes/MyApp.xcscheme",
                "MyApp/App/MyAppApp.swift",
                "MyApp/Assets.xcassets/Contents.json",
                "README.md",
                ".gitignore",
            ]

            for path in expected {
                #expect(
                    FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                    "expected \(path)"
                )
            }
        }
    }

    @Test("A shared scheme is written, so xcodebuild -scheme works on a fresh clone")
    func writesSharedScheme() throws {
        try withTemporaryDirectory { directory in
            let root = try generate(into: directory).projectDirectory
            // Without xcshareddata the scheme is per-user and CI cannot find it.
            let scheme = root.appendingPathComponent(
                "MyApp.xcodeproj/xcshareddata/xcschemes/MyApp.xcscheme"
            )
            #expect(try contents(of: scheme).contains("MyApp.app"))
        }
    }

    // MARK: - Token substitution

    @Test("Substitutes the name, bundle identifier and deployment target")
    func substitutesTokens() throws {
        try withTemporaryDirectory { directory in
            let root = try generate(into: directory).projectDirectory
            let pbxproj = try contents(
                of: root.appendingPathComponent("MyApp.xcodeproj/project.pbxproj")
            )

            #expect(pbxproj.contains("com.acme.my-app"))
            #expect(pbxproj.contains("IPHONEOS_DEPLOYMENT_TARGET = 17.0"))
            #expect(pbxproj.contains("MyApp.app"))
        }
    }

    @Test("No unsubstituted token survives into the generated project")
    func leavesNoTokensBehind() throws {
        try withTemporaryDirectory { directory in
            let root = try generate(into: directory).projectDirectory

            let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            for case let file as URL in files {
                guard (try? file.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == false
                else { continue }

                // A stray __TOKEN__ would ship to the developer verbatim.
                let text = (try? contents(of: file)) ?? ""
                #expect(!text.contains("__PROJECT_NAME__"), "in \(file.lastPathComponent)")
                #expect(!text.contains("__BUNDLE_ID__"), "in \(file.lastPathComponent)")
                #expect(!file.lastPathComponent.contains("__"), "in \(file.lastPathComponent)")
                #expect(!file.lastPathComponent.hasSuffix(".tpl"), "in \(file.lastPathComponent)")
            }
        }
    }

    @Test("Dotfile templates land as dotfiles")
    func rendersDotfiles() throws {
        try withTemporaryDirectory { directory in
            let root = try generate(into: directory).projectDirectory
            #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".gitignore").path))
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("__DOT__gitignore").path))
        }
    }

    // MARK: - Conditional components

    @Test("Disabling tests removes the target, its files and its project references")
    func omitsTestTargetWhenDisabled() throws {
        try withTemporaryDirectory { directory in
            var components = Set(Component.allCases)
            components.remove(.testing)
            let root = try generate(name: "Plain", components: components, into: directory).projectDirectory

            let testsDirectory = root.appendingPathComponent("PlainTests")
            #expect(!FileManager.default.fileExists(atPath: testsDirectory.path))

            // The project file must not reference a target that was not written.
            let pbxproj = try contents(of: root.appendingPathComponent("Plain.xcodeproj/project.pbxproj"))
            #expect(!pbxproj.contains("PlainTests"))
            #expect(!pbxproj.contains("bundle.unit-test"))
        }
    }

    @Test("Enabling tests writes the target and wires it into the project")
    func includesTestTargetWhenEnabled() throws {
        try withTemporaryDirectory { directory in
            let root = try generate(components: [.testing], into: directory).projectDirectory

            #expect(FileManager.default.fileExists(
                atPath: root.appendingPathComponent("MyAppTests/MyAppTests.swift").path
            ))
            let pbxproj = try contents(of: root.appendingPathComponent("MyApp.xcodeproj/project.pbxproj"))
            #expect(pbxproj.contains("bundle.unit-test"))
        }
    }

    @Test("A minimal project still produces a buildable skeleton")
    func minimalProjectHasEssentials() throws {
        try withTemporaryDirectory { directory in
            let root = try generate(components: [], into: directory).projectDirectory

            // Base is unconditional: without an entry point and a project file
            // there would be nothing to open.
            #expect(FileManager.default.fileExists(
                atPath: root.appendingPathComponent("MyApp/App/MyAppApp.swift").path
            ))
            #expect(FileManager.default.fileExists(
                atPath: root.appendingPathComponent("MyApp.xcodeproj/project.pbxproj").path
            ))
        }
    }

    // MARK: - Safety

    @Test("Refuses to write into a directory that already exists")
    func refusesExistingDestination() throws {
        try withTemporaryDirectory { directory in
            _ = try generate(into: directory)

            // Merging into someone's existing project and half-overwriting it
            // is unrecoverable, so this must fail rather than proceed.
            #expect(throws: ProjectGenerator.GenerationError.self) {
                _ = try generate(into: directory)
            }
        }
    }

    @Test("Generation is deterministic for the same configuration")
    func generationIsDeterministic() throws {
        try withTemporaryDirectory { first in
            try withTemporaryDirectory { second in
                let a = try generate(into: first)
                let b = try generate(into: second)
                #expect(a.fileCount == b.fileCount)

                let pbxA = try contents(of: a.projectDirectory.appendingPathComponent("MyApp.xcodeproj/project.pbxproj"))
                let pbxB = try contents(of: b.projectDirectory.appendingPathComponent("MyApp.xcodeproj/project.pbxproj"))
                #expect(pbxA == pbxB)
            }
        }
    }

    @Test("Skipping git leaves no repository behind")
    func canSkipGit() throws {
        try withTemporaryDirectory { directory in
            let outcome = try generate(into: directory)
            #expect(outcome.didInitializeGitRepository == false)
            #expect(!FileManager.default.fileExists(
                atPath: outcome.projectDirectory.appendingPathComponent(".git").path
            ))
        }
    }
}
