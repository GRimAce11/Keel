import Foundation
import Testing
@testable import KeelKit

@Suite("SwiftSourceAnalyzer")
struct SwiftSourceAnalyzerTests {

    private let analyzer = SwiftSourceAnalyzer()

    private func analyze(_ source: String) -> FileAnalysis {
        analyzer.analyze(source: source, path: "Test.swift")
    }

    // MARK: - Declarations

    @Test("Finds each kind of type declaration")
    func findsDeclarationKinds() {
        let analysis = analyze("""
            struct AStruct {}
            class AClass {}
            enum AnEnum {}
            protocol AProtocol {}
            actor AnActor {}
            extension AStruct {}
            """)

        // A type and its extension share a name, so declarations are keyed
        // separately from extensions.
        let kinds = Dictionary(
            uniqueKeysWithValues: analysis.types
                .filter { $0.kind != .extensionOf }
                .map { ($0.name, $0.kind) }
        )
        #expect(kinds["AStruct"] == .structure)
        #expect(kinds["AClass"] == .classType)
        #expect(kinds["AnEnum"] == .enumeration)
        #expect(kinds["AProtocol"] == .protocolType)
        #expect(kinds["AnActor"] == .actorType)
        // The extension shares the name, so it appears twice with two kinds.
        #expect(analysis.types.filter { $0.kind == .extensionOf }.count == 1)
    }

    @Test("Records inherited types without claiming which is a superclass")
    func recordsInheritedTypes() {
        // Syntax cannot tell a superclass from a protocol — both sit in the
        // same clause and only the compiler knows the difference.
        let analysis = analyze("final class Screen: UIViewController, Identifiable {}")
        let screen = analysis.types.first

        #expect(screen?.inheritedTypes == ["UIViewController", "Identifiable"])
        #expect(screen?.conforms(to: "Identifiable") == true)
        #expect(screen?.isFinal == true)
    }

    @Test("Captures attributes by name, without their arguments")
    func capturesAttributes() {
        let analysis = analyze("""
            @Observable
            @MainActor
            @available(iOS 17, *)
            final class ArticleListViewModel {}
            """)
        let viewModel = analysis.types.first

        #expect(viewModel?.hasAttribute("Observable") == true)
        #expect(viewModel?.hasAttribute("MainActor") == true)
        // Arguments are dropped, so @available(iOS 17, *) records as available.
        #expect(viewModel?.hasAttribute("available") == true)
    }

    @Test("Qualifies a nested type with its enclosing type")
    func qualifiesNestedTypes() {
        // Reporting Role as a top-level type would double-count and lose where
        // it lives.
        let analysis = analyze("""
            struct Module {
                enum Role { case core }
                struct Inner { struct Deepest {} }
            }
            """)

        let names = Set(analysis.types.map(\.name))
        #expect(names.contains("Module"))
        #expect(names.contains("Module.Role"))
        #expect(names.contains("Module.Inner.Deepest"))
        #expect(!names.contains("Role"))
    }

    @Test("Records the access level when one is declared")
    func recordsAccessLevel() {
        let analysis = analyze("""
            public struct Exposed {}
            private struct Hidden {}
            struct Implicit {}
            """)
        let levels = Dictionary(
            uniqueKeysWithValues: analysis.types.map { ($0.name, $0.accessLevel) }
        )

        #expect(levels["Exposed"] == "public")
        #expect(levels["Hidden"] == "private")
        // Absent rather than guessed at — the default depends on context.
        #expect(levels["Implicit"] == .some(nil))
    }

    @Test("Records the line each declaration starts on")
    func recordsLineNumbers() {
        let analysis = analyze("""
            import Foundation

            struct First {}
            struct Second {}
            """)
        #expect(analysis.types.first { $0.name == "First" }?.line == 3)
        #expect(analysis.types.first { $0.name == "Second" }?.line == 4)
    }

    // MARK: - Extensions

    @Test("An extension that adds a conformance is recorded as one")
    func recordsExtensionConformance() throws {
        // `extension APIError: AppErrorConvertible` is how a great deal of
        // Swift is wired together, and it is invisible if extensions are
        // skipped.
        let analysis = analyze("extension APIError: AppErrorConvertible {}")
        let extensionDecl = try #require(analysis.types.first)

        #expect(extensionDecl.kind == .extensionOf)
        #expect(extensionDecl.name == "APIError")
        #expect(extensionDecl.conforms(to: "AppErrorConvertible"))
    }

    // MARK: - Functions

    @Test("Counts functions, and which of them are async or throwing")
    func countsFunctionEffects() {
        let analysis = analyze("""
            struct Repository {
                func plain() {}
                func fetch() async throws -> Int { 0 }
                func load() async -> Int { 0 }
                func risky() throws {}
            }
            """)

        #expect(analysis.functionCount == 4)
        #expect(analysis.asyncFunctionCount == 2)
        #expect(analysis.throwingFunctionCount == 2)
    }

    // MARK: - Imports

