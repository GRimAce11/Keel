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

    /// Two or three sentences orienting someone new.
    public let overview: String?
    /// How a request moves through the app.
    public let dataFlow: String?
    /// Conventions the agent noticed in the facts.
    public let conventions: [String]
    /// Things worth being careful about.
    public let risks: [String]
    /// Where to start reading.
    public let onboarding: [String]

    public init(
        overview: String? = nil,
        dataFlow: String? = nil,
        conventions: [String] = [],
        risks: [String] = [],
        onboarding: [String] = []
    ) {
        self.overview = overview
        self.dataFlow = dataFlow
        self.conventions = conventions
        self.risks = risks
        self.onboarding = onboarding
    }

    public var isEmpty: Bool {
        overview == nil && dataFlow == nil
            && conventions.isEmpty && risks.isEmpty && onboarding.isEmpty
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
            dataFlow: clean(decoded.dataFlow, limit: Limit.prose),
            conventions: clean(decoded.conventions),
            risks: clean(decoded.risks),
            onboarding: clean(decoded.onboarding)
        )

        guard !interpretation.isEmpty else { throw ParseError.empty }
        return interpretation
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
        let dataFlow: String?
        let conventions: [String]?
        let risks: [String]?
        let onboarding: [String]?
    }
}
