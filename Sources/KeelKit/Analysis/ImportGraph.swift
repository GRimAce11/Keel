import Foundation

/// Where one Swift file sits in a project.
///
/// Every field is read from the directory layout, because with synchronized
/// folder groups the project file says nothing about it. That makes ownership
/// a naming-based fact, and `ImportEdge` records it as one — a file under
/// `Features/Profile/Data` belongs to the Profile feature because of where
/// somebody put it, not because the compiler says so.
public struct FileOwnership: Codable, Sendable, Equatable {
    public let target: String?
    /// Top-level source grouping: `App`, `Core`, `Features`.
    public let module: String?
    /// Feature name, when the file sits under a feature folder.
    public let feature: String?
    /// `Data`, `Domain`, `Presentation` — when the feature is divided.
    public let layer: String?

    public init(
        target: String? = nil,
        module: String? = nil,
        feature: String? = nil,
        layer: String? = nil
    ) {
        self.target = target
        self.module = module
        self.feature = feature
        self.layer = layer
    }

    /// What to call this file's owner when reporting a dependency.
    ///
    /// Most specific first. The target is the last resort so that files outside
    /// the app's source tree — a test bundle, an extension — still have an
    /// owner; without it their imports vanish from the graph, including the
    /// `@testable import` that is a real project edge.
    public var owner: String? { feature ?? module ?? target }
}

/// What kind of thing an import names.
public enum ImportKind: String, Codable, Sendable, Equatable, CaseIterable {
    /// An Apple framework.
    case system
    /// A product from a package this project depends on.
    case package
    /// Another target or module in this project.
    case project
    /// Keel does not recognise it. Reported as unknown rather than guessed at.
    case unknown

    public var displayName: String {
        switch self {
        case .system: return "system"
        case .package: return "package"
        case .project: return "project"
        case .unknown: return "unknown"
        }
    }
}

/// One `import`, with where it was written and what it reaches for.
public struct ImportEdge: Codable, Sendable, Equatable {
    public let file: String
    public let line: Int
    public let module: String
    public let kind: ImportKind
    public let owner: FileOwnership

    /// `Probe/Features/Articles/Data/ArticleRepository.swift:5`
    public var location: String { "\(file):\(line)" }
}

// MARK: - Graph

/// What the project's own files reach for.
///
/// A deliberate limitation, stated rather than hidden: imports only cross
/// *module* boundaries. In a single-target iOS app every feature compiles into
/// the same module, so one feature using another's types produces no import at
/// all and no edge here. This graph is therefore complete for what it measures
/// and silent about intra-module coupling — which is a different question, and
/// one imports cannot answer.
public struct ImportGraph: Codable, Sendable, Equatable {

    public let edges: [ImportEdge]
    /// True when every target compiles as one module, which is what makes
    /// feature-to-feature edges impossible rather than merely absent.
    public let isSingleModule: Bool

    public init(edges: [ImportEdge], isSingleModule: Bool) {
        self.edges = edges
        self.isSingleModule = isSingleModule
    }

    // MARK: Queries

    /// Modules imported by each owner, most-imported first, with evidence.
    public func dependencies(of kind: ImportKind? = nil) -> [Dependency] {
        var grouped: [String: [String: [ImportEdge]]] = [:]

        for edge in edges {
            guard let owner = edge.owner.owner else { continue }
            guard kind == nil || edge.kind == kind else { continue }
            grouped[owner, default: [:]][edge.module, default: []].append(edge)
        }

        return grouped
            .map { owner, modules in
                Dependency(
                    owner: owner,
                    imports: modules
                        .map { ImportedModule(module: $0.key, kind: $0.value[0].kind, evidence: $0.value) }
                        .sorted { ($0.evidence.count, $1.module) > ($1.evidence.count, $0.module) }
                )
            }
            .sorted { $0.owner < $1.owner }
    }

    /// Edges where one part of the project imports another, which is the only
    /// kind that can form a cycle.
    public func projectEdges() -> [(from: String, to: String, evidence: ImportEdge)] {
        edges.compactMap { edge in
            guard edge.kind == .project, let from = edge.owner.owner, from != edge.module else {
                return nil
            }
            return (from: from, to: edge.module, evidence: edge)
        }
    }

    /// Import cycles, as the loop of owners involved.
    ///
    /// Reported, not judged: a cycle between modules is usually a problem and
    /// occasionally deliberate, and this phase only says it exists.
    public func cycles() -> [[String]] {
        var adjacency: [String: Set<String>] = [:]
        for edge in projectEdges() {
            adjacency[edge.from, default: []].insert(edge.to)
        }

        var found: [[String]] = []
        var seen: Set<String> = []

        // Depth-first, keeping the path so a rediscovered node names the loop
        // rather than only reporting that one exists.
        func walk(_ node: String, _ path: [String], _ onPath: Set<String>) {
            for next in (adjacency[node] ?? []).sorted() {
                if onPath.contains(next) {
                    guard let start = path.firstIndex(of: next) else { continue }
                    let cycle = Array(path[start...]) + [next]
                    // One cycle, whichever node it was entered from.
                    let signature = Set(cycle)
                    if !found.contains(where: { Set($0) == signature }) { found.append(cycle) }
                    continue
                }
                guard !seen.contains(next) else { continue }
                walk(next, path + [next], onPath.union([next]))
            }
            seen.insert(node)
        }

        for node in adjacency.keys.sorted() where !seen.contains(node) {
            walk(node, [node], [node])
        }
        return found
    }

    // MARK: Shapes

    public struct Dependency: Codable, Sendable, Equatable {
        public let owner: String
        public let imports: [ImportedModule]
    }

    public struct ImportedModule: Codable, Sendable, Equatable {
        public let module: String
        public let kind: ImportKind
        public let evidence: [ImportEdge]
    }
}
