import Foundation
import Testing
@testable import KeelKit

/// Rules are tested by generating a real project and breaking it, rather than
/// by hand-building a model. A fixture assembled in memory can be made to
/// trigger any rule; a project that Keel itself wrote can only trigger the
/// ones that are really there.
@Suite("ProjectChecker")
struct ProjectCheckerTests {

    private let console = Console(useColor: false)

    /// Generates a project, optionally damages it, and checks the result.
    private func diagnostics(
        components: Set<Component> = Set(Component.allCases),
        damage: (URL) throws -> Void = { _ in }
    ) throws -> [Diagnostic] {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let configuration = ProjectConfiguration(
            name: try ProjectName("Probe"),
            bundleIdentifierPrefix: "com.acme",
            components: components
        )
        let outcome = try ProjectGenerator(configuration: configuration, console: console)
            .generate(in: destination, initializeGit: false)

        try damage(outcome.projectDirectory)
        return ProjectChecker(model: try ProjectScanner(root: outcome.projectDirectory).scan()).check()
    }

    private func write(_ source: String, to path: String, in root: URL) throws {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try source.write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: - The baseline that matters

    @Test("What Keel generates satisfies what Keel checks")
    func generatedProjectsAreClean() throws {
        // If this ever fails, either a rule is wrong or the templates are. Both
        // are worth stopping for — shipping a generator whose output fails the
        // checker would make the checker impossible to take seriously.
        #expect(try diagnostics().isEmpty)
    }

    @Test("A minimal project is clean apart from having no tests")
    func minimalProjectOnlyLacksTests() throws {
        let found = try diagnostics(components: [])
        #expect(found.map(\.rule) == ["no-test-target"])
        #expect(found.first?.severity == .warning)
    }

    // MARK: - Errors

    @Test("An attribute without its framework is an error, not a suspicion")
    func flagsMissingImport() throws {
        let found = try diagnostics { root in
            // Exactly the case a compiler would catch — on a project that
            // compiles. This one does not, which is when Keel is useful.
            let file = root.appendingPathComponent("Probe/Core/Persistence/StoredItem.swift")
            let source = try String(contentsOf: file, encoding: .utf8)
                .replacingOccurrences(of: "import SwiftData\n", with: "")
            try source.write(to: file, atomically: true, encoding: .utf8)
        }

        let diagnostic = try #require(found.first { $0.rule == "missing-import" })
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.message.contains("StoredItem"))
        #expect(diagnostic.location?.contains("StoredItem.swift") == true)
    }

