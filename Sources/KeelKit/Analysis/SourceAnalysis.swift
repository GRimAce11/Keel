import Foundation

/// One `import` statement, with where it was written.
///
/// The line is carried because an import is evidence: "this feature depends on
/// SwiftData" is only checkable if it says which file and which line said so.
public struct ImportDeclaration: Codable, Sendable, Equatable {
    public let module: String
    public let line: Int

    public init(module: String, line: Int) {
        self.module = module
        self.line = line
    }
}

/// What parsing found in one Swift file.
public struct FileAnalysis: Codable, Sendable, Equatable {
    public let path: String
    public let imports: [ImportDeclaration]
    public let types: [TypeDeclaration]
    public let functionCount: Int
    public let asyncFunctionCount: Int
    public let throwingFunctionCount: Int

    /// Module names alone, for the many callers that do not care where the
    /// import was written.
    public var importedModules: [String] { imports.map(\.module) }
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

        /// The plural a report uses. Spelled out because naive pluralisation
        /// turns "class" into "classs".
        public var pluralName: String {
            switch self {
            case .structure: return "structs"
            case .classType: return "classes"
            case .enumeration: return "enums"
            case .actorType: return "actors"
            case .protocolType: return "protocols"
            case .extensionOf: return "extensions"
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
/// `ArchitectureDetector` reads this to infer how a project is built, and
/// `document` reads it to describe the codebase. Both consume the same facts,
/// so a claim made in one cannot contradict the other.
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

    /// The same analysis with test sources left out.
    ///
    /// A test double imitates production code on purpose. A stub conforming to
    /// `APIClientProtocol` says nothing about how the app is built, and
    /// counting one would let a test suite change the architecture Keel
    /// reports. Test files are recognised by a `Tests` suffix on a path
    /// component, which is all the layout offers.
    public func excludingTests() -> SourceAnalysis {
        SourceAnalysis(files: files.filter { !Self.isTestPath($0.path) })
    }

    static func isTestPath(_ path: String) -> Bool {
        path.split(separator: "/").contains { component in
            component.lowercased()
                .replacingOccurrences(of: ".swift", with: "")
                .hasSuffix("tests")
        }
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
            for module in Set(file.importedModules) {
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

    // MARK: - Summaries

    /// Declaration counts by kind, in reading order, omitting kinds with none.
    public func declarationCounts() -> [(kind: TypeDeclaration.Kind, count: Int)] {
        let order: [TypeDeclaration.Kind] = [
            .structure, .classType, .enumeration, .protocolType, .actorType, .extensionOf,
        ]
        return order
            .map { (kind: $0, count: types(ofKind: $0).count) }
            .filter { $0.count > 0 }
    }

    /// The patterns worth naming when describing a codebase, with how many
    /// types use each. Only patterns actually present are returned.
    ///
    /// Which patterns are worth naming is a presentation choice rather than a
    /// fact, so it lives here in one place: `inspect` and `document` describe
    /// the same project from the same list, and cannot drift into describing
    /// it differently.
    public func notablePatterns() -> [(name: String, count: Int)] {
        [
            ("@Observable", types(withAttribute: "Observable").count),
            ("ObservableObject", types(conformingTo: "ObservableObject").count),
            ("@MainActor", types(withAttribute: "MainActor").count),
            ("@Model", types(withAttribute: "Model").count),
            ("SwiftUI View", types(conformingTo: "View").count),
            ("ViewModels", types(namedWithSuffix: "ViewModel").count),
            ("Repositories", types(namedWithSuffix: "Repository").count),
        ].filter { $0.count > 0 }
    }
}
