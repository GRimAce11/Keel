import Foundation
import Testing
@testable import KeelKit

/// What an agent is allowed to get away with.
///
/// The document is a file of measured facts with one section that is not, and
/// the whole arrangement only works if that section cannot quietly become
/// indistinguishable from the rest. These are the tests for the boundary.
@Suite("AI interpretation")
struct InterpretationTests {

    private let console = Console(useColor: false)

    private func model() throws -> ProjectModel {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-ai-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let outcome = try ProjectGenerator(
            configuration: ProjectConfiguration(
                name: try ProjectName("Probe"),
                bundleIdentifierPrefix: "com.acme",
                components: Set(Component.allCases)
            ),
            console: console
        ).generate(in: destination, initializeGit: false)
        return try ProjectScanner(root: outcome.projectDirectory).scan()
    }

    // MARK: - A reply that behaves

    @Test("A well-formed reply fills every field")
    func acceptsAValidReply() throws {
        let parsed = try ProjectInterpretation.parse("""
            {"overview": "A small reader app.",
             "dependencyFlow": "Views reach view models, which reach repositories.",
             "conventions": ["Repositories sit behind protocols."],
             "boundaries": ["Networking stays behind the repository."],
             "inconsistencies": ["One screen holds its own repository."],
             "risks": ["The container builds everything eagerly."],
             "readingOrder": ["Start at the entry point."],
             "legacyAreas": ["One type still uses the older observation style."],
             "questions": ["Is the preview repository used in production?"]}
            """)

        #expect(parsed.overview == "A small reader app.")
        #expect(parsed.boundaries == ["Networking stays behind the repository."])
        #expect(parsed.inconsistencies.count == 1)
        #expect(parsed.legacyAreas.count == 1)
        #expect(parsed.questions.count == 1)
        #expect(parsed.itemCount == 9)
    }

    @Test("A reply missing most fields is a partial answer, not a failure")
    func acceptsAPartialReply() throws {
        let parsed = try ProjectInterpretation.parse(#"{"overview": "Just this."}"#)

        #expect(parsed.overview == "Just this.")
        #expect(parsed.risks.isEmpty)
        #expect(!parsed.isEmpty)
    }

    // MARK: - A reply that does not

    @Test("A reply that is not JSON is refused")
    func rejectsProse() {
        #expect(throws: ProjectInterpretation.ParseError.notJSON) {
            try ProjectInterpretation.parse("I had a look and it seems like a nice app.")
        }
    }

