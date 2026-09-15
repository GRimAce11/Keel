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

/// One place a type declaration mentions a name, before anything is known
/// about what that name refers to.
///
/// Deliberately unresolved. The parser can see that `ProfileView` has a
/// property written `ProfileViewModel`; it cannot see whether that name is a
/// type this project declares, one a package vends, or one that no longer
/// exists. `TypeGraphBuilder` answers that by checking the name against every
/// declaration found in the project, the same way `ImportGraphBuilder` answers
/// what an imported module is. Keeping the two steps apart is what makes the
/// second one arguable: the syntax is a fact, the resolution is a lookup, and
/// a reader can disagree with the lookup without doubting the fact.
public struct TypeUsage: Codable, Sendable, Hashable {
    /// Qualified name of the declaration the mention was written inside.
    public let owner: String
    /// The name exactly as written — `Article`, `[Article]`'s element,
    /// `Outer.Inner`. Never rewritten, so evidence quotes the source.
    public let referenced: String
    public let kind: ReferenceKind
    public let line: Int

    public init(owner: String, referenced: String, kind: ReferenceKind, line: Int) {
        self.owner = owner
        self.referenced = referenced
        self.kind = kind
        self.line = line
    }
}

/// What parsing found in one Swift file.
public struct FileAnalysis: Codable, Sendable, Equatable {
    public let path: String
    public let imports: [ImportDeclaration]
    public let types: [TypeDeclaration]
    /// Every mention of a name by a type in this file, unresolved.
    ///
    /// Working material. `TypeGraphBuilder` reads these once, resolves them
    /// against the project's declarations and throws away everything that does
    /// not match — which on a real project is most of them, since a file
    /// mentions far more of Apple's types than its own. The model that comes
    /// out of a scan therefore carries the resolved `TypeGraph` and not these;
    /// see `withoutReferences()`.
    public let references: [TypeUsage]
    public let functionCount: Int
    public let asyncFunctionCount: Int
    public let throwingFunctionCount: Int

    init(
        path: String,
        imports: [ImportDeclaration],
        types: [TypeDeclaration],
        references: [TypeUsage],
        functionCount: Int,
        asyncFunctionCount: Int,
        throwingFunctionCount: Int
    ) {
        self.path = path
        self.imports = imports
        self.types = types
        self.references = references
        self.functionCount = functionCount
        self.asyncFunctionCount = asyncFunctionCount
        self.throwingFunctionCount = throwingFunctionCount
    }

    /// Module names alone, for the many callers that do not care where the
    /// import was written.
    public var importedModules: [String] { imports.map(\.module) }

    func withoutReferences() -> FileAnalysis {
        FileAnalysis(
            path: path,
            imports: imports,
            types: types,
            references: [],
            functionCount: functionCount,
            asyncFunctionCount: asyncFunctionCount,
            throwingFunctionCount: throwingFunctionCount
        )
    }
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

    /// Every unresolved mention, across every file.
    public var references: [TypeUsage] {
        files.flatMap(\.references)
    }

    /// The same analysis with the raw mentions dropped.
    ///
    /// What a scan puts on the model, once `TypeGraphBuilder` has had them.
    /// Keeping them would roughly double what `inspect --json` prints, to say
    /// a second time — unresolved, and mostly about Apple's types — what the
    /// type graph already says resolved. Dropping them here rather than
    /// hiding them from the encoder keeps the model honest: what `--json`
    /// prints is the whole of what the model holds, and decoding it gives
    /// back an equal value.
    public func withoutReferences() -> SourceAnalysis {
        SourceAnalysis(files: files.map { $0.withoutReferences() })
    }

    /// Declarations only — extensions are excluded, since an extension is a
    /// second mention of a type rather than another type.
    public var declaredTypes: [TypeDeclaration] {
        types.filter { $0.kind != .extensionOf }
    }

    /// The protocols this project declares itself.
    ///
    /// The line between "our abstraction" and "Apple's", which three separate
    /// rules were each working out for themselves.
    public var declaredProtocolNames: Set<String> {
        Set(declaredTypes.filter { $0.kind == .protocolType }.map(\.name))
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
