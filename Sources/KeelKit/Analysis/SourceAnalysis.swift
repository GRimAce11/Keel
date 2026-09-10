import Foundation

/// What parsing found in one Swift file.
public struct FileAnalysis: Codable, Sendable, Equatable {
    public let path: String
    public let imports: [String]
    public let types: [TypeDeclaration]
    public let functionCount: Int
    public let asyncFunctionCount: Int
    public let throwingFunctionCount: Int
}

// MARK: - Declarations

public struct TypeDeclaration: Codable, Sendable, Equatable {
    public let name: String
    public let kind: Kind
    public let path: String
    public let line: Int
    /// Superclass and protocol conformances together.
    ///
    /// Syntax cannot separate them — both appear in the same clause, and only
    /// the compiler knows which name is a class. The field is named for what
    /// it actually contains rather than implying a distinction Keel cannot
    /// make.
    public let inheritedTypes: [String]
    /// Attribute names without arguments: `Observable`, `MainActor`, `Model`.
    public let attributes: [String]
    public let accessLevel: String?
    public let isFinal: Bool
    public let memberCount: Int

    public enum Kind: String, Codable, Sendable, Equatable {
        case structure
        case classType
        case enumeration
        case actorType
        case protocolType
        case extensionOf

        public var displayName: String {
            switch self {
            case .structure: return "struct"
            case .classType: return "class"
            case .enumeration: return "enum"
            case .actorType: return "actor"
            case .protocolType: return "protocol"
            case .extensionOf: return "extension"
            }
        }
    }

    public func hasAttribute(_ name: String) -> Bool {
        attributes.contains(name)
    }

    public func conforms(to name: String) -> Bool {
        inheritedTypes.contains(name)
    }
}

// MARK: - Aggregate

/// Every fact parsing found across a project.
///
/// Phase 11 reads this to infer architecture, and `document` reads it to
/// describe the codebase. Both consume the same facts, so a claim made in one
/// cannot contradict the other.
public struct SourceAnalysis: Codable, Sendable, Equatable {
    public let files: [FileAnalysis]

    public init(files: [FileAnalysis]) {
        self.files = files
    }

    public var types: [TypeDeclaration] {
        files.flatMap(\.types)
    }

    /// Declarations only — extensions are excluded, since an extension is a
    /// second mention of a type rather than another type.
    public var declaredTypes: [TypeDeclaration] {
        types.filter { $0.kind != .extensionOf }
    }

    public var fileCount: Int { files.count }
    public var functionCount: Int { files.reduce(0) { $0 + $1.functionCount } }
    public var asyncFunctionCount: Int { files.reduce(0) { $0 + $1.asyncFunctionCount } }
    public var throwingFunctionCount: Int { files.reduce(0) { $0 + $1.throwingFunctionCount } }

    /// How many files import each module, most-used first.
    public func importCounts() -> [(module: String, files: Int)] {
        var counts: [String: Int] = [:]
        for file in files {
            // A file importing the same module twice still counts once.
            for module in Set(file.imports) {
                counts[module, default: 0] += 1
            }
        }
        return counts
            .map { (module: $0.key, files: $0.value) }
            .sorted { ($0.files, $1.module) > ($1.files, $0.module) }
    }

    public func types(withAttribute attribute: String) -> [TypeDeclaration] {
        types.filter { $0.hasAttribute(attribute) }
    }

    public func types(conformingTo name: String) -> [TypeDeclaration] {
        types.filter { $0.conforms(to: name) }
    }

    public func types(ofKind kind: TypeDeclaration.Kind) -> [TypeDeclaration] {
        types.filter { $0.kind == kind }
    }

    /// Types whose name ends in a suffix, e.g. `ViewModel` or `Repository`.
    ///
    /// A naming convention, not a structural fact — kept as an explicit query
    /// so callers decide how much weight to give it.
    public func types(namedWithSuffix suffix: String) -> [TypeDeclaration] {
        declaredTypes.filter { $0.name.hasSuffix(suffix) }
    }
}
