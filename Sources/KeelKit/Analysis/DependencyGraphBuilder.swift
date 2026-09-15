import Foundation

/// Joins what the project imports with what its types refer to.
///
/// Neither source is complete on its own. An import crosses module boundaries
/// and nothing smaller, so in a single-target app it cannot see one feature
/// using another. A type reference sees that and nothing outside the project,
/// so it cannot see a package. Each is blind exactly where the other looks.
///
/// Nothing is invented in the join. Every link here traces back to a line in
/// one of the two graphs, and both of those trace back to a line in a file.
struct DependencyGraphBuilder {

    let inputs: Inputs

    struct Inputs {
        let importGraph: ImportGraph
        let typeGraph: TypeGraph
        /// Needed for their roles, which is the only thing in a project layout
        /// that establishes which way a dependency ought to run.
        let modules: [Module]
    }

    func build() -> DependencyGraph {
        let links = importLinks() + typeLinks()
        guard !links.isEmpty else { return .empty }

        let graph = DependencyGraph(links: links, violations: [])
        return DependencyGraph(links: links, violations: violations(in: graph))
    }

    // MARK: - Imports

    /// One link per `import`, from the importing file to the module it names.
    private func importLinks() -> [DependencyLink] {
        inputs.importGraph.edges.map { edge in
            DependencyLink(
                from: DependencyEndpoint(file: edge.file, owner: edge.owner),
                to: Self.endpoint(forImported: edge.module, kind: edge.kind),
                origin: .importStatement,
                detail: "import \(edge.module)",
                file: edge.file,
                line: edge.line,
                // An import statement names its module outright. What that
                // module *is* may be uncertain — `ImportKind` carries that —
                // but that the file imports it is not.
                support: .observed
            )
        }
    }

    /// What an imported name refers to.
    ///
    /// Another target in this project is internal and has a module of its own,
    /// which is exactly what a target's product is. Everything else is outside
    /// the project: an Apple framework, a package, or a name Keel could not
    /// place — and an unplaceable name stays a node rather than disappearing,
    /// because a dependency nobody can identify is still a dependency.
    static func endpoint(forImported module: String, kind: ImportKind) -> DependencyEndpoint {
        switch kind {
        case .project:
            return DependencyEndpoint(
                owner: FileOwnership(target: module, module: module),
                module: module,
                isExternal: false
            )
        case .system, .package, .unknown:
            return DependencyEndpoint(module: module, isExternal: true)
        }
    }

    // MARK: - Type references

    /// One link per type reference, between the files the two types live in.
    private func typeLinks() -> [DependencyLink] {
        let nodes = Dictionary(
            inputs.typeGraph.nodes.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first }
        )

        return inputs.typeGraph.references.compactMap { reference in
            guard let subject = nodes[reference.from], let object = nodes[reference.to] else {
                return nil
            }
            return DependencyLink(
                from: DependencyEndpoint(
                    type: subject.name, file: subject.path, owner: subject.owner
                ),
                to: DependencyEndpoint(
                    type: object.name, file: object.path, owner: object.owner
                ),
                origin: .typeReference,
                detail: reference.kind.displayName,
                file: reference.file,
                line: reference.line,
                support: reference.support
            )
        }
    }

    // MARK: - Violations

    /// Dependencies running against a direction the project itself establishes.
    ///
    /// Only one thing in a project layout establishes a direction: what the
    /// top-level folders are called. `Core` and `Shared` exist to be used by
    /// features, so a dependency the other way makes the shared code unusable
    /// without that feature. Nothing establishes that features may not use
    /// each other, so those are reported as edges and not as faults.
    ///
    /// Read at module scope, where the claim is about the shared code as a
    /// whole rather than about one file in it.
    private func violations(in graph: DependencyGraph) -> [DependencyViolation] {
        let roles = Dictionary(
            inputs.modules.map { ($0.name, $0.role) }, uniquingKeysWith: { first, _ in first }
        )

        var found: [DependencyViolation] = []
        var grouped: [String: [DependencyLink]] = [:]

        for link in graph.links {
            guard let module = link.from.owner.module,
                  roles[module] == .core || roles[module] == .shared,
                  link.from.owner.feature == nil,
                  let feature = link.to.owner.feature
            else { continue }

            grouped["\(module)\u{0}\(feature)", default: []].append(link)
        }

        for (key, evidence) in grouped {
            let parts = key.split(separator: "\u{0}", omittingEmptySubsequences: false)
            found.append(
                DependencyViolation(
                    rule: .sharedCodeDependsOnFeature,
                    from: String(parts[0]),
                    to: String(parts[1]),
                    scope: .module,
                    evidence: evidence.sorted { ($0.file, $0.line) < ($1.file, $1.line) }
                )
            )
        }

        return found.sorted { ($0.from, $0.to) < ($1.from, $1.to) }
    }
}