    @Test("A scheme CI cannot see is an error")
    func flagsUnsharedScheme() throws {
        let found = try diagnostics { root in
            let shared = root.appendingPathComponent(
                "Probe.xcodeproj/xcshareddata/xcschemes/Probe.xcscheme"
            )
            let user = root.appendingPathComponent(
                "Probe.xcodeproj/xcuserdata/someone.xcuserdatad/xcschemes/Local.xcscheme"
            )
            try FileManager.default.createDirectory(
                at: user.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: shared, to: user)
        }

        let diagnostic = try #require(found.first { $0.rule == "scheme-not-shared" })
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.message.contains("Local"))
    }

    // MARK: - Warnings

    @Test("A view model that is not isolated and cannot be observed is reported twice")
    func flagsViewModelProblems() throws {
        let found = try diagnostics { root in
            try write(
                """
                import Foundation

                final class LegacyViewModel {
                    var title = ""
                }
                """,
                to: "Probe/Features/Legacy/LegacyViewModel.swift",
                in: root
            )
        }

        let rules = found.map(\.rule)
        #expect(rules.contains("view-model-not-main-actor"))
        #expect(rules.contains("view-model-not-observable"))

        // Both rest on the name, so neither may claim to be an error.
        let viewModelRules = found.filter { $0.rule.hasPrefix("view-model") }
        #expect(viewModelRules.allSatisfy { $0.severity == .warning })
        // And each says why Keel might be wrong.
        #expect(found.first { $0.rule == "view-model-not-main-actor" }?
            .detail?.contains("may be wrong") == true)
    }

    @Test("A screen owning infrastructure is reported per import, with the file as location")
    func flagsViewImportingInfrastructure() throws {
        let found = try diagnostics { root in
            try write(
                """
                import SwiftUI
                import Network

                struct LegacyView: View {
                    var body: some View { Text("hi") }
                }
                """,
                to: "Probe/Features/Legacy/LegacyView.swift",
                in: root
            )
        }

        let diagnostic = try #require(found.first { $0.rule == "view-imports-infrastructure" })
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.message.contains("Network"))
        // The path belongs in the location, not repeated in the message.
        #expect(!diagnostic.message.contains("LegacyView.swift"))
        #expect(diagnostic.location?.contains("LegacyView.swift") == true)
    }

    @Test("A repository with nothing in front of it is reported")
    func flagsRepositoryWithoutProtocol() throws {
        let found = try diagnostics { root in
            try write(
                """
                import Foundation

                struct LegacyRepository {
                    func fetch() async throws -> [String] { [] }
                }
                """,
                to: "Probe/Features/Legacy/LegacyRepository.swift",
                in: root
            )
        }

        let diagnostic = try #require(found.first { $0.rule == "repository-without-protocol" })
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.message.contains("LegacyRepository"))
        // The generated ArticleRepository does conform to one, and must not be
        // caught by this.
        #expect(!found.contains { $0.message.contains("ArticleRepository") })
    }

    @Test("A conformance added in an extension counts as having a protocol")
    func acceptsConformanceViaExtension() throws {
        let found = try diagnostics { root in
            try write(
                """
                import Foundation

                protocol LegacyFetching {
                    func fetch() async throws -> [String]
                }

                struct LegacyRepository {
                    func fetch() async throws -> [String] { [] }
                }

                extension LegacyRepository: LegacyFetching {}
                """,
                to: "Probe/Features/Legacy/LegacyRepository.swift",
                in: root
            )
        }

        // Extensions are how a great deal of Swift declares conformance;
        // missing them would make the rule fire constantly and wrongly.
        #expect(!found.contains { $0.rule == "repository-without-protocol" })
    }

    // MARK: - Discipline

    @Test("Test doubles cannot trigger rules")
    func ignoresTestSources() throws {
        let found = try diagnostics { root in
            // A stub with the shape of every violation, in the test target.
            try write(
                """
                import Foundation

                final class StubViewModel {
                    var title = ""
                }

                struct StubRepository {
                    func fetch() async throws -> [String] { [] }
                }
                """,
                to: "ProbeTests/Support/StubViewModel.swift",
                in: root
            )
        }

        #expect(!found.contains { $0.message.contains("Stub") })
    }

    @Test("Only structural rules are allowed to be errors")
    func reservesErrorsForCertainty() throws {
        let found = try diagnostics { root in
            try write(
                "import Foundation\n\nfinal class LooseViewModel {}\n",
                to: "Probe/Features/Legacy/LooseViewModel.swift",
                in: root
            )
        }

        // The whole credibility of the command rests on this: a naming
        // convention never gets to fail someone's build.
        let conventionRules: Set<String> = [
            "view-model-not-main-actor", "view-model-not-observable",
            "repository-without-protocol", "inconsistent-feature-layers",
            "view-imports-infrastructure", "no-test-target",
        ]
        for diagnostic in found where conventionRules.contains(diagnostic.rule) {
            #expect(diagnostic.severity == .warning, "\(diagnostic.rule) must not be an error")
        }
    }

    @Test("Findings are ordered errors first, then stably")
    func ordersFindings() {
        let unordered = [
            Diagnostic(rule: "z-rule", severity: .warning, message: "w"),
            Diagnostic(rule: "a-rule", severity: .error, message: "e"),
            Diagnostic(rule: "a-rule", severity: .warning, message: "w2"),
        ]
        let ordered = unordered.ordered()

        #expect(ordered.map(\.severity) == [.error, .warning, .warning])
        #expect(ordered.map(\.rule) == ["a-rule", "a-rule", "z-rule"])
        #expect(ordered.errors.count == 1)
        #expect(ordered.warnings.count == 2)
    }

    @Test("Diagnostics round-trip through Codable, for --json")
    func isCodable() throws {
        let found = try diagnostics(components: [])
        let data = try JSONEncoder().encode(found)
        #expect(try JSONDecoder().decode([Diagnostic].self, from: data) == found)
    }
}

// MARK: - Doctor

@Suite("Doctor")
struct DoctorTests {

    @Test(
        "A version is read from whatever wording the toolchain uses",
        arguments: [
            ("Apple Swift version 6.1.2 (swiftlang-6.1.2)", "6.1.2"),
            ("Swift version 6.0 (swift-6.0-RELEASE)", "6.0"),
            ("swift-driver version: 1.1 Apple Swift version 6.3.3 (x)", "6.3.3"),
        ]
    )
    func parsesVersions(text: String, expected: String) {
        // The third case is the one that matters: the driver prints its own
        // version first, as "version:" with a colon, which the pattern does not
        // match — so the compiler's version is what comes back.
        #expect(Doctor.version(in: text) == expected)
    }

    @Test("Text with no version yields nothing rather than a guess")
    func refusesToInventAVersion() {
        #expect(Doctor.version(in: "command not found") == nil)
        #expect(Doctor.version(in: "") == nil)
    }

    @Test("Diagnosis runs without a project and reports on the toolchain alone")
    func worksWithoutAProject() {
        // `keel doctor` in an empty directory is a reasonable way to ask
        // whether the machine is ready at all, so a missing project is not an
        // error.
        let diagnostics = Doctor(model: nil).diagnose()
        #expect(!diagnostics.contains { $0.rule == "no-app-target" })
    }

    @Test("Swift is found on a machine that just compiled this test")
    func findsSwift() {
        // Tautological in the best way: if swift were missing, nothing here
        // would be running.
        #expect(Doctor.swiftVersion() != nil)
        #expect(!Doctor(model: nil).diagnose().contains { $0.rule == "swift-missing" })
    }
}
