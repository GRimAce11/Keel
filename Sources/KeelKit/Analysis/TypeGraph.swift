import Foundation

/// How one type mentions another.
///
/// The distinctions matter because they carry different weight. A property
/// whose declared type is `ProfileRepository` is a dependency the type cannot
/// be built without; a `Logger.shared` in one method body is a mention. Both
/// are real, and a report that treats them alike is misleading in whichever
/// direction it rounds.
public enum ReferenceKind: String, Codable, Sendable, Equatable, CaseIterable {
    /// A class's superclass.
    case inheritance
    /// A protocol the type conforms to.
    case conformance
    /// A class's first inherited type, where Keel could not tell which it is.
    ///
    /// Only a class can be ambiguous, and only in first position: Swift
    /// requires the superclass to come first, so everything after it is a
    /// conformance by the grammar. When the name resolves — to a class or a
    /// protocol this project declares, or to one of the Apple types Keel
    /// recognises — the answer is settled and this case is not used.
    case inheritsOrConforms
    /// The declared type of a stored or computed property.
    case propertyType
    /// A parameter of a function or method.
    case parameterType
    /// A parameter of an initializer — how most Swift dependency injection is
    /// written, and worth telling apart from an ordinary parameter.
    case initializerDependency
    /// A function's return type.
    case returnType
    /// A generic parameter's constraint, or a `where` clause.
    case genericConstraint
    /// `ProfileViewModel()` — the type is constructed here.
    case constructorReference
    /// `APIClient.shared` — a member reached through the type's own name.
    case memberReference
    /// The type is named somewhere else: a local variable's annotation, a
    /// cast, a typealias.
    case typeReference

    public var displayName: String {
        switch self {
        case .inheritance: return "inherits"
        case .conformance: return "conforms to"
        case .inheritsOrConforms: return "inherits or conforms to"
        case .propertyType: return "property"
        case .parameterType: return "parameter"
        case .initializerDependency: return "init parameter"
        case .returnType: return "returns"
        case .genericConstraint: return "generic constraint"
        case .constructorReference: return "constructs"
        case .memberReference: return "member of"
        case .typeReference: return "names"
        }
    }

    /// Whether the relationship is written into a declaration rather than into
    /// a body.
    ///
    /// A declared relationship is part of the type's shape and survives any
    /// rewrite of its methods; a body reference may not. `check` will want the
    /// distinction in phase 6, and a reader wants it now.
    public var isStructural: Bool {
        switch self {
        case .inheritance, .conformance, .inheritsOrConforms,
             .propertyType, .parameterType, .initializerDependency,
             .returnType, .genericConstraint:
            return true
        case .constructorReference, .memberReference, .typeReference:
            return false
        }
    }
}

// MARK: - Roles

/// What a type appears to be for.
///
/// Every value here is a claim about purpose, which is softer than anything
/// else in the model — so each node carries the `Support` behind its role.
/// A type conforming to SwiftUI's `View` is a view because the code says so; a
/// type called `ArticleRepository` is a repository because somebody named it
/// one. The rules below read only what is in front of them, and `other` is
/// used freely rather than stretching a guess to fit.
public enum TypeRole: String, Codable, Sendable, Equatable, CaseIterable {
    case view
    case viewModel
    case viewController
    case repository
    case service
    case client
    case model
    case persistence
    case container
    case coordinator
    case other

    public var displayName: String {
        switch self {
        case .view: return "View"
        case .viewModel: return "ViewModel"
        case .viewController: return "ViewController"
        case .repository: return "Repository"
        case .service: return "Service"
        case .client: return "Client"
        case .model: return "Model"
        case .persistence: return "Persistence"
        case .container: return "Container"
        case .coordinator: return "Coordinator"
        case .other: return "Other"
        }
    }

    /// The band a role sits in, for reports that are organised by layer
    /// rather than by type.
    public var layer: Layer {
        switch self {
        case .view, .viewModel, .viewController: return .presentation
        case .service, .model, .container, .coordinator: return .domain
        case .repository, .client, .persistence: return .data
        case .other: return .unclassified
        }
    }

    public enum Layer: String, Codable, Sendable, Equatable, CaseIterable {
        case presentation
        case domain
        case data
        case unclassified

        public var displayName: String {
            switch self {
            case .presentation: return "Presentation"
            case .domain: return "Domain"
            case .data: return "Data"
            case .unclassified: return "Unclassified"
            }
        }
    }
}

// MARK: - Nodes and edges