    @Test("A reply with nothing usable in it is refused")
    func rejectsAnEmptyObject() {
        #expect(throws: ProjectInterpretation.ParseError.empty) {
            try ProjectInterpretation.parse("{}")
        }
        #expect(throws: ProjectInterpretation.ParseError.empty) {
            try ProjectInterpretation.parse(#"{"overview": "   ", "risks": []}"#)
        }
    }

    @Test("A reply whose fields are the wrong shape is refused")
    func rejectsMalformedFields() {
        #expect(throws: ProjectInterpretation.ParseError.self) {
            try ProjectInterpretation.parse(#"{"overview": ["not", "a", "string"]}"#)
        }
    }

    @Test("Markdown an agent adds out of habit is stripped, not published")
    func stripsInjectedMarkdown() throws {
        // Keel owns the document's structure. A `##` arriving in a field would
        // otherwise open a section that looks like one Keel measured.
        let parsed = try ProjectInterpretation.parse("""
            {"overview": "## Architecture\\n\\nThis is **great**.",
             "risks": ["- Watch the `APIClient`."]}
            """)

        let overview = try #require(parsed.overview)
        #expect(!overview.contains("#"))
        #expect(!overview.contains("*"))
        #expect(overview.contains("Architecture"))
        #expect(parsed.risks == ["Watch the APIClient."])
    }

    @Test("A field long enough to become the document is cut short")
    func capsRunawayFields() throws {
        let long = String(repeating: "word ", count: 1_000)
        let parsed = try ProjectInterpretation.parse(#"{"overview": "\#(long)"}"#)

        let overview = try #require(parsed.overview)
        #expect(overview.count <= ProjectInterpretation.Limit.prose + 1)
        #expect(overview.hasSuffix("…"))
    }

    @Test("More items than asked for are cut to the limit")
    func capsRunawayLists() throws {
        let many = (1...40).map { "\"Risk \($0).\"" }.joined(separator: ",")
        let parsed = try ProjectInterpretation.parse("{\"risks\": [\(many)]}")

        #expect(parsed.risks.count == ProjectInterpretation.Limit.items)
    }

    // MARK: - Claims the project cannot support

    @Test("A statement naming a type the project does not have is dropped")
    func dropsUnsupportedClaims() throws {
        let model = try model()
        let parsed = try ProjectInterpretation.parse("""
            {"overview": "ArticleListView drives the reading screen.",
             "risks": ["PaymentGateway retries silently.",
                       "ArticleRepository caches nothing."]}
            """)

        let verified = parsed.verified(against: model.vocabulary)

        // The invented one goes; the two real ones stay. Dropping the whole
        // reply over one bad sentence would throw away good interpretation.
        #expect(verified.overview == "ArticleListView drives the reading screen.")
        #expect(verified.risks == ["ArticleRepository caches nothing."])
    }

    @Test("Ordinary prose is not mistaken for a claim about a type")
    func leavesProseAlone() throws {
        let model = try model()
        let parsed = try ProjectInterpretation.parse("""
            {"overview": "The app is small and uses SwiftUI throughout.",
             "risks": ["Start here before changing anything."]}
            """)

        let verified = parsed.verified(against: model.vocabulary)
        #expect(verified.overview == parsed.overview)
        #expect(verified.risks == parsed.risks)
    }

    @Test("Only CamelCase names are judged, so a capitalised sentence survives")
    func onlyJudgesTypeShapedNames() {
        let vocabulary: Set<String> = ["ArticleRepository"]

        #expect(ProjectInterpretation.unsupportedNames(
            in: "Swift and The and Networking are fine.", vocabulary: vocabulary
        ).isEmpty)
        #expect(ProjectInterpretation.unsupportedNames(
            in: "ArticleRepository is fine.", vocabulary: vocabulary
        ).isEmpty)
        #expect(ProjectInterpretation.unsupportedNames(
            in: "PaymentGateway is not.", vocabulary: vocabulary
        ) == ["PaymentGateway"])
    }

    @Test("A reply that is entirely invention survives checking as nothing at all")
    func dropsAnEntirelyInventedReply() throws {
        let model = try model()
        let parsed = try ProjectInterpretation.parse("""
            {"overview": "PaymentGateway talks to BillingService.",
             "risks": ["CheckoutFlow is untested."]}
            """)

        #expect(parsed.verified(against: model.vocabulary).isEmpty)
    }

    // MARK: - The guarantees around it

    @Test("The vocabulary holds what the project contains and nothing else")
    func vocabularyIsDrawnFromTheProject() throws {
        let vocabulary = try model().vocabulary

        #expect(vocabulary.contains("ArticleListView"))
        #expect(vocabulary.contains("Articles"))
        #expect(vocabulary.contains("Probe"))
        #expect(vocabulary.contains("SwiftUI"))
        #expect(!vocabulary.contains("PaymentGateway"))
    }

    @Test("The prompt sends relationships, and still sends no source")
    func promptCarriesRelationshipsNotCode() throws {
        let prompt = DocumentationPrompt(model: try model()).text()

        #expect(prompt.contains("Feature dependencies:") || prompt.contains("Module dependencies:"))
        #expect(prompt.contains("What the types are for, by role:"))

        // The line that must never move: facts, never code.
        for marker in ["import SwiftUI", "func ", "var body", "struct ArticleListView"] {
            #expect(!prompt.contains(marker), "source leaked into the prompt: \(marker)")
        }
    }

    @Test("Evidence reaches the prompt as sentences, not as Swift values")
    func promptRendersEvidenceReadably() throws {
        let prompt = DocumentationPrompt(model: try model()).text()

        // It once interpolated the struct itself, which sent the agent a
        // debug description and told a reader nothing.
        #expect(!prompt.contains("ArchitectureEvidence("))
        #expect(!prompt.contains("KeelKit."))
        #expect(prompt.contains("SwiftUI views declared."))
    }

    @Test("Nothing an agent says can reach a deterministic section")
    func interpretationIsQuarantined() throws {
        let model = try model()
        let plain = ProjectDocument(model: model).markdown()
        let withAgent = ProjectDocument(
            model: model,
            interpretation: .init(
                fields: ProjectInterpretation(
                    overview: "Something an agent said.",
                    risks: ["And something else."]
                ),
                agentName: "Agent"
            )
        ).markdown()

        // The agent's section is added; every other section is byte-identical.
        let fenced = withAgent.components(separatedBy: ProjectDocument.overviewStart)
        #expect(fenced.count == 2)
        let after = fenced[1].components(separatedBy: ProjectDocument.overviewEnd)
        #expect(after.count == 2)

        let stripped = fenced[0] + after[1]
        for section in ["## Architecture", "## Structure"] where plain.contains(section) {
            #expect(stripped.contains(section), "\(section) was disturbed by the interpretation")
        }
        #expect(!plain.contains("Something an agent said."))
    }

    @Test("A document is still written when there is no interpretation at all")
    func fallsBackToTheDeterministicDocument() throws {
        // The degradation path: an agent that fails costs its section, never
        // the file.
        let markdown = ProjectDocument(model: try model(), interpretation: nil).markdown()

        #expect(markdown.contains("## Architecture"))
        #expect(!markdown.contains(ProjectDocument.overviewStart))
    }
}
