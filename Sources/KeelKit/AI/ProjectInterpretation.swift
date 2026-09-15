import Foundation

/// What an agent is allowed to hand back.
///
/// The agent returns data; Keel writes the Markdown. That order matters. If the
/// agent authored the document directly, every guarantee about structure,
/// attribution and length would depend on it following instructions — and an
/// agent that ignored them would produce a file indistinguishable from one Keel
/// had verified. Fields go through `parse`, which drops anything malformed, so
/// the worst a bad response can do is arrive empty.
public struct ProjectInterpretation: Codable, Sendable, Equatable {

    // What the facts add up to. Inferred: the agent's reading of evidence Keel
    // established, which is a different thing from the evidence.

    /// Two or three sentences orienting someone new.
    public let overview: String?
    /// How a request moves through the app, read from the dependency graph.
    public let dependencyFlow: String?
    /// Conventions the agent noticed in the facts.
    public let conventions: [String]
    /// Boundaries the project appears to maintain — and is worth keeping.
    public let boundaries: [String]
    /// Places the facts disagree with each other.
    public let inconsistencies: [String]

    // What to do about it. Suggested: the agent's advice, which is nobody's
    // rule until a person decides it is.

    /// Things worth being careful about.
    public let risks: [String]
    /// Where to start reading.
    public let readingOrder: [String]
    /// Parts that look older than the rest.
    public let legacyAreas: [String]
    /// Things a developer should go and find out.
    public let questions: [String]

    public init(
        overview: String? = nil,
        dependencyFlow: String? = nil,
        conventions: [String] = [],
        boundaries: [String] = [],
        inconsistencies: [String] = [],
        risks: [String] = [],
        readingOrder: [String] = [],
        legacyAreas: [String] = [],
        questions: [String] = []
    ) {
        self.overview = overview
        self.dependencyFlow = dependencyFlow
        self.conventions = conventions
        self.boundaries = boundaries
        self.inconsistencies = inconsistencies
        self.risks = risks
        self.readingOrder = readingOrder
        self.legacyAreas = legacyAreas
        self.questions = questions
    }

    /// What the agent is claiming when it fills a given field.
    ///
    /// Assigned by Keel, never by the agent. If a reply could say "this is an
    /// observed fact", then the one distinction the document rests on would be
    /// the agent's to make — and an agent that got it wrong would produce a
    /// section indistinguishable from one Keel measured.
    ///
    /// Nothing here is ever `observed`. Observation is what the rest of the
    /// document does; this type only holds what somebody made of it.
    public enum Standing: String, Codable, Sendable, Equatable {
        /// A reading of evidence Keel established.
        case inferred
        /// Advice. Not a rule this project follows, and must never be
        /// rendered as one.
        case suggested

        public var displayName: String {
            switch self {
            case .inferred: return "Inferred"
            case .suggested: return "Suggested"
            }
        }
    }

    /// How many separate statements the reply amounts to, for reporting how
    /// many were dropped.
    public var itemCount: Int {
        (overview == nil ? 0 : 1) + (dependencyFlow == nil ? 0 : 1)
            + conventions.count + boundaries.count + inconsistencies.count
            + risks.count + readingOrder.count + legacyAreas.count + questions.count
    }

    public var isEmpty: Bool {
        overview == nil && dependencyFlow == nil
            && conventions.isEmpty && boundaries.isEmpty && inconsistencies.isEmpty
            && risks.isEmpty && readingOrder.isEmpty && legacyAreas.isEmpty
            && questions.isEmpty
    }

    // MARK: - Limits

    /// Caps, so one field cannot become the document.
    enum Limit {
        static let prose = 1_200
        static let item = 300
        static let items = 10
    }

    // MARK: - Parsing

    public enum ParseError: Error, CustomStringConvertible, Equatable {
        case notJSON
        case empty

        public var description: String {
            switch self {
            case .notJSON:
                return "The agent's reply was not the JSON object it was asked for."
            case .empty:
                return "The agent replied, but with nothing usable in it."
            }
        }
    }

