import Foundation

/// The grain a dependency is read at.
///
/// The same facts answer "what depends on what" at several sizes, and which
/// size you want depends on the question. "Which files does this one need" is
/// a refactoring question; "does Core depend on a feature" is an architecture
/// one. Aggregating is a view over one set of links rather than a second graph,
/// so the two can never disagree.
public enum DependencyScope: String, Codable, Sendable, Equatable, CaseIterable {
    case type
    case file
    case layer
    case feature
    case module
    case target

    public var displayName: String {
        switch self {
        case .type: return "Type"
        case .file: return "File"
        case .layer: return "Layer"
        case .feature: return "Feature"
        case .module: return "Module"
        case .target: return "Target"
        }
    }

    /// The scopes at which a dependency is an architectural statement,
    /// coarsest first.
    ///
    /// Type and file are left out, and not only because a tree of them runs to
    /// thousands of lines. A loop between types is ordinary Swift — a protocol
    /// and its conformer refer to each other, and the compiler does not mind —
    /// so reporting one as a cycle would teach people to ignore the section
    /// that also carries the real ones. A loop between two *features* is a
    /// different claim entirely.
    public static let structural: [DependencyScope] = [.target, .module, .feature, .layer]
}

/// Where a dependency came from.
public enum DependencyOrigin: String, Codable, Sendable, Equatable {
    /// An `import`. Crosses module boundaries and nothing smaller.
    case importStatement
    /// One type naming another. Needs no boundary to cross, which is what lets
    /// it see inside a single-module app.
    case typeReference

    public var displayName: String {
        switch self {
        case .importStatement: return "import"
        case .typeReference: return "reference"
        }
    }
}

// MARK: - Endpoints

/// One end of a dependency, carrying everything needed to name it at any
/// scope.
public struct DependencyEndpoint: Codable, Sendable, Equatable {
    /// Qualified type name, when the link came from a type reference.
    public let type: String?
    /// The file it was written in or declared in, when Keel knows one.
    public let file: String?
    /// Where that file sits: target, module, feature, layer.
    public let owner: FileOwnership
    /// The module named, when this end is something an `import` pointed at.
    public let module: String?
    /// Whether this end is outside the project — an Apple framework, a
    /// package, or a module Keel could not place.
    public let isExternal: Bool

    public init(
        type: String? = nil,
        file: String? = nil,
        owner: FileOwnership = FileOwnership(),
        module: String? = nil,
        isExternal: Bool = false
    ) {
        self.type = type
        self.file = file
        self.owner = owner
        self.module = module
        self.isExternal = isExternal
    }

    /// What to call this end at a given scope, or nil if it has no name there.
    ///
    /// Something outside the project is one node at every scope, because that
    /// is the whole of what an import says about it: `SwiftData` has no file,
    /// no feature and no layer that Keel can see, and inventing one would be
    /// worse than naming it plainly.
    public func name(at scope: DependencyScope) -> String? {
        if isExternal { return module }

        switch scope {
        case .type: return type
        case .file: return file
        case .layer: return owner.layer
        case .feature: return owner.feature
        case .module: return owner.module
        case .target: return owner.target
        }
    }

    /// The most specific name this end has, for evidence lines.
    public var label: String {
        type ?? module ?? file ?? owner.owner ?? "unknown"
    }
}

// MARK: - Links

/// One thing depending on another, at the finest grain Keel can state it, with
/// the line that said so.
///
/// Everything else in this file is an aggregation of these. Keeping the links
/// canonical means a feature-level edge can always be unfolded back into the
/// lines that produced it, which is what makes the coarse answer checkable.
public struct DependencyLink: Codable, Sendable, Equatable {
    public let from: DependencyEndpoint
    public let to: DependencyEndpoint
    public let origin: DependencyOrigin
    /// What the source said, in one phrase: `property`, `conforms to`,
    /// `import`.
    public let detail: String
    public let file: String
    public let line: Int
    /// How firmly the link itself is established — not how important it is.
    public let support: Support

    public init(
        from: DependencyEndpoint,
        to: DependencyEndpoint,
        origin: DependencyOrigin,
        detail: String,
        file: String,
        line: Int,
        support: Support
    ) {
        self.from = from
        self.to = to
        self.origin = origin
        self.detail = detail
        self.file = file
        self.line = line
        self.support = support
    }

    public var location: String { "\(file):\(line)" }

    /// `ProfileViewModel → AuthService  property`
    public var describedInFull: String {
        "\(from.label) → \(to.label)  \(detail)"
    }
}

// MARK: - Violations

/// A dependency pointing the wrong way.
///
/// Only one rule, and deliberately so. A cycle is wrong whichever way you read
/// it, so it needs nothing to establish direction. A *direction* violation
/// needs something in the project to say which way the arrow should point, and
/// the only thing that does is what the top-level folders are called: code in
/// `Core` or `Shared` exists to be used by features, so a dependency running
/// the other way makes the shared code unusable without that feature.
///
/// Cross-feature dependencies are **not** here. Nothing in a project layout
/// establishes that one feature may not use another, and calling every such
/// edge a violation would be a guess dressed as a rule. They are reported as
/// edges, and left to be judged.
public struct DependencyViolation: Codable, Sendable, Equatable {
    public let rule: Rule
    public let from: String
    public let to: String
    public let scope: DependencyScope
    public let evidence: [DependencyLink]

    public init(
        rule: Rule,
        from: String,
        to: String,
        scope: DependencyScope,
        evidence: [DependencyLink]
    ) {
        self.rule = rule
        self.from = from
        self.to = to
        self.scope = scope
        self.evidence = evidence
    }

    public enum Rule: String, Codable, Sendable, Equatable, CaseIterable {
        case sharedCodeDependsOnFeature

