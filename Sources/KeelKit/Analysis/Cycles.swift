import Foundation

/// Finds loops in a directed graph of names.
///
/// One implementation, shared. Both the import graph and the unified
/// dependency graph report cycles, and two copies of a depth-first search
/// would eventually disagree about the same project — reporting a loop in one
/// command and not the other, which is worse than reporting neither.
enum Cycles {

    /// Every loop in the graph, each as the path that closes it.
    ///
    /// A cycle is named rather than merely counted: "Profile → Auth → Profile"
    /// tells somebody where to start, and "one cycle found" does not. The same
    /// loop entered from a different node is one cycle, so it is reported once.
    static func find(in adjacency: [String: Set<String>]) -> [[String]] {
        var found: [[String]] = []
        var settled: Set<String> = []

        // Depth-first, keeping the path so a rediscovered node names the loop
        // rather than only reporting that one exists.
        func walk(_ node: String, _ path: [String], _ onPath: Set<String>) {
            for next in (adjacency[node] ?? []).sorted() {
                if onPath.contains(next) {
                    guard let start = path.firstIndex(of: next) else { continue }
                    let cycle = Array(path[start...]) + [next]
                    let signature = Set(cycle)
                    if !found.contains(where: { Set($0) == signature }) { found.append(cycle) }
                    continue
                }
                guard !settled.contains(next) else { continue }
                walk(next, path + [next], onPath.union([next]))
            }
            settled.insert(node)
        }

        for node in adjacency.keys.sorted() where !settled.contains(node) {
            walk(node, [node], [node])
        }
        return found
    }

    /// Everything reachable from a node, not counting the node itself unless a
    /// cycle leads back to it.
    static func reachable(from start: String, in adjacency: [String: Set<String>]) -> Set<String> {
        var seen: Set<String> = []
        var queue = Array(adjacency[start] ?? [])

        while let next = queue.popLast() {
            guard seen.insert(next).inserted else { continue }
            queue += adjacency[next] ?? []
        }
        return seen
    }
}