    /// Reads an agent's reply.
    ///
    /// Tolerant about the wrapper and strict about the contents: agents like to
    /// wrap JSON in a fenced code block or a sentence of preamble, which is a
    /// formatting habit rather than a refusal. What is *inside* is then cleaned
    /// field by field.
    public static func parse(_ reply: String) throws -> ProjectInterpretation {
        guard let data = jsonObject(in: reply) else { throw ParseError.notJSON }

        let decoded: Raw
        do {
            decoded = try JSONDecoder().decode(Raw.self, from: data)
        } catch {
            throw ParseError.notJSON
        }

        let interpretation = ProjectInterpretation(
            overview: clean(decoded.overview, limit: Limit.prose),
            dependencyFlow: clean(decoded.dependencyFlow ?? decoded.dataFlow, limit: Limit.prose),
            conventions: clean(decoded.conventions),
            boundaries: clean(decoded.boundaries),
            inconsistencies: clean(decoded.inconsistencies),
            risks: clean(decoded.risks),
            readingOrder: clean(decoded.readingOrder ?? decoded.onboarding),
            legacyAreas: clean(decoded.legacyAreas),
            questions: clean(decoded.questions)
        )

        guard !interpretation.isEmpty else { throw ParseError.empty }
        return interpretation
    }

    /// Drops anything naming something the project does not contain.
    ///
    /// The agent is given facts and asked to interpret them. An agent that
    /// names a `PaymentService` in a project with no such type has stopped
    /// interpreting and started inventing, and the invented name is exactly
    /// what a reader would go looking for. Rather than trying to tell a good
    /// sentence from a bad one, this checks the only thing that can be
    /// checked mechanically: does every type-shaped name in it exist.
    ///
    /// Deliberately narrow. It discards the item that names the thing, not
    /// the whole reply, and it only judges capitalised multi-word identifiers
    /// — ordinary prose, Apple's frameworks and the project's own vocabulary
    /// all pass through untouched.
    public func verified(against vocabulary: Set<String>) -> ProjectInterpretation {
        func keep(_ text: String) -> Bool {
            Self.unsupportedNames(in: text, vocabulary: vocabulary).isEmpty
        }

        return ProjectInterpretation(
            overview: overview.flatMap { keep($0) ? $0 : nil },
            dependencyFlow: dependencyFlow.flatMap { keep($0) ? $0 : nil },
            conventions: conventions.filter(keep),
            boundaries: boundaries.filter(keep),
            inconsistencies: inconsistencies.filter(keep),
            risks: risks.filter(keep),
            readingOrder: readingOrder.filter(keep),
            legacyAreas: legacyAreas.filter(keep),
            questions: questions.filter(keep)
        )
    }

    /// Type-shaped names in a sentence that the project does not declare.
    ///
    /// "Type-shaped" means CamelCase with an inner capital — `ProfileView`,
    /// `APIClient`. A single capitalised word is far more likely to be the
    /// start of a sentence or a proper noun than a claim about a type, so it
    /// is left alone: a check that fired on "Swift" or "The" would throw away
    /// good interpretation to catch nothing.
    static func unsupportedNames(in text: String, vocabulary: Set<String>) -> [String] {
        let pattern = #"\b[A-Z][A-Za-z0-9]*[a-z][A-Za-z0-9]*[A-Z][A-Za-z0-9]*\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let found = Range(match.range, in: text) else { return nil }
            let name = String(text[found])
            return vocabulary.contains(name) ? nil : name
        }
    }

    /// The outermost `{...}` in a reply, ignoring any prose around it.
    private static func jsonObject(in reply: String) -> Data? {
        guard let start = reply.firstIndex(of: "{"),
              let end = reply.lastIndex(of: "}"),
              start < end
        else { return nil }
        return String(reply[start...end]).data(using: .utf8)
    }

    /// Strips the Markdown an agent adds out of habit, then truncates.
    ///
    /// Headings and bullets are removed rather than escaped because Keel owns
    /// the document's structure: a `##` arriving in a field would otherwise
    /// open a section that looks like one Keel wrote.
    static func clean(_ text: String?, limit: Int) -> String? {
        guard let text else { return nil }

        var cleaned = text
            .replacingOccurrences(of: #"^\s*#{1,6}\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*[-*+]\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[`*_]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return nil }

        if cleaned.count > limit {
            cleaned = String(cleaned.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return cleaned
    }

    static func clean(_ items: [String]?) -> [String] {
        (items ?? [])
            .compactMap { clean($0, limit: Limit.item) }
            .prefix(Limit.items)
            .map { $0 }
    }

    /// Decoded shape before cleaning. Every field optional: a reply missing one
    /// is a partial answer, not a failure.
    private struct Raw: Decodable {
        let overview: String?
        let dependencyFlow: String?
        let conventions: [String]?
        let boundaries: [String]?
        let inconsistencies: [String]?
        let risks: [String]?
        let readingOrder: [String]?
        let legacyAreas: [String]?
        let questions: [String]?

        /// Older names for two of the fields. An agent given a cached or
        /// paraphrased prompt reaches for these, and refusing a usable answer
        /// over the spelling of a key would be pedantry.
        let dataFlow: String?
        let onboarding: [String]?
    }
}