    @Test("Collects imports, including submodules")
    func collectsImports() {
        let analysis = analyze("""
            import Foundation
            import SwiftUI
            import os.log
            """)
        #expect(analysis.imports == ["Foundation", "SwiftUI", "os.log"])
    }

    // MARK: - Robustness

    @Test("Broken source still yields what could be parsed")
    func recoversFromSyntaxErrors() {
        // The whole point of parsing rather than compiling: analysis has to
        // work on a project that does not currently build.
        let analysis = analyze("""
            struct Good {}
            struct Broken { let x: = }
            struct AlsoGood {}
            """)

        let names = Set(analysis.types.map(\.name))
        #expect(names.contains("Good"))
        #expect(names.contains("AlsoGood"))
    }

    @Test("A type mentioned only in a comment or a string is not a declaration")
    func ignoresNonCode() {
        // This is exactly what substring matching got wrong.
        let analysis = analyze("""
            // struct Ghost {}
            let sample = "class Phantom {}"
            struct Real {}
            """)

        #expect(analysis.types.map(\.name) == ["Real"])
    }

    @Test("An empty file yields nothing rather than failing")
    func handlesEmptyFile() {
        let analysis = analyze("")
        #expect(analysis.types.isEmpty)
        #expect(analysis.imports.isEmpty)
        #expect(analysis.functionCount == 0)
    }
}

// MARK: - Aggregate

@Suite("SourceAnalysis")
struct SourceAnalysisTests {

    private let analyzer = SwiftSourceAnalyzer()

    private func analysis(_ sources: [String: String]) -> SourceAnalysis {
        SourceAnalysis(
            files: sources
                .sorted { $0.key < $1.key }
                .map { analyzer.analyze(source: $0.value, path: $0.key) }
        )
    }

    @Test("Counts how many files import each module, most used first")
    func countsImports() {
        let result = analysis([
            "A.swift": "import SwiftUI\nimport Foundation\n",
            "B.swift": "import SwiftUI\n",
            "C.swift": "import SwiftUI\nimport SwiftUI\n",
        ])
        let counts = result.importCounts()

        #expect(counts.first?.module == "SwiftUI")
        // A file importing the same module twice still counts once.
        #expect(counts.first?.files == 3)
        #expect(counts.first { $0.module == "Foundation" }?.files == 1)
    }

    @Test("Excludes extensions when counting declared types")
    func separatesExtensionsFromDeclarations() {
        // An extension is a second mention of a type, not another type.
        let result = analysis([
            "A.swift": "struct Article {}\nextension Article: Codable {}\n",
        ])

        #expect(result.types.count == 2)
        #expect(result.declaredTypes.count == 1)
    }

    @Test("Finds types by attribute, conformance and naming convention")
    func queriesTypes() {
        let result = analysis([
            "A.swift": """
                @Observable @MainActor final class ArticleListViewModel {}
                @Observable @MainActor final class ArticleRepository {}
                struct ArticleListView: View {}
                """,
        ])

        #expect(result.types(withAttribute: "Observable").count == 2)
        #expect(result.types(conformingTo: "View").map(\.name) == ["ArticleListView"])
        #expect(result.types(namedWithSuffix: "ViewModel").map(\.name) == ["ArticleListViewModel"])
        #expect(result.types(namedWithSuffix: "Repository").map(\.name) == ["ArticleRepository"])
    }

    @Test("Aggregates counts across files")
    func aggregatesCounts() {
        let result = analysis([
            "A.swift": "func one() async {}",
            "B.swift": "func two() throws {}",
        ])

        #expect(result.fileCount == 2)
        #expect(result.functionCount == 2)
        #expect(result.asyncFunctionCount == 1)
        #expect(result.throwingFunctionCount == 1)
    }
}

// MARK: - Integration

@Suite("Parsed analysis of a generated project")
struct GeneratedProjectAnalysisTests {

    @Test("A generated project parses into the patterns it was built with")
    func analysesGeneratedProject() throws {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-parse-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let configuration = ProjectConfiguration(
            name: try ProjectName("Probe"),
            components: Set(Component.allCases)
        )
        let outcome = try ProjectGenerator(
            configuration: configuration,
            console: Console(useColor: false)
        ).generate(in: destination, initializeGit: false)

        let analysis = try ProjectScanner(root: outcome.projectDirectory).scan().analysis

        #expect(analysis.fileCount > 0)
        // Keel generates @Observable ViewModels and repositories, so parsing
        // its own output should find exactly those.
        #expect(!analysis.types(withAttribute: "Observable").isEmpty)
        #expect(!analysis.types(withAttribute: "MainActor").isEmpty)
        #expect(!analysis.types(conformingTo: "View").isEmpty)
        #expect(!analysis.types(namedWithSuffix: "ViewModel").isEmpty)
        #expect(!analysis.types(namedWithSuffix: "Repository").isEmpty)
        #expect(analysis.asyncFunctionCount > 0)
        // And no ObservableObject anywhere, which is the pattern it replaces.
        #expect(analysis.types(conformingTo: "ObservableObject").isEmpty)
    }
}
