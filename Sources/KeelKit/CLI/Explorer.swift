import Foundation

/// Walks somebody through a project they did not write.
///
/// Every screen is a view over the one `ProjectModel` the other commands read,
/// so nothing here can discover a fact `inspect` would deny. What it adds is a
/// way to arrive at the fact you wanted without knowing which flag produces it
/// — which is the difference between a report and a tool, on a codebase you
/// are seeing for the first time.
///
/// Driven by an `AnswerProvider` rather than by `readLine`, so the whole thing
/// is testable without a terminal. That also makes the non-interactive
/// behaviour fall out for free: with no human, every question takes its
/// default, and the default everywhere is to leave.
public struct Explorer {

    public let model: ProjectModel
    let answers: any AnswerProvider
    let console: Console

    public init(model: ProjectModel, answers: any AnswerProvider, console: Console = .shared) {
        self.model = model
        self.answers = answers
        self.console = console
    }

    /// What the explorer can show. `exit` is last and is every menu's default,
    /// so a run with nobody answering ends rather than looping.
    enum Screen: CaseIterable {
        case architecture
        case features
        case dependencies
        case dataFlow
        case types
        case findings
        case search
        case exit

        var title: String {
            switch self {
            case .architecture: return "Architecture"
            case .features: return "Features"
            case .dependencies: return "Dependencies"
            case .dataFlow: return "Data flow"
            case .types: return "Types by role"
            case .findings: return "Architecture warnings"
            case .search: return "Search"
            case .exit: return "Exit"
            }
        }
    }

    // MARK: - Running

    public func run() {
        summary()

        while true {
            let screens = Screen.allCases
            let choice = answers.choice(
                "What would you like to explore?",
                options: screens.map(\.title),
                default: screens.count - 1
            )
            let screen = screens[min(max(choice, 0), screens.count - 1)]

            guard screen != .exit else { return }
            show(screen)
            console.write()
        }
    }

    private func show(_ screen: Screen) {
        switch screen {
        case .architecture: architecture()
        case .features: features()
        case .dependencies: dependencies()
        case .dataFlow: dataFlow()
        case .types: types()
        case .findings: findings()
        case .search: search()
        case .exit: return
        }
    }

    // MARK: - Home

    private func summary() {
        console.heading(model.name)
        console.detail("Swift files   \(model.source.swiftFileCount)")
        console.detail("Types         \(model.typeGraph.nodes.count)")
        console.detail("Features      \(model.features.count)")
        console.detail("Targets       \(model.allTargets.count)")
        console.write()
        console.detail(model.architecture.summary)
        // The promise the whole tool rests on, worth restating where somebody
        // is about to lean on it.
        console.detail("Read from the project's own files. Nothing here needs it to compile.")
    }

    // MARK: - Architecture

    private func architecture() {
        console.heading("Architecture")
        for line in model.architecture.flowSummary {
            console.detail(line)
        }
        console.write()

        let findings = model.architecture.findings
        let width = findings.map(\.dimension.count).max() ?? 0

        for finding in findings {
            let label = finding.dimension.padding(toLength: width, withPad: " ", startingAt: 0)
            let basis = finding.support == .undetermined ? "" : "  \(finding.sourceSummary)"
            console.detail("\(label)  \(finding.value)\(basis)")
        }

        console.write()
        guard let finding = pick(
            "Show the evidence for which one?",
            findings,
            label: { "\($0.dimension): \($0.value)" }
        ) else { return }

        console.heading("\(finding.dimension) — \(finding.value)")
        for item in finding.evidence {
            let stance = item.stance == .supporting ? "" : " (\(item.stance.rawValue))"
            console.detail("\(item.statement)\(stance)")
            console.detail("  \(item.basis.displayName)")
            for location in item.locations {
                console.detail("  \(location)")
            }
        }
    }

    // MARK: - Features

    private func features() {
        guard !model.features.isEmpty else {
            console.heading("Features")
            console.detail("This project is not organised into feature folders.")
            return
        }

        console.heading("Features (\(model.features.count))")
        for feature in model.features {
            console.detail("\(feature.name)  \(Prose.count(feature.swiftFileCount, "file"))")
        }

        console.write()
        guard let feature = pick("Look at which one?", model.features, label: \.name) else { return }
        show(feature)
    }

