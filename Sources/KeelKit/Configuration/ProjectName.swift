import Foundation

/// A validated project name.
///
/// The name a developer types becomes a Swift module name, a target name, a
/// scheme name and part of a bundle identifier. Each of those has different
/// rules, so the raw input is normalised once here and every consumer reads a
/// derived form rather than re-deriving its own.
public struct ProjectName: Sendable {
    /// The name as it appears in Xcode: `MyApp`.
    public let raw: String

    /// Lowercased and hyphen-separated, for bundle identifiers: `my-app`.
    public let slug: String

    /// True when the input needed cleaning up to become valid.
    public let wasSanitized: Bool

    /// The original input, kept so callers can explain what changed.
    public let original: String

    public enum ValidationError: Error, CustomStringConvertible, Equatable {
        case empty
        case noUsableCharacters(String)
        case reservedWord(String)

        public var description: String {
            switch self {
            case .empty:
                return "Project name cannot be empty."
            case .noUsableCharacters(let input):
                return """
                    "\(input)" has no letters or digits to build a name from. \
                    Use something like MyApp.
                    """
            case .reservedWord(let word):
                return """
                    "\(word)" is a Swift keyword and cannot be used as a module \
                    name. Try something like \(word.capitalized)App.
                    """
            }
        }
    }

    /// Swift keywords that would break `import <Name>` or the generated target.
    /// Not exhaustive across all contextual keywords — these are the ones that
    /// actually fail to compile as a module name.
    private static let reservedWords: Set<String> = [
        "associatedtype", "borrowing", "case", "catch", "class", "consuming",
        "continue", "default", "defer", "deinit", "do", "else", "enum",
        "extension", "fallthrough", "fileprivate", "for", "func", "guard",
        "if", "import", "in", "init", "inout", "internal", "let", "nil",
        "operator", "private", "protocol", "public", "repeat", "rethrows",
        "return", "self", "static", "struct", "subscript", "super", "switch",
        "throw", "throws", "try", "typealias", "var", "where", "while",
        // Not keywords, but colliding with these makes for a miserable time.
        "swift", "foundation", "swiftui", "uikit", "combine", "observation",
    ]

    public init(_ input: String) throws {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.empty }

        // Split on anything that is not alphanumeric, then upper-camel-case the
        // pieces. "my cool app", "my-cool-app" and "my_cool_app" all land on
        // "MyCoolApp", which is what someone typing any of them meant.
        let words = trimmed
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)

        guard !words.isEmpty else {
            throw ValidationError.noUsableCharacters(trimmed)
        }

        // Preserve existing internal casing so "MyAPIClient" is not flattened
        // to "Myapiclient" — only the first character of each word is raised.
        let joined = words.map { word in
            guard let first = word.first else { return word }
            return first.uppercased() + word.dropFirst()
        }.joined()

        // A module name cannot begin with a digit.
        let normalized = joined.first?.isNumber == true ? "App" + joined : joined

        guard !Self.reservedWords.contains(normalized.lowercased()) else {
            throw ValidationError.reservedWord(normalized)
        }

        self.raw = normalized
        self.original = trimmed
        self.wasSanitized = normalized != trimmed
        self.slug = Self.slugify(words)
    }

    /// `["My", "Cool", "App"]` -> `"my-cool-app"`. Splits words that are
    /// already camel-cased so `MyApp` becomes `my-app`, not `myapp`.
    private static func slugify(_ words: [String]) -> String {
        words
            .flatMap(splitCamelCase)
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    private static func splitCamelCase(_ word: String) -> [String] {
        var parts: [String] = []
        var current = ""
        for character in word {
            if character.isUppercase, !current.isEmpty {
                parts.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }
}

// MARK: - Equatable

extension ProjectName: Equatable, Hashable {
    /// Compares the normalised name only.
    ///
    /// `original` and `wasSanitized` describe what the developer typed, not
    /// what the project is called. Including them would make `MyApp` typed as
    /// "my app" unequal to `MyApp` typed exactly — and would break round
    /// tripping, since the encoded form is the normalised name.
    public static func == (lhs: ProjectName, rhs: ProjectName) -> Bool {
        lhs.raw == rhs.raw
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(raw)
    }
}

// MARK: - Codable

extension ProjectName: Codable {
    /// Encoded as the plain name, so a serialised configuration stays readable
    /// and decoding re-runs validation rather than trusting stored fields.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }
}