/// One type this project declares, with where it lives and what it looks like
/// it is for.
public struct TypeNode: Codable, Sendable, Equatable {
    /// Qualified name, so a nested `Outer.Inner` is not confused with a
    /// top-level `Inner`.
    public let name: String
    public let kind: TypeDeclaration.Kind
    public let path: String
    public let line: Int
    public let role: TypeRole
    /// Whether the role came from the code or from the name.
    public let roleSupport: Support
    /// Which feature, module and target the declaring file belongs to —
    /// the same ownership the import graph uses, so the two graphs describe
    /// the project in one vocabulary.
    public let owner: FileOwnership

    public init(
        name: String,
        kind: TypeDeclaration.Kind,
        path: String,
        line: Int,
        role: TypeRole,
        roleSupport: Support,
        owner: FileOwnership
    ) {
        self.name = name
        self.kind = kind
        self.path = path
        self.line = line
        self.role = role
        self.roleSupport = roleSupport
        self.owner = owner
    }

    public var location: String { "\(path):\(line)" }
}

/// One type referring to another, and where it said so.
public struct TypeReference: Codable, Sendable, Equatable {
    public let from: String
    public let to: String
    public let kind: ReferenceKind
    public let file: String
    public let line: Int
    /// How firmly the referenced name was matched to a declaration.
    ///
    /// `observed` when exactly one declaration in the project carries that
    /// name. `conventional` when several do — the reference is still real, but
    /// which of the same-named types it reaches is a name match rather than a
    /// resolution, and syntax alone cannot settle it. `undetermined` never
    /// appears: a name that matches no declaration is not a project
    /// relationship, so it is left out rather than reported weakly.
    public let support: Support

    public init(
        from: String,
        to: String,
        kind: ReferenceKind,
        file: String,
        line: Int,
        support: Support
    ) {
        self.from = from
        self.to = to
        self.kind = kind
        self.file = file
        self.line = line
        self.support = support
    }

    public var location: String { "\(file):\(line)" }

    /// `ProfileView → ProfileViewModel (property) at App/ProfileView.swift:12`
    public var describedInFull: String {
        "\(from) → \(to) (\(kind.displayName)) at \(location)"
    }
}

// MARK: - Findings

/// A relationship worth a second look.
///
/// Reported, never failed. Each rule below describes a shape that is usually a
/// mistake and sometimes deliberate — a small app where the view really does
/// hold the repository, a core utility that genuinely knows one feature. Keel
/// is not in a position to tell those apart, so it names what it found and
/// leaves the judgement where it belongs. `check` does not read these; that is
/// phase 6's decision to make, deliberately, rather than a side effect of this
/// phase existing.
public struct RelationshipFinding: Codable, Sendable, Equatable {
    public let rule: Rule
    public let subject: String
    public let object: String
    /// The weaker of the two endpoints' role support.
    ///
    /// A finding about two types whose roles are both naming-derived is a
    /// naming-derived finding, and says so. Taking the stronger of the two
    /// would let one solid endpoint launder a guess about the other.
    public let support: Support
    public let evidence: [TypeReference]

    public init(
        rule: Rule,
        subject: String,
        object: String,
        support: Support,
        evidence: [TypeReference]
    ) {
        self.rule = rule
        self.subject = subject
        self.object = object
        self.support = support
        self.evidence = evidence
    }

    public enum Rule: String, Codable, Sendable, Equatable, CaseIterable {
        /// A view reaching a networking client, with no layer in between.
        case viewReachesClient
        /// A view reaching a repository, with no layer in between.
        case viewReachesRepository
        /// A view model reaching a view — presentation flowing backwards.
        case viewModelReachesView
        /// Shared code depending on a feature, which inverts the usual
        /// direction and makes the shared code unusable without that feature.
        case coreReachesFeature
        /// One feature reaching into another's types.
        ///
        /// The relationship phase 2 structurally could not see: inside a
        /// single module, features import nothing from each other because
        /// there is no module boundary to cross.
        case featureReachesFeature

        public var summary: String {
            switch self {
            case .viewReachesClient: return "A view reaches a networking client directly"
            case .viewReachesRepository: return "A view reaches a repository directly"
            case .viewModelReachesView: return "A view model refers back to a view"
            case .coreReachesFeature: return "Shared code depends on a feature"
            case .featureReachesFeature: return "One feature depends on another"
            }
        }
    }

    public var headline: String { "\(subject) → \(object)" }
}

// MARK: - Graph

