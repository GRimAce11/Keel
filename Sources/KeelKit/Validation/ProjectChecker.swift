import Foundation

/// Validates a project against the rules the generated architecture follows.
///
/// Every rule runs off the `ProjectModel` the scan already produced, so a
/// finding here cannot contradict what `inspect` printed or what `document`
/// wrote. Nothing is re-read and nothing is compiled.
///
/// The severities are deliberately lopsided. Only two rules produce errors,
/// because only two of them rest on something structural with a definite
/// consequence. Calling a naming convention an error would make the command
/// easy to dismiss, and a checker nobody trusts is worse than no checker.
public struct ProjectChecker {

    /// Attributes that cannot work without their framework, and the import
    /// they need. A project that does not compile is exactly when this is
    /// worth catching, and exactly when a compiler cannot tell you.
    private static let requiredImports: [(attribute: String, module: String)] = [
        (attribute: "Model", module: "SwiftData"),
    ]

    /// Frameworks a screen has no business owning directly.
    private static let infrastructureModules: Set<String> = [
        "SwiftData", "CoreData", "Network",
    ]

    public let model: ProjectModel

    /// Production code only, for the same reason architecture detection uses
    /// it: a test double is an imitation on purpose.
    private let analysis: SourceAnalysis
    private let typeGraph: TypeGraph
    /// The join of the import and type graphs, built once. Several rules below
    /// ask it questions, and rebuilding it per question would turn one pass
    /// over the project into a dozen.
    private let dependencies: DependencyGraph
    private let nodesByName: [String: TypeNode]
    private let declaredProtocols: Set<String>