    private func show(_ feature: Feature) {
        console.heading("Feature: \(feature.name)")

        console.detail("Layers")
        if feature.layers.isEmpty {
            console.detail("  none — the folder is flat")
        } else {
            for layer in feature.layers { console.detail("  \(layer)") }
        }

        let graph = model.dependencyGraph()
        let out = graph.dependencies(of: feature.name, at: .feature)
        console.write()
        console.detail("Depends on")
        if out.isEmpty {
            console.detail("  nothing else in this project")
        } else {
            for name in out { console.detail("  \(name)") }
        }

        let incoming = graph.edges(at: .feature).filter { $0.to == feature.name }.map(\.from)
        if !incoming.isEmpty {
            console.write()
            console.detail("Depended on by")
            for name in incoming.sorted() { console.detail("  \(name)") }
        }

        let owned = model.typeGraph.nodes.filter { $0.owner.feature == feature.name }
        for role in TypeRole.allCases {
            let inRole = owned.filter { $0.role == role }
            guard !inRole.isEmpty, role != .other else { continue }
            console.write()
            console.detail("\(role.displayName)s")
            for node in inRole { console.detail("  \(node.name)  \(node.location)") }
        }
    }

    // MARK: - Dependencies

    private func dependencies() {
        let graph = model.dependencyGraph()
        let scopes = DependencyScope.structural.filter { !graph.edges(at: $0).isEmpty }

        guard !scopes.isEmpty else {
            console.heading("Dependencies")
            console.detail("Nothing in this project groups into parts that depend on each other.")
            console.detail("Try Types by role for the type-level view.")
            return
        }

        guard let scope = pick("At what scope?", scopes, label: \.displayName) else { return }

        let edges = graph.edges(at: scope)
        console.heading("\(scope.displayName) dependencies (\(edges.count))")
        for edge in edges {
            console.detail("\(edge.from) → \(edge.to)  \(Prose.count(edge.evidence.count, "reference"))")
        }

        for cycle in graph.cycles(at: scope) {
            console.write()
            console.warn("Cycle: \(cycle.joined(separator: " → "))")
        }

        console.write()
        guard let edge = pick(
            "Show the evidence for which one?",
            edges,
            label: { "\($0.from) → \($0.to)" }
        ) else { return }

        console.heading("\(edge.from) → \(edge.to)")
        for link in edge.evidence {
            console.detail("\(link.location)  \(link.describedInFull)")
        }
    }

    // MARK: - Data flow

    private func dataFlow() {
        console.heading("Data flow")

        let flow = model.architecture.presentationFlow
        guard !flow.value.isUnknown else {
            // The honest answer, printed rather than replaced by the likeliest
            // shape. A path nobody can trace is not a path.
            console.detail("Undetermined from static analysis.")
            for item in flow.evidence {
                console.detail(item.statement)
            }
            return
        }

        console.detail("\(flow.value.displayName)  \(flow.sourceSummary)")
        for item in flow.evidence {
            console.detail(item.statement)
            for location in item.locations { console.detail("  \(location)") }
        }

        console.write()
        console.detail("These are references written in source. Keel does not claim any of them")
        console.detail("runs, or in what order.")
    }

    // MARK: - Types

    private func types() {
        let roles = model.typeGraph.roleCounts().filter { $0.role != .other }
        guard !roles.isEmpty else {
            console.heading("Types")
            console.detail("No type here matches a role Keel recognises.")
            return
        }

        guard let entry = pick(
            "Which role?",
            roles,
            label: { "\($0.role.displayName) (\($0.count))" }
        ) else { return }

        let nodes = model.typeGraph.types(inRole: entry.role)
        console.heading("\(entry.role.displayName) (\(nodes.count))")
        for node in nodes {
            console.detail("\(node.name)  \(node.roleSupport.displayName)  \(node.location)")
        }

        console.write()
        guard let node = pick("Look at which one?", nodes, label: \.name) else { return }
        show(node)
    }

    private func show(_ node: TypeNode) {
        console.heading(node.name)
        console.detail("\(node.kind.displayName)  \(node.location)")
        console.detail("Role    \(node.role.displayName)  \(node.roleSupport.displayName)")
        if let owner = node.owner.owner {
            console.detail("Owner   \(owner)")
        }

        let outgoing = model.typeGraph.references(from: node.name)
        console.write()
        console.detail("Refers to")
        if outgoing.isEmpty {
            console.detail("  nothing else in this project")
        } else {
            for reference in outgoing {
                console.detail("  → \(reference.to)  \(reference.kind.displayName)  \(reference.location)")
            }
        }

        let incoming = model.typeGraph.references(to: node.name)
        console.write()
        console.detail("Referred to by")
        if incoming.isEmpty {
            // Not the same as unused: an entry point, a SwiftUI App, or a type
            // reached only by name is unreferenced and entirely alive.
            console.detail("  nothing — which is not the same as unused")
        } else {
            for reference in incoming {
                console.detail("  ← \(reference.from)  \(reference.kind.displayName)  \(reference.location)")
            }
        }
    }