        public var summary: String {
            switch self {
            case .sharedCodeDependsOnFeature:
                return "Shared code depends on a feature, so it cannot be used without it"
            }
        }
    }

    public var headline: String { "\(from) → \(to)" }
}

// MARK: - Graph

/// Everything the project depends on, from every source Keel has.
///
/// Imports and type references answer the same question at different reaches.
/// An import crosses module boundaries and nothing smaller; a type reference
/// needs no boundary at all. Held apart they each have a blind spot — the
/// import graph cannot see inside a single-module app, and the type graph
/// cannot see a package. Joined, the blind spots do not overlap.
///
/// Derived, not stored. It is a join of two graphs the model already holds, so
/// materialising it onto `ProjectModel` would put the same facts in a JSON
/// document three times and give them a chance to drift apart. `--graph`
/// builds it on demand.
public struct DependencyGraph: Codable, Sendable, Equatable {

    public let links: [DependencyLink]
    public let violations: [DependencyViolation]

    public static let empty = DependencyGraph(links: [], violations: [])

    public init(links: [DependencyLink], violations: [DependencyViolation]) {
        self.links = links
        self.violations = violations
    }

    // MARK: Aggregation

    /// Every dependency at one scope, with the links behind each.
    ///
    /// Self-edges are dropped: a feature whose files refer to each other does
    /// not depend on itself, it just has more than one file. The links are
    /// still there to be read at a finer scope.
    public func edges(
        at scope: DependencyScope,
        includingExternal: Bool = false
    ) -> [DependencyEdge] {
        var grouped: [Pair: [DependencyLink]] = [:]

        for link in links {
            guard includingExternal || !link.to.isExternal else { continue }
            guard let from = link.from.name(at: scope),
                  let to = link.to.name(at: scope),
                  from != to
            else { continue }

            grouped[Pair(from: from, to: to), default: []].append(link)
        }

        return grouped
            .map { pair, evidence in
                DependencyEdge(
                    from: pair.from,
                    to: pair.to,
                    scope: scope,
                    origins: DependencyOrigin.allCases.filter { origin in
                        evidence.contains { $0.origin == origin }
                    },
                    evidence: evidence.sorted { ($0.file, $0.line) < ($1.file, $1.line) }
                )
            }
            .sorted { ($0.from, $0.to) < ($1.from, $1.to) }
    }

    /// Every name that appears at a scope, either end.
    public func nodes(at scope: DependencyScope, includingExternal: Bool = false) -> [String] {
        var names: Set<String> = []
        for edge in edges(at: scope, includingExternal: includingExternal) {
            names.insert(edge.from)
            names.insert(edge.to)
        }
        return names.sorted()
    }

    /// What one node depends on directly.
    public func dependencies(
        of name: String,
        at scope: DependencyScope,
        includingExternal: Bool = false
    ) -> [String] {
        edges(at: scope, includingExternal: includingExternal)
            .filter { $0.from == name }
            .map(\.to)
    }

    /// Everything one node depends on, directly or through something else.
    ///
    /// The node itself appears only if a cycle leads back to it, which is a
    /// useful thing to notice rather than an artefact to filter away.
    public func transitiveDependencies(
        of name: String,
        at scope: DependencyScope,
        includingExternal: Bool = false
    ) -> [String] {
        Cycles.reachable(
            from: name,
            in: adjacency(at: scope, includingExternal: includingExternal)
        ).sorted()
    }

    /// Dependency cycles at one scope, each as the loop that closes it.
    ///
    /// The one Keel could not report before: two features referring to each
    /// other's types compile into the same module, so no import crosses
    /// between them and an import-only graph is silent by construction.
    ///
    /// Ask at a scope in `DependencyScope.structural`. A loop at type or file
    /// scope is usually nothing — a protocol and the type conforming to it
    /// name each other in every codebase — and the query answers honestly at
    /// those scopes rather than pretending otherwise, but the answer is not an
    /// architecture finding.
    public func cycles(at scope: DependencyScope) -> [[String]] {
        Cycles.find(in: adjacency(at: scope, includingExternal: false))
    }

    /// Every node at a scope with what it directly depends on, for drawing.
    public func tree(at scope: DependencyScope, includingExternal: Bool = false) -> [Branch] {
        let all = edges(at: scope, includingExternal: includingExternal)
        var grouped: [String: [DependencyEdge]] = [:]
        for edge in all {
            grouped[edge.from, default: []].append(edge)
        }
        return grouped
            .map { Branch(name: $0.key, dependencies: $0.value) }
            .sorted { $0.name < $1.name }
    }

    private func adjacency(
        at scope: DependencyScope,
        includingExternal: Bool
    ) -> [String: Set<String>] {
        var adjacency: [String: Set<String>] = [:]
        for edge in edges(at: scope, includingExternal: includingExternal) {
            adjacency[edge.from, default: []].insert(edge.to)
        }
        return adjacency
    }

    // MARK: Shapes

    public struct DependencyEdge: Codable, Sendable, Equatable {
        public let from: String
        public let to: String
        public let scope: DependencyScope
        /// Which kinds of source established this edge, in declaration order.
        public let origins: [DependencyOrigin]
        public let evidence: [DependencyLink]

        public init(
            from: String,
            to: String,
            scope: DependencyScope,
            origins: [DependencyOrigin],
            evidence: [DependencyLink]
        ) {
            self.from = from
            self.to = to
            self.scope = scope
            self.origins = origins
            self.evidence = evidence
        }
    }

    public struct Branch: Codable, Sendable, Equatable {
        public let name: String
        public let dependencies: [DependencyEdge]
    }

    private struct Pair: Hashable {
        let from: String
        let to: String
    }
}

extension DependencyOrigin: CaseIterable {}