    public init(model: ProjectModel) {
        self.model = model
        analysis = model.analysis.excludingTests()
        typeGraph = model.typeGraph
        dependencies = model.dependencyGraph()
        nodesByName = Dictionary(
            model.typeGraph.nodes.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first }
        )
        declaredProtocols = Set(
            model.analysis.excludingTests().declaredTypes
                .filter { $0.kind == .protocolType }
                .map(\.name)
        )
    }

    public func check() -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        diagnostics += missingImports()
        diagnostics += unsharedSchemes()
        diagnostics += viewModelIsolation()
        diagnostics += viewModelObservability()
        diagnostics += viewModelObservationConsistency()
        diagnostics += viewsOwningInfrastructure()
        diagnostics += repositoriesWithoutProtocols()
        diagnostics += featureLayering()
        diagnostics += testing()

        // Read from the relationship graphs rather than from declarations.
        diagnostics += viewsReachingInfrastructure()
        diagnostics += viewsConstructingInfrastructure()
        diagnostics += concreteRepositoryDependencies()
        diagnostics += sharedCodeDependingOnFeatures()
        diagnostics += featureCycles()
        diagnostics += layerInversions()

        return diagnostics.ordered()
    }

    // MARK: - Relationship rules

    /// A screen that refers to a networking client or a persistence type with
    /// nothing in between.
    ///
    /// Repositories are deliberately not included. Passing one through a
    /// view's initializer to build its view model is a real pattern and not a
    /// boundary being crossed, and a rule that fired on it would be switched
    /// off within a week.
    private func viewsReachingInfrastructure() -> [Diagnostic] {
        let rules: [(role: TypeRole, id: String, subject: String)] = [
            (.client, "view-reaches-networking", "a networking client"),
            (.persistence, "view-reaches-persistence", "a persistence type"),
        ]

        return rules.flatMap { rule -> [Diagnostic] in
            grouped(references(fromViewsTo: [rule.role])).map { subject, references in
                diagnostic(
                    rule: rule.id,
                    references: references,
                    message: "\(subject.name) refers to \(rule.subject), "
                        + "\(Self.list(references.map(\.to))), directly.",
                    location: subject.location
                )
            }
        }
    }

    /// A screen building infrastructure that the project injects elsewhere.
    ///
    /// The second half is what makes this a rule rather than an opinion: if
    /// nothing in the project ever takes this type as an initializer
    /// parameter, nobody has decided it is a dependency and a view
    /// constructing one is not opting out of anything.
    private func viewsConstructingInfrastructure() -> [Diagnostic] {
        let injected = Set(
            typeGraph.references.filter { $0.kind == .initializerDependency }.map(\.to)
        )
        guard !injected.isEmpty else { return [] }

        let offending = references(fromViewsTo: [.client, .repository, .persistence, .service])
            .filter { $0.kind == .constructorReference && injected.contains($0.to) }

        return grouped(offending).map { subject, references in
            diagnostic(
                rule: "view-constructs-infrastructure",
                references: references,
                message: "\(subject.name) constructs \(Self.list(references.map(\.to))), "
                    + "which the project injects elsewhere.",
                location: subject.location
            )
        }
    }

    /// Something depending on a repository's concrete type rather than the
    /// protocol in front of it.
    ///
    /// Only where the project has actually established the boundary — most of
    /// its repositories sitting behind a protocol — because otherwise this is
    /// Keel's opinion about how repositories should be written rather than a
    /// report of the project departing from its own habit.
    private func concreteRepositoryDependencies() -> [Diagnostic] {
        let repositories = typeGraph.nodes.filter { $0.role == .repository && $0.kind != .protocolType }
        guard repositories.count > 1 else { return [] }

        let abstracted = Set(
            repositories
                .filter { repository in
                    typeGraph.references.contains {
                        $0.from == repository.name && $0.kind == .conformance
                            && declaredProtocols.contains($0.to)
                    }
                }
                .map(\.name)
        )
        // Established means most of them, not one of them.
        guard abstracted.count * 2 > repositories.count else { return [] }

        let offending = typeGraph.references.filter { reference in
            guard abstracted.contains(reference.to), reference.kind.isStructural else { return false }
            // The composition root knowing its concrete types is its job.
            guard reference.from != model.architecture.compositionRoot else { return false }
            // A repository's own protocol conformance is the boundary, not a
            // breach of it.
            return !declaredProtocols.contains(reference.from)
        }

        return grouped(offending).map { subject, references in
            diagnostic(
                rule: "concrete-repository-dependency",
                references: references,
                message: "\(subject.name) depends on \(Self.list(references.map(\.to))) "
                    + "rather than the protocol in front of it.",
                location: subject.location,
                // The boundary is established by what the project mostly does,
                // and "mostly" is never certainty.
                severity: .warning
            )
        }
    }

    /// Shared code depending on a feature, from the unified dependency graph.
    private func sharedCodeDependingOnFeatures() -> [Diagnostic] {
        dependencies.violations
            .filter { $0.rule == .sharedCodeDependsOnFeature }
            .map { violation in
                Diagnostic(
                    rule: "shared-code-depends-on-feature",
                    severity: .warning,
                    message: "\(violation.from) depends on the \(violation.to) feature.",
                    location: violation.evidence.first?.location,
                    detail: CheckRules.rule("shared-code-depends-on-feature")?.explanation,
                    evidence: violation.evidence.map {
                        .init(location: $0.location, statement: $0.describedInFull)
                    },
                    path: [violation.from, violation.to]
                )
            }
    }

    /// Features that depend on each other in a loop.
    private func featureCycles() -> [Diagnostic] {
        dependencies.cycles(at: .feature).map { cycle in
            let edges = dependencies.edges(at: .feature).filter { edge in
                zip(cycle, cycle.dropFirst()).contains { $0 == edge.from && $1 == edge.to }
            }
            return Diagnostic(
                rule: "feature-dependency-cycle",
                severity: .warning,
                message: "\(cycle.joined(separator: " → ")) is a dependency cycle.",
                location: edges.first?.evidence.first?.location,
                detail: CheckRules.rule("feature-dependency-cycle")?.explanation,
                evidence: edges.compactMap { edge in
                    edge.evidence.first.map {
                        .init(location: $0.location, statement: "\(edge.from) → \(edge.to): \($0.describedInFull)")
                    }
                },
                path: cycle
            )
        }
    }

    /// A dependency pointing back out through the project's own layers.
    private func layerInversions() -> [Diagnostic] {
        guard model.architecture.layerBoundaries.value == .crossed else { return [] }

        return model.architecture.layerBoundaries.evidence
            .filter { $0.stance == .supporting }
            .map { item in
                Diagnostic(
                    rule: "layer-inversion",
                    severity: .warning,
                    message: item.statement,
                    location: item.locations.first,
                    detail: CheckRules.rule("layer-inversion")?.explanation,
                    evidence: item.locations.map { .init(location: $0, statement: "type reference") }
                )
            }
    }

    // MARK: - Relationship helpers

    /// Structural references from a screen to a type in one of the given roles.
    ///
    /// Body references are left out: `Logger.shared` inside one method is a
    /// mention, and a rule that treated it like a held dependency would be
    /// wrong often enough to be ignored. Construction is the exception and is
    /// handled by its own rule.
    private func references(fromViewsTo roles: Set<TypeRole>) -> [TypeReference] {
        typeGraph.references.filter { reference in
            guard let from = node(reference.from), let to = node(reference.to) else { return false }
            guard from.role == .view || from.role == .viewController else { return false }
            guard roles.contains(to.role) else { return false }
            return reference.kind.isStructural || reference.kind == .constructorReference
        }
    }

    /// One diagnostic per referring type, rather than one per reference.
    private func grouped(_ references: [TypeReference]) -> [(TypeNode, [TypeReference])] {
        var bySubject: [String: [TypeReference]] = [:]
        for reference in references {
            bySubject[reference.from, default: []].append(reference)
        }
        return bySubject
            .compactMap { name, references in
                node(name).map { ($0, references.sorted { ($0.file, $0.line) < ($1.file, $1.line) }) }
            }
            .sorted { $0.0.name < $1.0.name }
    }

    /// Builds the finding, deriving severity from how firmly it is established.
    ///
    /// The severity model in one place: an error needs the relationship *and*
    /// both of its ends to come from the code. A view is a view because it
    /// conforms to SwiftUI's `View`; a client is a client because somebody
    /// called it one — and the moment a name is load-bearing, this is a
    /// warning however obvious it looks.
    private func diagnostic(
        rule: String,
        references: [TypeReference],
        message: String,
        location: String,
        severity: Diagnostic.Severity? = nil
    ) -> Diagnostic {
        let established = references.allSatisfy { reference in
            reference.support == .observed
                && node(reference.from)?.roleSupport == .observed
                && node(reference.to)?.roleSupport == .observed
        }

        return Diagnostic(
            rule: rule,
            severity: severity ?? (established ? .error : .warning),
            message: message,
            location: location,
            detail: CheckRules.rule(rule)?.explanation,
            evidence: references.map {
                .init(location: $0.location, statement: "\($0.kind.displayName): \($0.to)")
            }
        )
    }

    private func node(_ name: String) -> TypeNode? {
        nodesByName[name]
    }

    /// A view model observing differently from the rest of the project.
    ///
    /// The convention is read as *dominance*, not unanimity. Asking whether
    /// the whole project agrees would be self-defeating: the first type to
    /// depart makes the project "mixed", and the rule would fall silent
    /// exactly when it had something to say.
    private func viewModelObservationConsistency() -> [Diagnostic] {
        let macro = analysis.types(withAttribute: "Observable")
        let objects = analysis.types(conformingTo: "ObservableObject")
            .filter { !$0.hasAttribute("Observable") }

        let total = macro.count + objects.count
        // Too few to have a habit, let alone a convention to depart from.
        guard total >= Self.observationConventionMinimum else { return [] }

        let macroDominates = macro.count * 4 > total * 3
        let objectsDominate = objects.count * 4 > total * 3
        guard macroDominates || objectsDominate else { return [] }

        let expected = macroDominates ? "@Observable" : "ObservableObject"
        let departures = macroDominates ? objects : macro

        return viewModels
            .filter { type in departures.contains { $0.name == type.name && $0.path == type.path } }
            .map { type in
                Diagnostic(
                    rule: "view-model-observation-inconsistent",
                    severity: .warning,
                    message: "\(type.name) is \(macroDominates ? "an ObservableObject" : "@Observable"), "
                        + "but this project observes with \(expected).",
                    location: "\(type.path):\(type.line)",
                    detail: CheckRules.rule("view-model-observation-inconsistent")?.explanation,
                    evidence: [
                        .init(
                            location: "\(type.path):\(type.line)",
                            statement: "\(macroDominates ? "ObservableObject" : "@Observable")"
                                + " — \(macroDominates ? macro.count : objects.count) of \(total) "
                                + "observable types here use \(expected)"
                        )
                    ]
                )
            }
    }

    /// How many observable types a project needs before one of them can be
    /// called a departure.
    ///
    /// Three types agreeing is a coincidence; four is a habit worth naming.
    private static let observationConventionMinimum = 4

    // MARK: - Errors

    /// An attribute used without the framework that defines it.
    ///
    /// Structural and certain: the file says `@Model` and does not say
    /// `import SwiftData`, so it cannot build. This is the kind of thing a
    /// compiler would catch — on a project that compiles.
    private func missingImports() -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []

        for file in analysis.files {
            let imports = Set(file.importedModules)
            for requirement in Self.requiredImports {
                let users = file.types.filter { $0.hasAttribute(requirement.attribute) }
                guard !users.isEmpty, !imports.contains(requirement.module) else { continue }

                for type in users {
                    diagnostics.append(
                        Diagnostic(
                            rule: "missing-import",
                            severity: .error,
                            message: "\(type.name) is @\(requirement.attribute) but the file does not import \(requirement.module).",
                            location: "\(type.path):\(type.line)",
                            detail: "Add `import \(requirement.module)` to this file."
                        )
                    )
                }
            }
        }
        return diagnostics
    }

    /// A scheme that lives under `xcuserdata` is gitignored.
    ///
    /// Structural and certain: CI and a fresh clone cannot see it, so they
    /// cannot build it.
    private func unsharedSchemes() -> [Diagnostic] {
        model.schemes.filter { !$0.isShared }.map { scheme in
            Diagnostic(
                rule: "scheme-not-shared",
                severity: .error,
                message: "The \(scheme.name) scheme is not shared.",
                location: nil,
                detail: """
                    It lives under xcuserdata, which is gitignored, so CI and a \
                    fresh clone cannot build it. Xcode: Product › Scheme › Manage \
                    Schemes, then tick Shared.
                    """
            )
        }
    }

    // MARK: - Warnings

    /// A view model that is not `@MainActor`.
    ///
    /// A warning rather than an error because isolation can arrive from
    /// somewhere syntax cannot follow: a `@MainActor` protocol it conforms to,
    /// an enclosing type, or a module-wide default.
    private func viewModelIsolation() -> [Diagnostic] {
        viewModels
            .filter { !$0.hasAttribute("MainActor") }
            .map { type in
                Diagnostic(
                    rule: "view-model-not-main-actor",
                    severity: .warning,
                    message: "\(type.name) is not marked @MainActor.",
                    location: "\(type.path):\(type.line)",
                    detail: """
                        A type driving a view should be isolated to the main actor. \
                        Keel may be wrong here: isolation inherited from a protocol, \
                        an enclosing type or a module default is not visible to syntax.
                        """
                )
            }
    }

    /// A view model nothing can observe.
    private func viewModelObservability() -> [Diagnostic] {
        viewModels
            .filter { !$0.hasAttribute("Observable") && !$0.conforms(to: "ObservableObject") }
            .map { type in
                Diagnostic(
                    rule: "view-model-not-observable",
                    severity: .warning,
                    message: "\(type.name) is neither @Observable nor an ObservableObject.",
                    location: "\(type.path):\(type.line)",
                    detail: """
                        A view reading this will not redraw when it changes. If state \
                        lives somewhere else entirely, the name is what is misleading.
                        """
                )
            }
    }

    /// A file that declares a screen and imports infrastructure.
    ///
    /// Judged per file rather than per type: the import is a property of the
    /// file, and Keel cannot see which declaration uses it.
    private func viewsOwningInfrastructure() -> [Diagnostic] {
        guard model.source.importsSwiftUI else { return [] }

        return analysis.files.flatMap { file -> [Diagnostic] in
            let views = file.types.filter { $0.conforms(to: "View") }
            guard !views.isEmpty else { return [] }

            return Set(file.importedModules)
                .intersection(Self.infrastructureModules)
                .sorted()
                .map { module in
                    Diagnostic(
                        rule: "view-imports-infrastructure",
                        severity: .warning,
                        message: "A SwiftUI view is declared in a file that imports \(module).",
                        location: file.path,
                        detail: """
                            Screens that reach for storage or the network directly are the \
                            hardest ones to test. Keel cannot see which type in the file \
                            uses the import, only that both are here.
                            """
                    )
                }
        }
    }

    /// A repository with no abstraction in front of it.
    private func repositoriesWithoutProtocols() -> [Diagnostic] {
        let declaredProtocols = Set(
            analysis.declaredTypes.filter { $0.kind == .protocolType }.map(\.name)
        )

        return analysis.types(namedWithSuffix: "Repository")
            .filter { $0.kind != .protocolType }
            .filter { type in
                // A conformance added in an extension counts, so the whole
                // analysis is searched rather than this declaration alone.
                let conformances = analysis.types
                    .filter { $0.name == type.name }
                    .flatMap(\.inheritedTypes)
                return !conformances.contains(where: declaredProtocols.contains)
            }
            .map { type in
                Diagnostic(
                    rule: "repository-without-protocol",
                    severity: .warning,
                    message: "\(type.name) does not conform to a protocol the project declares.",
                    location: "\(type.path):\(type.line)",
                    detail: """
                        Without an abstraction, everything depending on this is pinned to \
                        the concrete type and cannot be given a stub in a test.
                        """
                )
            }
    }

    /// Features divided differently from each other.
    ///
    /// The inconsistency, not the layout: Keel has no opinion about whether a
    /// feature should have a `Domain` folder, only about four features
    /// disagreeing.
    private func featureLayering() -> [Diagnostic] {
        guard model.architecture.featureLayering.value == .inconsistent else { return [] }

        return [
            Diagnostic(
                rule: "inconsistent-feature-layers",
                severity: .warning,
                message: "Feature folders are not divided the same way as each other.",
                location: nil,
                detail: model.architecture.featureLayering.evidence.map(\.statement).joined(separator: " ")
            )
        ]
    }

    private func testing() -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []

        if model.testTargets.isEmpty {
            diagnostics.append(
                Diagnostic(
                    rule: "no-test-target",
                    severity: .warning,
                    message: "The project has no test target.",
                    location: nil,
                    detail: "Nothing here can be verified automatically."
                )
            )
        } else if !model.source.usesSwiftTesting && !model.source.usesXCTest {
            // A test bundle that imports no testing framework is a contradiction
            // worth surfacing, though the bundle may simply be empty.
            diagnostics.append(
                Diagnostic(
                    rule: "test-target-without-framework",
                    severity: .warning,
                    message: "There is a test target, but no file imports Swift Testing or XCTest.",
                    location: nil,
                    detail: "The target may be empty, or its tests may live somewhere Keel did not look."
                )
            )
        }

        return diagnostics
    }

    // MARK: - Helpers

    private var viewModels: [TypeDeclaration] {
        analysis.types(namedWithSuffix: "ViewModel")
    }

    /// "a, b and c" — matching the prose everywhere else.
    static func list(_ items: [String]) -> String {
        let unique = Array(Set(items)).sorted()
        guard let last = unique.last else { return "" }
        guard unique.count > 1 else { return last }
        return unique.dropLast().joined(separator: ", ") + " and " + last
    }
}