    // MARK: - Findings

    private func findings() {
        let diagnostics = ProjectChecker(model: model).check()
        guard !diagnostics.isEmpty else {
            console.heading("Architecture warnings")
            console.success("Nothing to report.")
            return
        }

        console.heading("Architecture warnings (\(diagnostics.count))")
        for diagnostic in diagnostics {
            let mark = diagnostic.severity == .error ? "error  " : "warning"
            console.detail("\(mark)  \(diagnostic.message)")
        }

        console.write()
        guard let diagnostic = pick("Look at which one?", diagnostics, label: \.message) else {
            return
        }

        console.heading(diagnostic.rule)
        console.detail("Severity  \(diagnostic.severity.displayName)")
        if let location = diagnostic.location {
            console.detail("Source    \(location)")
        }
        if let path = diagnostic.path, path.count > 1 {
            console.detail("Path      \(path.joined(separator: " → "))")
        }
        if !diagnostic.evidence.isEmpty {
            console.write()
            console.detail("Evidence")
            for item in diagnostic.evidence {
                console.detail("  \(item.location)  \(item.statement)")
            }
        }
        if let rule = CheckRules.rule(diagnostic.rule) {
            console.write()
            console.detail("Why this rule exists")
            console.detail("  \(rule.explanation)")
            console.detail("Why it is a \(diagnostic.severity.displayName)")
            console.detail("  \(rule.severityPolicy)")
        }
    }

    // MARK: - Search

    private func search() {
        let query = answers.text("Search for", default: "").trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            console.detail("Nothing to search for.")
            return
        }

        let matches = Self.matches(for: query, in: model)
        console.heading("\(Prose.count(matches.count, "match")) for \"\(query)\"")

        guard !matches.isEmpty else {
            console.detail("Nothing here is called that.")
            return
        }
        for match in matches.prefix(Self.searchLimit) {
            console.detail("\(match.kind)  \(match.name)\(match.detail.map { "  \($0)" } ?? "")")
        }
        if matches.count > Self.searchLimit {
            console.detail("and \(matches.count - Self.searchLimit) more")
        }
    }

    /// One thing the search found.
    struct Match: Equatable {
        let kind: String
        let name: String
        let detail: String?
    }

    /// Everything in the project whose name contains the query.
    ///
    /// Case-insensitive and substring-based, because somebody exploring a
    /// codebase they did not write is guessing at names. Ordered by kind so
    /// the answer is the same every time.
    static func matches(for query: String, in model: ProjectModel) -> [Match] {
        let needle = query.lowercased()
        func hit(_ name: String) -> Bool { name.lowercased().contains(needle) }

        var found: [Match] = []

        found += model.features.filter { hit($0.name) }
            .map { Match(kind: "feature ", name: $0.name, detail: $0.path) }
        found += model.modules.filter { hit($0.name) }
            .map { Match(kind: "module  ", name: $0.name, detail: $0.path) }
        found += model.allTargets.filter { hit($0.name) }
            .map { Match(kind: "target  ", name: $0.name, detail: $0.productType.displayName) }
        found += model.typeGraph.nodes.filter { hit($0.name) }
            .map { Match(kind: "type    ", name: $0.name, detail: $0.location) }
        found += model.analysis.files.map(\.path).filter { hit($0) }.sorted()
            .map { Match(kind: "file    ", name: $0, detail: nil) }
        found += model.dependencies.filter { hit($0.name) }
            .map { Match(kind: "package ", name: $0.name, detail: $0.requirement) }

        return found
    }

    private static let searchLimit = 30

    // MARK: - Choosing

    /// Offers a list and returns what was chosen, or nil for "go back".
    ///
    /// Back is always last and always the default, so a run with nobody
    /// answering walks out of every screen instead of into one.
    private func pick<T>(
        _ question: String,
        _ items: [T],
        label: (T) -> String
    ) -> T? {
        guard !items.isEmpty else { return nil }

        let options = items.map(label) + ["Back"]
        let choice = answers.choice(question, options: options, default: options.count - 1)
        guard choice >= 0, choice < items.count else { return nil }
        return items[choice]
    }

    private func pick<T>(
        _ question: String,
        _ items: [T],
        label: KeyPath<T, String>
    ) -> T? {
        pick(question, items) { $0[keyPath: label] }
    }
}
