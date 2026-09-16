import Foundation
import Testing
@testable import KeelKit

/// The diagram is a view over the dependency graph, so most of what matters is
/// that it says exactly what the graph says — and refuses to draw when it
/// cannot say it clearly.
@Suite("ArchitectureDiagram")
struct ArchitectureDiagramTests {

    /// One module-scope link, built by hand so a test can name the shapes the
    /// generated fixtures never produce — a folder with a space in it, a
    /// folder called `end`.
    private func link(from: String, to: String, line: Int = 1) -> DependencyLink {
        DependencyLink(
            from: DependencyEndpoint(
                file: "\(from)/File.swift",
                owner: FileOwnership(target: "App", module: from)
            ),
            to: DependencyEndpoint(
                file: "\(to)/File.swift",
                owner: FileOwnership(target: "App", module: to)
            ),
            origin: .typeReference,
            detail: "\(from) refers to \(to)",
            file: "\(from)/File.swift",
            line: line,
            support: .observed
        )
    }

    private func graph(_ pairs: [(String, String)]) -> DependencyGraph {
        DependencyGraph(
            links: pairs.enumerated().map { link(from: $1.0, to: $1.1, line: $0 + 1) },
            violations: []
        )
    }

    private func drawn(_ pairs: [(String, String)]) throws -> ArchitectureDiagram {
        guard case .drawn(let diagram) = ArchitectureDiagram.at(.module, in: graph(pairs)) else {
            throw DiagramMissing()
        }
        return diagram
    }

    private struct DiagramMissing: Error {}

    // MARK: - When there is nothing to draw

    @Test("A scope with no edges produces no diagram")
    func noEdgesDrawsNothing() {
        guard case .nothing = ArchitectureDiagram.at(.module, in: graph([])) else {
            Issue.record("drew a diagram for a graph with no edges")
            return
        }
    }

    @Test("A scope the project is not organised at produces no diagram")
    func unusedScopeDrawsNothing() {
        // The links carry a module on both ends and nothing else, so layer
        // scope has no names at all. An empty box would be worse than no box.
        guard case .nothing = ArchitectureDiagram.at(.layer, in: graph([("App", "Core")])) else {
            Issue.record("drew a diagram for a scope with no names")
            return
        }
    }

    @Test("Too many nodes is said, not drawn and not truncated")
    func refusesToDrawAWall() {
        let pairs = (0...ArchitectureDiagram.nodeLimit).map { ("Hub", "Module\($0)") }

        guard case .tooLarge(let count) = ArchitectureDiagram.at(.module, in: graph(pairs)) else {
            Issue.record("drew a diagram past the node limit")
            return
        }
        // Hub plus one node per edge. Reporting the real total is the point:
        // a truncated graph does not look truncated, so the document says how
        // big it is instead of drawing part of it.
        #expect(count == pairs.count + 1)
        #expect(count > ArchitectureDiagram.nodeLimit)
    }

    // MARK: - What it draws

    @Test("Every edge the graph reports becomes an arrow")
    func drawsEveryEdge() throws {
        let diagram = try drawn([("App", "Core"), ("App", "Features"), ("Features", "Core")])
        let mermaid = diagram.mermaid()

        #expect(mermaid.hasPrefix("```mermaid\nflowchart TD"))
        #expect(mermaid.hasSuffix("```"))
        #expect(mermaid.contains("    App --> Core"))
        #expect(mermaid.contains("    App --> Features"))
        #expect(mermaid.contains("    Features --> Core"))
        #expect(diagram.nodes == ["App", "Core", "Features"])
    }

    @Test("A name that is already an identifier is used as written")
    func readableNamesStayReadable() throws {
        // `n0 --> n1` would be correct and unreadable. Someone reading the
        // Markdown source should see the same names as someone reading the
        // rendered picture.
        let mermaid = try drawn([("App", "Core")]).mermaid()

        #expect(mermaid.contains("App --> Core"))
        #expect(!mermaid.contains("n0"))
        #expect(!mermaid.contains("[\""))
    }

