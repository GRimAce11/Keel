import Foundation

/// A picture of what depends on what, drawn from the links `keel inspect
/// --graph` already prints.
///
/// Mermaid rather than ASCII, because `PROJECT.md` is read on GitHub more
/// often than in a terminal and GitHub renders it. Nothing here is a second
/// source of truth: every arrow is one aggregation of the same links, so the
/// picture and the report cannot disagree, and any arrow can be unfolded back
/// into the file and line that produced it.
public struct ArchitectureDiagram {

    /// Past this a flowchart stops being a diagram and becomes a wall.
    ///
    /// The alternative — drawing the most connected two dozen and dropping the
    /// rest — was rejected on purpose. A truncated dependency graph does not
    /// look truncated: an edge to an omitted node simply is not there, and a
    /// reader concludes the dependency does not exist. Saying "too large to
    /// draw" is the honest answer, and `keel inspect --graph` reads it a node
    /// at a time.
    static let nodeLimit = 24

    /// Mermaid reads these as syntax rather than as a node name, so a folder
    /// that happens to be called `end` gets a generated identifier instead.
    private static let reserved: Set<String> = [
        "end", "graph", "subgraph", "flowchart", "class", "classdef",
        "click", "style", "linkstyle", "direction",
    ]

    public let scope: DependencyScope
    public let edges: [DependencyGraph.DependencyEdge]
    public let nodes: [String]
    /// Nodes sitting on a cycle at this scope, which is the one thing in a
    /// dependency diagram worth colouring.
    public let looping: Set<String>

    /// How many nodes may depend on one another in both directions before the
    /// picture stops being one.
    ///
    /// `flowchart TD` places nodes in ranks, top to bottom, which needs a
    /// direction of flow to exist. A node with arrows both in and out cannot
    /// be ranked, and once several of them are mutually reachable the layout
    /// has nothing to sort by and draws a tangle.
    ///
    /// Three is still legible — it is a triangle. Four is where it stops being
    /// a diagram, so four is where Keel stops drawing one.
    ///
    /// This is the measure the node limit was missing. A seven-node graph with
    /// five features in one knot is unreadable while a twenty-node tree is
    /// fine, and counting nodes cannot tell those apart.
    static let tangleLimit = 4

    public enum Result {
        case drawn(ArchitectureDiagram)
        /// Readable as a report but not as a picture. Carries the count so the
        /// document can say how big rather than only that it gave up.
        case tooLarge(nodeCount: Int)
        /// So much of it depends on itself that ranking is impossible. Carries
        /// both counts, because "five of six" is the finding — a reader learns
        /// more from that sentence than from the drawing it replaces.
        case tooTangled(knot: Int, total: Int)
        /// Fewer than two nodes, or no edges between them. A scope the project
        /// is not organised at produces no section rather than an empty box.
        case nothing
    }

    public static func at(_ scope: DependencyScope, in graph: DependencyGraph) -> Result {
        let edges = graph.edges(at: scope)
        guard !edges.isEmpty else { return .nothing }

        var names: Set<String> = []
        for edge in edges {
            names.insert(edge.from)
            names.insert(edge.to)
        }
        guard names.count > 1 else { return .nothing }
        guard names.count <= nodeLimit else { return .tooLarge(nodeCount: names.count) }

        let cycles = graph.cycles(at: scope)
        let knot = largestKnot(in: cycles)
        guard knot < tangleLimit else {
            return .tooTangled(knot: knot, total: names.count)
        }

        return .drawn(
            ArchitectureDiagram(
                scope: scope,
                edges: edges,
                nodes: names.sorted(),
                looping: Set(cycles.flatMap { $0 })
            )
        )
    }

    /// The largest set of nodes that all reach one another, approximated by
    /// merging cycles that share a node.
    ///
    /// Merging matters. Two separate two-node loops are two small knots and
    /// draw perfectly well; counting every looping node together would call
    /// that a four-node tangle and refuse a diagram worth having.
    static func largestKnot(in cycles: [[String]]) -> Int {
        var groups: [Set<String>] = []

        for cycle in cycles {
            var merged = Set(cycle)
            var rest: [Set<String>] = []
            for group in groups {
                if group.isDisjoint(with: merged) {
                    rest.append(group)
                } else {
                    merged.formUnion(group)
                }
            }
            groups = rest + [merged]
        }

        return groups.map(\.count).max() ?? 0
    }

    // MARK: - Drawing

    public func mermaid() -> String {
        let ids = identifiers()
        var lines = ["flowchart TD"]

        // Only the nodes whose name could not be used as written. The rest
        // read better as bare identifiers, and mermaid infers them from the
        // arrows anyway.
        for node in nodes where ids[node] != node {
            lines.append("    \(ids[node]!)[\"\(escaped(node))\"]")
        }

        for edge in edges {
            guard let from = ids[edge.from], let to = ids[edge.to] else { continue }
            lines.append("    \(from) --> \(to)")
        }

        // No fill, so the highlight survives whichever theme the reader has.
        if !looping.isEmpty {
            let members = nodes.filter { looping.contains($0) }.compactMap { ids[$0] }
            lines.append("")
            lines.append("    classDef cycle stroke:#F05138,stroke-width:2px")
            lines.append("    class \(members.joined(separator: ",")) cycle")
        }

        return "```mermaid\n" + lines.joined(separator: "\n") + "\n```"
    }

    /// What to call each node in the mermaid source.
    ///
    /// The name itself when it is already a safe identifier, because
    /// `App --> Core` is legible to someone reading the Markdown source and
    /// `n0 --> n1` is not. Anything else — a space, a dash, a leading digit, a
    /// word mermaid reserves — gets a generated one with the real name as its
    /// label.
    private func identifiers() -> [String: String] {
        var ids: [String: String] = [:]
        var used: Set<String> = []

        for (index, node) in nodes.enumerated() {
            let usable = !node.isEmpty
                && (node.first?.isLetter ?? false)
                && node.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
                && !Self.reserved.contains(node.lowercased())
                && !used.contains(node)

            let id = usable ? node : "n\(index)"
            ids[node] = id
            used.insert(id)
        }
        return ids
    }

    /// A quote would end the label it sits in.
    private func escaped(_ name: String) -> String {
        name.replacingOccurrences(of: "\"", with: "'")
    }
}