/// What the project's own types are made of each other.
///
/// The counterpart to `ImportGraph`, and the answer to its stated limitation.
/// Imports only cross module boundaries, so in a single-target app — which is
/// most apps — no import can show that one feature depends on another. Type
/// references are not bounded that way: they are visible wherever one type
/// names another, module or no module.
///
/// What it does not do, and will not: this is a graph of *mentions*, drawn from
/// syntax. It says `ProfileViewModel` names `ProfileRepository` at a line that
/// can be opened. It does not say that line runs, how often, or in what order.
/// Nothing here is a call graph, and nothing here should be read as one.
public struct TypeGraph: Codable, Sendable, Equatable {

    public let nodes: [TypeNode]
    public let references: [TypeReference]
    public let findings: [RelationshipFinding]

    public static let empty = TypeGraph(nodes: [], references: [], findings: [])

    public init(nodes: [TypeNode], references: [TypeReference], findings: [RelationshipFinding]) {
        self.nodes = nodes
        self.references = references
        self.findings = findings
    }

    // MARK: Queries

    public func node(named name: String) -> TypeNode? {
        nodes.first { $0.name == name }
    }

    /// Every type Keel reads as filling one role.
    ///
    /// The canonical answer to "which types here are views". Asking it any
    /// other way — a suffix here, a conformance there — is how two parts of
    /// one report come to disagree about the same project, which is worse
    /// than either of them being wrong on its own.
    public func types(inRole role: TypeRole) -> [TypeNode] {
        nodes.filter { $0.role == role }
    }

    /// The same, as names, for callers that need to filter declarations.
    public func names(inRole role: TypeRole) -> Set<String> {
        Set(types(inRole: role).map(\.name))
    }

    public func references(from name: String) -> [TypeReference] {
        references.filter { $0.from == name }
    }

    public func references(to name: String) -> [TypeReference] {
        references.filter { $0.to == name }
    }

    /// Types nothing else in the project refers to.
    ///
    /// Not dead code, and must not be called that: an entry point, a SwiftUI
    /// `App`, a type used only from a storyboard or only by name are all
    /// unreferenced and all alive. It is a list of places to look.
    public func unreferencedTypes() -> [TypeNode] {
        let referenced = Set(references.map(\.to))
        return nodes.filter { !referenced.contains($0.name) }
    }

    /// Every distinct pair, with all the ways one reaches the other.
    ///
    /// A type usually names another several times — a property, an init
    /// parameter, three calls. That is one relationship with four pieces of
    /// evidence, not four relationships.
    public func relationships() -> [Relationship] {
        var grouped: [Pair: [TypeReference]] = [:]
        for reference in references {
            grouped[Pair(from: reference.from, to: reference.to), default: []].append(reference)
        }

        return grouped
            .map { pair, evidence in
                Relationship(
                    from: pair.from,
                    to: pair.to,
                    kinds: ReferenceKind.allCases.filter { kind in
                        evidence.contains { $0.kind == kind }
                    },
                    evidence: evidence.sorted { ($0.file, $0.line) < ($1.file, $1.line) }
                )
            }
            .sorted { ($0.from, $0.to) < ($1.from, $1.to) }
    }

    /// Relationships where both ends have a role, grouped by the layer the
    /// referring type sits in. The architecture-shaped view of the same facts.
    public func relationships(inLayer layer: TypeRole.Layer) -> [Relationship] {
        let roles = Dictionary(nodes.map { ($0.name, $0.role) }, uniquingKeysWith: { first, _ in first })
        return relationships().filter { relationship in
            roles[relationship.from]?.layer == layer && roles[relationship.to] != nil
        }
    }

    /// How many types carry each role, most common first. Roles nobody has are
    /// left out rather than reported as zero.
    public func roleCounts() -> [(role: TypeRole, count: Int)] {
        TypeRole.allCases
            .map { role in (role: role, count: nodes.filter { $0.role == role }.count) }
            .filter { $0.count > 0 }
            .sorted { ($0.count, $1.role.rawValue) > ($1.count, $0.role.rawValue) }
    }

    // MARK: Shapes

    public struct Relationship: Codable, Sendable, Equatable {
        public let from: String
        public let to: String
        /// Every way `from` reaches `to`, in the order the kinds are declared.
        public let kinds: [ReferenceKind]
        public let evidence: [TypeReference]

        /// The strongest thing that can be said about the pair.
        ///
        /// A declared relationship outranks a body reference: if a type both
        /// holds another as a property and constructs it twice, "property" is
        /// the honest one-word summary.
        public var principalKind: ReferenceKind { kinds.first ?? .typeReference }
    }

    private struct Pair: Hashable {
        let from: String
        let to: String
    }
}