    @Test("A name mermaid could not parse gets an identifier and keeps its label")
    func unsafeNamesAreRelabelled() throws {
        let mermaid = try drawn([("Design System", "Core Kit")]).mermaid()

        // The real names survive, as labels rather than as syntax.
        #expect(mermaid.contains("[\"Design System\"]"))
        #expect(mermaid.contains("[\"Core Kit\"]"))
        #expect(!mermaid.contains("Design System -->"))
        #expect(mermaid.contains(" --> "))
    }

    @Test("A folder named for mermaid syntax does not become syntax")
    func reservedWordsAreRelabelled() throws {
        // `end` closes a subgraph. A module called `end` written bare would
        // not draw wrongly — it would fail to draw at all.
        let mermaid = try drawn([("App", "end")]).mermaid()

        #expect(mermaid.contains("[\"end\"]"))
        #expect(!mermaid.contains("--> end"))
    }

    @Test("A quote in a name cannot end the label it sits in")
    func quotesAreNeutralised() throws {
        let mermaid = try drawn([("App", "Say \"Hello\"")]).mermaid()

        #expect(!mermaid.contains("\"Say \"Hello\"\""))
        #expect(mermaid.contains("Say 'Hello'"))
    }

    // MARK: - Tangles

    @Test("Two nodes in a loop still draw — that is a picture, not a tangle")
    func smallLoopsStillDraw() throws {
        let diagram = try drawn([("A", "B"), ("B", "A")])
        #expect(diagram.looping == ["A", "B"])
    }

    @Test("Three nodes in a loop still draw — a triangle is legible")
    func trianglesStillDraw() throws {
        let diagram = try drawn([("A", "B"), ("B", "C"), ("C", "A")])
        #expect(diagram.nodes.count == 3)
    }

    @Test("Four nodes that all reach each other are said, not drawn")
    func refusesToDrawAKnot() {
        // The case that shipped broken: seven features with five in one knot
        // sailed past the node limit and rendered as a hairball. Node count
        // was the wrong measure.
        let pairs = [("A", "B"), ("B", "A"), ("B", "C"), ("C", "B"), ("C", "D"), ("D", "A")]

        guard case .tooTangled(let knot, let total) = ArchitectureDiagram.at(.module, in: graph(pairs)) else {
            Issue.record("drew a diagram of a four-node knot")
            return
        }
        #expect(knot == 4)
        #expect(total == 4)
    }

    @Test("Separate small loops are separate, and still draw")
    func doesNotMergeUnrelatedLoops() throws {
        // Two two-node loops are two small knots. Counting every looping node
        // together would call this a four-node tangle and refuse a diagram
        // well worth having.
        let diagram = try drawn([("A", "B"), ("B", "A"), ("C", "D"), ("D", "C")])

        #expect(diagram.looping.count == 4)
        #expect(ArchitectureDiagram.largestKnot(in: [["A", "B"], ["C", "D"]]) == 2)
    }

    @Test("Cycles sharing a node are one knot")
    func mergesOverlappingLoops() {
        #expect(ArchitectureDiagram.largestKnot(in: [["A", "B"], ["B", "C"]]) == 3)
        #expect(ArchitectureDiagram.largestKnot(in: []) == 0)
        // Order must not matter: merging has to fold a group already recorded.
        #expect(ArchitectureDiagram.largestKnot(in: [["A", "B"], ["C", "D"], ["B", "C"]]) == 4)
    }

    // MARK: - Cycles

    @Test("Nodes on a cycle are marked, and only those")
    func marksCycles() throws {
        let diagram = try drawn([("App", "Core"), ("Core", "Shared"), ("Shared", "Core")])
        let mermaid = diagram.mermaid()

        #expect(diagram.looping == ["Core", "Shared"])
        #expect(mermaid.contains("classDef cycle stroke:#F05138"))
        #expect(mermaid.contains("class Core,Shared cycle"))
        // App reaches the loop but is not in it, and saying otherwise would
        // point at the wrong file.
        #expect(!mermaid.contains("class App"))
    }

    @Test("A graph with no cycle carries no cycle styling")
    func leavesAcyclicGraphsAlone() throws {
        let diagram = try drawn([("App", "Core"), ("App", "Shared")])

        #expect(diagram.looping.isEmpty)
        #expect(!diagram.mermaid().contains("classDef"))
        #expect(!diagram.mermaid().contains("class "))
    }
}
