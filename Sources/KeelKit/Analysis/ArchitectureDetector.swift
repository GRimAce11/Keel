import Foundation

/// Works out how a project is built, from its layout, its declarations and
/// what its types do to each other.
///
/// Each rule is written as "what would have to be true": a project is not
/// MVVM because it resembles the diagram, it is MVVM because it declares views
/// *and* types that hold their state *and* the views actually reach those
/// types. Every rule records what it read, so a reader can reject the
/// conclusion and still trust the counts.
///
/// The three kinds of evidence are kept apart all the way through. A folder
/// called `Features` and a type called `ArticleViewModel` are conventions; an
/// `@Observable` attribute is a declaration; `ArticleListView` holding an
/// `ArticleListViewModel` is a relationship. They are not interchangeable, and
/// `Finding` derives its support from which of them a rule managed to find —
/// so no rule can quietly promote a naming habit to a fact.
struct ArchitectureDetector {

    /// Top-level folder names that mean a layer rather than a feature.
    private static let layerNames: Set<String> = [
        "data", "domain", "presentation", "ui", "view", "views",
        "model", "models", "viewmodel", "viewmodels",
    ]

    /// Which layers may depend on which, for the layer names Keel recognises.
    ///
    /// Not a linear stack, which is the mistake worth not making: `Domain` is
    /// the *innermost* layer, and both `Presentation` and `Data` depend on it.
    /// A repository returning a domain model is the arrangement working, not a
    /// boundary being crossed. What must not happen is the arrow pointing at
    /// presentation, or out of domain at all.
    ///
    /// `Presentation → Data` is allowed here even though it skips a layer:
    /// it is a shortcut rather than an inversion, and `presentationFlow`
    /// already reports it in the terms that make it worth knowing.
    ///
    /// Only these names are placed. A project dividing its features into
    /// `Engine` and `Adapters` gets `undetermined` rather than an invented
    /// ranking — Keel has no way to know which of those sits inside the other.
    private static let layerDependencies: [String: Set<String>] = [
        "presentation": ["domain", "data"],
        "ui": ["domain", "data"],
        "view": ["domain", "data"],
        "views": ["domain", "data"],
        "data": ["domain"],
        "domain": [],
        "model": [],
        "models": [],
    ]

    /// Types that bridge SwiftUI and UIKit, by conformance or by superclass.
    private static let bridgingTypes: Set<String> = [
        "UIViewRepresentable", "UIViewControllerRepresentable",
        "NSViewRepresentable", "NSViewControllerRepresentable",
        "UIHostingController", "UIHostingConfiguration",
    ]

    let modules: [Module]
    let features: [Feature]
    /// Parsed source with tests already removed — see
    /// `SourceAnalysis.excludingTests()`.
    let analysis: SourceAnalysis
    /// What the project's types do to each other. The whole reason this
    /// detector can say more than "types with these names exist".
    let typeGraph: TypeGraph
    /// The same relationships aggregated to features, modules and layers.
    let dependencies: DependencyGraph

    func detect() -> Architecture {
        let wiring = self.wiring()
        return Architecture(
            presentation: presentation(),
            uiCoexistence: uiCoexistence(),
            observation: observation(),
            concurrency: concurrency(),
            persistence: persistence(),
            organisation: organisation(),
            featureLayering: featureLayering(),
            presentationFlow: presentationFlow(),
            featureIsolation: featureIsolation(),
            layerBoundaries: layerBoundaries(),
            dependencyDirection: dependencyDirection(),
            persistenceAccess: access(to: persistenceTypes(), named: "persistence"),
            networkingAccess: access(to: networkingTypes(), named: "networking"),
            wiring: wiring.finding,
            compositionRoot: wiring.root
        )
    }

    // MARK: - Presentation

    /// Whether the project is MVVM, and on what basis.
    ///
    /// The plan for this phase is explicit that counting `*ViewModel` is not
    /// detection, so the four things that could each be true are reported
    /// separately: that the names exist, that the types observe, that views
    /// reach them, and how many. A project where all four hold is MVVM from
    /// relationships. A project where only the first holds is a project with a
    /// naming habit, and says so.
    private func presentation() -> Finding<PresentationPattern> {
        // `View` on its own would match any protocol of that name, so SwiftUI
        // has to actually be imported for a conformance to mean a screen.
        let views = filesImporting("SwiftUI") > 0
            ? analysis.types(conformingTo: "View")
            : []
        let controllers = viewControllers()

        switch (!views.isEmpty, !controllers.isEmpty) {
        case (false, false):
            return Finding(
                value: .unknown,
                evidence: [.init("No SwiftUI view and no view controller declared.", basis: .observedFact)]
            )

        case (true, true):
            return Finding(
                value: .mixed,
                evidence: [
                    .init(Prose.count(views.count, "SwiftUI view") + " declared.",
                          basis: .observedFact, locations: locations(views)),
                    .init(Prose.count(controllers.count, "view controller") + " declared.",
                          basis: .observedFact, locations: controllers.map(\.location)),
                ]
            )

        case (false, true):
            return Finding(
                value: .mvc,
                evidence: [
                    .init(Prose.count(controllers.count, "view controller") + " declared.",
                          basis: .observedFact, locations: controllers.map(\.location)),
                    .init("No type conforms to SwiftUI's View.", basis: .observedFact),
                ]
            )

        case (true, false):
            return swiftUIPresentation(views: views)
        }
    }

    /// SwiftUI is in use; the question is whether screen state lives outside
    /// the view, and whether the views actually use it.
    private func swiftUIPresentation(views: [TypeDeclaration]) -> Finding<PresentationPattern> {
        // The suffix, deliberately, and not `typeGraph.types(inRole: .viewModel)`.
        // This rule's whole job is to separate what the project *names* from
        // what it *does*, and the evidence below says "named with a ViewModel
        // suffix" in so many words. Asking the graph would widen it to
        // presenters and make that sentence false.
        let viewModels = analysis.types(namedWithSuffix: "ViewModel")
        // Context, not support: that SwiftUI views exist settles the SwiftUI
        // half of the question and says nothing about where their state lives,
        // which is the half this finding is about.
        var evidence: [ArchitectureEvidence] = [
            .context(Prose.count(views.count, "SwiftUI view") + " declared.",
                     basis: .observedFact, locations: locations(views)),
        ]

        guard !viewModels.isEmpty else {
            evidence.append(
                .init("No type is named with a ViewModel suffix.", basis: .namingConvention)
            )
            return Finding(value: .modelView, evidence: evidence)
        }

        // 1. The names exist. A convention, and only that.
        evidence.append(
            .init(Prose.count(viewModels.count, "type") + " named with a ViewModel suffix.",
                  basis: .namingConvention, locations: locations(viewModels))
        )

        // 2. Do they observe? A view model that is neither `@Observable` nor an
        // `ObservableObject` cannot drive a SwiftUI view, whatever it is called.
        let observing = viewModels.filter {
            $0.hasAttribute("Observable") || $0.conforms(to: "ObservableObject")
        }
        if observing.isEmpty {
            evidence.append(
                .qualifying("None of them is @Observable or an ObservableObject.", basis: .observedFact)
            )
        } else {
            evidence.append(
                .init("\(observing.count) of those \(observing.count == 1 ? "is" : "are") "
                      + "@Observable or an ObservableObject.",
                      basis: .observedFact, locations: locations(observing))
            )
        }

        // 3. Do the views reach them? The question the other three cannot
        // answer, and the one that separates a design from a folder of files.
        let used = viewsReaching(role: .viewModel)
        if used.isEmpty {
            evidence.append(
                .qualifying("No view refers to one, so the naming is the only link between them.",
                            basis: .structuralRelationship)
            )
            return Finding(value: .mvvm, evidence: evidence)
        }

        let viewsUsingOne = Set(used.map(\.from)).count
        evidence.append(
            .init("\(Prose.count(viewsUsingOne, "view")) \(viewsUsingOne == 1 ? "refers" : "refer") to one, "
                  + "in \(Prose.count(used.count, "place")).",
                  basis: .structuralRelationship,
                  locations: Self.sortedLocations(used))
        )
        return Finding(value: .mvvm, evidence: evidence)
    }

    /// View controllers, from the one place that decides what a type is for.
    ///
    /// This used to have its own rule, which agreed with the type graph's by
    /// luck rather than by construction. Two answers to "is this a view
    /// controller" is one more than a report can survive.
    private func viewControllers() -> [TypeNode] {
        typeGraph.types(inRole: .viewController)
    }

    // MARK: - UI coexistence

    /// Where SwiftUI and UIKit meet, when a project has both.
    private func uiCoexistence() -> Finding<UICoexistence> {
        let swiftUI = filesImporting("SwiftUI")
        let uiKit = filesImporting("UIKit")

        guard swiftUI > 0 || uiKit > 0 else {
            return Finding(
                value: .unknown,
                evidence: [.init("Neither SwiftUI nor UIKit is imported.", basis: .observedFact)]
            )
        }

        let counts: [ArchitectureEvidence] = [
            swiftUI > 0 ? .init("SwiftUI imported by \(Prose.count(swiftUI, "file")).", basis: .observedFact) : nil,
            uiKit > 0 ? .init("UIKit imported by \(Prose.count(uiKit, "file")).", basis: .observedFact) : nil,
        ].compactMap { $0 }

        guard swiftUI > 0, uiKit > 0 else {
            return Finding(value: swiftUI > 0 ? .swiftUIOnly : .uiKitOnly, evidence: counts)
        }

        // A representable or a hosting controller is the seam, and naming it
        // is more use than saying both frameworks are present.
        let bridges = analysis.declaredTypes.filter { type in
            type.inheritedTypes.contains { Self.bridgingTypes.contains(TypeName.base(of: $0)) }
        }

        guard !bridges.isEmpty else {
            return Finding(
                value: .sideBySide,
                evidence: counts + [
                    .qualifying("No type bridges the two — no representable, no hosting controller.",
                                basis: .observedFact)
                ]
            )
        }

        return Finding(
            value: .bridged,
            evidence: counts + [
                .init("\(Prose.count(bridges.count, "type")) \(bridges.count == 1 ? "bridges" : "bridge") "
                      + "the two: \(Prose.list(bridges.map(\.name).sorted())).",
                      basis: .observedFact, locations: locations(bridges))
            ]
        )
    }

    // MARK: - Presentation flow

    /// What a screen actually holds.
    ///
    /// The relationship answer to the question the MVVM verdict only gestures
    /// at. A project can declare a hundred view models and still have every
    /// view holding its own repository.
    private func presentationFlow() -> Finding<PresentationFlow> {
        let toViewModels = viewsReaching(role: .viewModel)
        let toData = viewsReaching(roles: [.repository, .client, .persistence])

        guard !toViewModels.isEmpty || !toData.isEmpty else {
            return Finding(
                value: .unknown,
                evidence: [
                    .init("No view refers to a view model, a repository or a client.",
                          basis: .structuralRelationship)
                ]
            )
        }

        var evidence: [ArchitectureEvidence] = []
        if !toViewModels.isEmpty {
            evidence.append(
                .init("\(Prose.count(toViewModels.count, "reference")) from a view to a view model.",
                      basis: .structuralRelationship, locations: Self.sortedLocations(toViewModels))
            )
        }
        if !toData.isEmpty {
            evidence.append(
                .init("\(Prose.count(toData.count, "reference")) from a view straight to a repository, "
                      + "client or persistence type.",
                      basis: .structuralRelationship, locations: Self.sortedLocations(toData))
            )
        }

        switch (!toViewModels.isEmpty, !toData.isEmpty) {
        case (true, true): return Finding(value: .mixed, evidence: evidence)
        case (true, false): return Finding(value: .throughViewModels, evidence: evidence)
        case (false, true): return Finding(value: .viewsReachData, evidence: evidence)
        case (false, false): return Finding(value: .unknown, evidence: evidence)
        }
    }

    // MARK: - Feature isolation

    private func featureIsolation() -> Finding<FeatureIsolation> {
        guard features.count > 1 else {
            return Finding(
                value: .unknown,
                evidence: [
                    .init(features.isEmpty
                          ? "The project is not organised into feature folders."
                          : "Only one feature folder, so nothing can cross between them.",
                          basis: .namingConvention)
                ]
            )
        }

        let edges = dependencies.edges(at: .feature)
        guard !edges.isEmpty else {
            return Finding(
                value: .isolated,
                evidence: [
                    .init("No type in any of the \(features.count) features refers to a type in another.",
                          basis: .structuralRelationship)
                ]
            )
        }

        // Reported, not judged. Nothing in a project layout establishes that
        // one feature may not use another.
        return Finding(
            value: .coupled,
            evidence: edges.map { edge in
                .init("\(edge.from) depends on \(edge.to) "
                      + "(\(Prose.count(edge.evidence.count, "reference"))).",
                      basis: .structuralRelationship,
                      locations: edge.evidence.map(\.location))
            }
        )
    }

    // MARK: - Layer boundaries

    /// Whether dependencies run the way the layer folders imply.
    ///
    /// Only folders Keel can order are read. A project dividing its features
    /// into `Engine` and `Adapters` gets `undetermined`, because nothing says
    /// which of those sits above the other and inventing a ranking would turn
    /// an unfamiliar layout into a false finding.
    private func layerBoundaries() -> Finding<LayerBoundaries> {
        let edges = dependencies.edges(at: .layer)
        let placed = edges.filter {
            Self.layerDependencies[$0.from.lowercased()] != nil
                && Self.layerDependencies[$0.to.lowercased()] != nil
        }

        guard !placed.isEmpty else {
            return Finding(
                value: .unknown,
                evidence: [
                    .init(edges.isEmpty
                          ? "No dependency crosses between layer folders."
                          : "The layer folders here are not ones Keel can place: "
                            + "\(Prose.list(Set(edges.flatMap { [$0.from, $0.to] }).sorted())).",
                          basis: .namingConvention)
                ]
            )
        }

        let crossed = placed.filter { edge in
            !(Self.layerDependencies[edge.from.lowercased()] ?? []).contains(edge.to.lowercased())
        }

        guard !crossed.isEmpty else {
            return Finding(
                value: .respected,
                evidence: placed.map { edge in
                    .init("\(edge.from) → \(edge.to) (\(Prose.count(edge.evidence.count, "reference"))).",
                          basis: .structuralRelationship, locations: edge.evidence.map(\.location))
                }
            )
        }

        return Finding(
            value: .crossed,
            evidence: crossed.map { edge in
                .init("\(edge.from) → \(edge.to) points back outwards "
                      + "(\(Prose.count(edge.evidence.count, "reference"))).",
                      basis: .structuralRelationship, locations: edge.evidence.map(\.location))
            } + placed
                .filter { edge in
                    !crossed.contains { $0.from == edge.from && $0.to == edge.to }
                }
                .map { edge in
                    .context("\(edge.from) → \(edge.to) runs the way it should "
                             + "(\(Prose.count(edge.evidence.count, "reference"))).",
                             basis: .structuralRelationship)
                }
        )
    }

    // MARK: - Dependency direction

    /// Which way dependencies run between shared code and features.
    private func dependencyDirection() -> Finding<DependencyDirection> {
        let shared = Set(modules.filter { $0.role == .core || $0.role == .shared }.map(\.name))

        guard !shared.isEmpty, !features.isEmpty else {
            return Finding(
                value: .unknown,
                evidence: [
                    .init("The project has no folder that is shared code and features both.",
                          basis: .namingConvention)
                ]
            )
        }

        let wrongWay = dependencies.violations.filter { $0.rule == .sharedCodeDependsOnFeature }
        guard wrongWay.isEmpty else {
            return Finding(
                value: .sharedOnFeatures,
                evidence: wrongWay.map { violation in
                    .init("\(violation.from) depends on the \(violation.to) feature.",
                          basis: .structuralRelationship,
                          locations: violation.evidence.map(\.location))
                }
            )
        }

        let inward = dependencies.edges(at: .module).filter { shared.contains($0.to) }
        return Finding(
            value: .featuresOnShared,
            evidence: [
                .init("Nothing in \(Prose.list(shared.sorted())) depends on a feature.",
                      basis: .structuralRelationship)
            ] + inward.map { edge in
                .init("\(edge.from) → \(edge.to) (\(Prose.count(edge.evidence.count, "dependency", plural: "dependencies"))).",
                      basis: .structuralRelationship, locations: edge.evidence.map(\.location))
            }
        )
    }

    // MARK: - Reach

    /// How far up the stack a set of types is reached for.
    ///
    /// The same question for persistence and for networking: is it behind the
    /// data layer, or wired into the screens. Answered from who refers to it,
    /// never from where the files sit.
    private func access(to targets: [TypeNode], named subject: String) -> Finding<DataAccess> {
        guard !targets.isEmpty else {
            return Finding(
                value: .unknown,
                evidence: [.init("No \(subject) type found in the project.", basis: .observedFact)]
            )
        }

        let names = Set(targets.map(\.name))
        let roles = Dictionary(
            typeGraph.nodes.map { ($0.name, $0.role) }, uniquingKeysWith: { first, _ in first }
        )
        let inbound = typeGraph.references.filter { names.contains($0.to) && !names.contains($0.from) }

        let byViews = inbound.filter { roles[$0.from] == .view || roles[$0.from] == .viewController }
        let byViewModels = inbound.filter { roles[$0.from] == .viewModel }
        let byOthers = inbound.filter {
            let role = roles[$0.from]
            return role != .view && role != .viewController && role != .viewModel
        }

        var evidence: [ArchitectureEvidence] = [
            .context(Prose.count(targets.count, "\(subject) type") + ": "
                     + (targets.count > 4
                        ? targets.map(\.name).sorted().prefix(4).joined(separator: ", ") + " and others."
                        : Prose.list(targets.map(\.name).sorted()) + "."),
                     basis: .observedFact, locations: targets.map(\.location))
        ]
        for (group, label) in [(byViews, "view"), (byViewModels, "view model"), (byOthers, "other type")]
        where !group.isEmpty {
            evidence.append(
                .init("Reached by \(Prose.count(Set(group.map(\.from)).count, label)).",
                      basis: .structuralRelationship, locations: Self.sortedLocations(group))
            )
        }

        switch (!byViews.isEmpty, !byViewModels.isEmpty || !byOthers.isEmpty) {
        case (true, true): return Finding(value: .mixed, evidence: evidence)
        case (true, false): return Finding(value: .views, evidence: evidence)
        case (false, true):
            return Finding(value: byViewModels.isEmpty ? .isolated : .viewModels, evidence: evidence)
        case (false, false):
            evidence.append(
                .init("Nothing else in the project refers to \(inbound.isEmpty ? "them" : "it").",
                      basis: .structuralRelationship)
            )
            return Finding(value: .isolated, evidence: evidence)
        }
    }

    /// Types that are the persistence layer, by attribute or by role.
    private func persistenceTypes() -> [TypeNode] {
        typeGraph.nodes.filter { $0.role == .persistence }
    }

    private func networkingTypes() -> [TypeNode] {
        typeGraph.nodes.filter { $0.role == .client }
    }

    // MARK: - Organisation

    private func organisation() -> Finding<Organisation> {
        guard !modules.isEmpty else {
            return Finding(
                value: .unknown,
                evidence: [.init("No top-level source folders to read a layout from.", basis: .namingConvention)]
            )
        }

        if !features.isEmpty {
            let containers = modules.filter { $0.role == .features }.map(\.name)
            var evidence: [ArchitectureEvidence] = [
                .init(Prose.count(features.count, "feature folder") + " found.", basis: .namingConvention)
            ]
            if !containers.isEmpty {
                evidence.append(.init("Held under \(Prose.list(containers)).", basis: .namingConvention))
            }
            return Finding(value: .featureBased, evidence: evidence)
        }

        let layers = modules.filter { Self.layerNames.contains($0.name.lowercased()) }
        if layers.count > 1 {
            return Finding(
                value: .layered,
                evidence: [.init("Top level divided into \(Prose.list(layers.map(\.name))).",
                                 basis: .namingConvention)]
            )
        }

        let named = modules.filter { $0.role != .other }
        if named.count > 1 {
            return Finding(
                value: .grouped,
                evidence: [.init("Top level divided into \(Prose.list(named.map(\.name))).",
                                 basis: .namingConvention)]
            )
        }

        return Finding(
            value: .unknown,
            evidence: [
                .init("\(Prose.count(modules.count, "top-level folder")), not divided by feature, "
                      + "by layer or by role.", basis: .namingConvention)
            ]
        )
    }

    // MARK: - Feature layers

    private func featureLayering() -> Finding<FeatureLayering> {
        guard !features.isEmpty else {
            return Finding(
                value: .unknown,
                evidence: [.init("The project is not organised into feature folders.", basis: .namingConvention)]
            )
        }

        let divided = features.filter { !$0.layers.isEmpty }

        guard !divided.isEmpty else {
            return Finding(
                value: .flat,
                evidence: [
                    .init(features.count == 1
                          ? "The \(features[0].name) feature folder has no subfolders."
                          : "None of the \(Prose.count(features.count, "feature folder")) is divided into subfolders.",
                          basis: .namingConvention)
                ]
            )
        }

        guard divided.count == features.count else {
            return Finding(
                value: .inconsistent,
                evidence: [
                    .init("\(divided.count) of \(features.count) features are divided into subfolders; "
                          + "\(Prose.list(features.filter { $0.layers.isEmpty }.map(\.name))) "
                          + "\(features.count - divided.count == 1 ? "is" : "are") flat.",
                          basis: .namingConvention)
                ]
            )
        }

        // Same names in the same order, which is what "divided alike" means
        // when the only thing on disk is folder names.
        let shapes = Set(features.map { $0.layers.joined(separator: "/") })
        guard shapes.count == 1, let layers = features.first?.layers else {
            return Finding(
                value: .inconsistent,
                evidence: [
                    .init("Every feature is divided, but not into the same layers: "
                          + "\(shapes.sorted().map { $0.replacingOccurrences(of: "/", with: " + ") }.joined(separator: "; ")).",
                          basis: .namingConvention)
                ]
            )
        }

        let subject = features.count == 1
            ? "The \(features[0].name) feature is"
            : "All \(features.count) features are"

        return Finding(
            value: .layered,
            evidence: [.init("\(subject) divided into \(Prose.list(layers)).", basis: .namingConvention)]
        )
    }

    // MARK: - Observation

    private func observation() -> Finding<ObservationStyle> {
        let macro = analysis.types(withAttribute: "Observable")
        let objects = analysis.types(conformingTo: "ObservableObject")

        switch (!macro.isEmpty, !objects.isEmpty) {
        case (false, false):
            return Finding(
                value: .unknown,
                evidence: [.init("No type is @Observable or an ObservableObject.", basis: .observedFact)]
            )

        case (true, true):
            return Finding(
                value: .mixed,
                evidence: [
                    .init(Prose.count(macro.count, "type") + " marked @Observable.",
                          basis: .observedFact, locations: locations(macro)),
                    .init(Prose.count(objects.count, "type") + " conforming to ObservableObject.",
                          basis: .observedFact, locations: locations(objects)),
                ]
            )

        case (true, false):
            return Finding(
                value: .observationMacro,
                evidence: [.init(Prose.count(macro.count, "type") + " marked @Observable.",
                                 basis: .observedFact, locations: locations(macro))]
            )

        case (false, true):
            return Finding(
                value: .observableObject,
                evidence: [.init(Prose.count(objects.count, "type") + " conforming to ObservableObject.",
                                 basis: .observedFact, locations: locations(objects))]
            )
        }
    }

    // MARK: - Concurrency

    private func concurrency() -> Finding<ConcurrencyStyle> {
        let asyncFunctions = analysis.asyncFunctionCount
        let actors = analysis.types(ofKind: .actorType)
        let isolated = analysis.types(withAttribute: "MainActor")
        let combineFiles = filesImporting("Combine")

        var evidence: [ArchitectureEvidence] = []
        if asyncFunctions > 0 {
            evidence.append(.init(Prose.count(asyncFunctions, "async function") + ".", basis: .observedFact))
        }
        if !actors.isEmpty {
            evidence.append(.init(Prose.count(actors.count, "actor") + " declared.",
                                  basis: .observedFact, locations: locations(actors)))
        }
        if !isolated.isEmpty {
            evidence.append(.init(Prose.count(isolated.count, "type") + " isolated to @MainActor.",
                                  basis: .observedFact, locations: locations(isolated)))
        }
        if combineFiles > 0 {
            evidence.append(.init("Combine imported by \(Prose.count(combineFiles, "file")).", basis: .observedFact))
        }

        switch (asyncFunctions > 0, combineFiles > 0) {
        case (true, true): return Finding(value: .mixed, evidence: evidence)
        case (true, false): return Finding(value: .asyncAwait, evidence: evidence)
        case (false, true): return Finding(value: .combine, evidence: evidence)
        case (false, false):
            // Actors and @MainActor can be present without either, and are
            // worth keeping in the evidence even when they settle nothing.
            evidence.append(
                .qualifying("No async function, and Combine is not imported.", basis: .observedFact)
            )
            return Finding(value: .unknown, evidence: evidence)
        }
    }

    // MARK: - Persistence

    private func persistence() -> Finding<PersistenceStyle> {
        let swiftDataFiles = filesImporting("SwiftData")
        let coreDataFiles = filesImporting("CoreData")
        let models = analysis.types(withAttribute: "Model")
        let managedObjects = analysis.declaredTypes.filter { $0.conforms(to: "NSManagedObject") }

        var swiftData: [ArchitectureEvidence] = [
            .init("SwiftData imported by \(Prose.count(swiftDataFiles, "file")).", basis: .observedFact)
        ]
        if !models.isEmpty {
            swiftData.append(.init(Prose.count(models.count, "type") + " marked @Model.",
                                   basis: .observedFact, locations: locations(models)))
        }

        var coreData: [ArchitectureEvidence] = [
            .init("CoreData imported by \(Prose.count(coreDataFiles, "file")).", basis: .observedFact)
        ]
        if !managedObjects.isEmpty {
            coreData.append(.init(Prose.count(managedObjects.count, "type") + " inheriting from NSManagedObject.",
                                  basis: .observedFact, locations: locations(managedObjects)))
        }

        switch (swiftDataFiles > 0, coreDataFiles > 0) {
        case (true, true): return Finding(value: .mixed, evidence: swiftData + coreData)
        case (true, false): return Finding(value: .swiftData, evidence: swiftData)
        case (false, true): return Finding(value: .coreData, evidence: coreData)
        case (false, false):
            // Not the same as "stores nothing": UserDefaults and a file on
            // disk leave no import behind.
            return Finding(
                value: .unknown,
                evidence: [.init("Neither SwiftData nor CoreData is imported.", basis: .observedFact)]
            )
        }
    }

    // MARK: - Wiring

    /// How a type gets hold of what it depends on.
    ///
    /// The plan for this phase forbids inferring a composition root from a
    /// name, and it is right to: a type called `AppContainer` that builds
    /// nothing is not a composition root, and a type called `AppState` that
    /// builds the whole object graph is one. So the test is structural — does
    /// something construct several of the project's own services, and do other
    /// types take those same services as initializer parameters. A name is
    /// used only to break ties between two types that both qualify.
    private func wiring() -> (finding: Finding<DependencyWiring>, root: String?) {
        let injected = Set(
            typeGraph.references
                .filter { $0.kind == .initializerDependency }
                .map(\.to)
        )

        // A composition root builds concrete types and hands them over as
        // protocols — `AppContainer` constructs an `APIClient`, and everything
        // downstream takes an `any APIClientProtocol`. Matching only the exact
        // constructed name misses every project that inverts its dependencies,
        // which is most of the ones worth detecting.
        let standingInFor = Set(
            typeGraph.references
                .filter { ($0.kind == .conformance || $0.kind == .inheritance) && injected.contains($0.to) }
                .map(\.from)
        )
        let injectable = injected.union(standingInFor)

        // Who builds the things other types are handed.
        var builders: [String: Set<String>] = [:]
        for reference in typeGraph.references
        where reference.kind == .constructorReference && injectable.contains(reference.to) {
            builders[reference.from, default: []].insert(reference.to)
        }

        let roots = builders
            .filter { $0.value.count >= Self.compositionRootThreshold }
            .keys
            .sorted()

        // A protocol the project declares, taken as an initializer parameter,
        // is dependency inversion actually in use — and unlike a name, it is a
        // fact. Declaring the protocol and conforming to it is not enough:
        // that says the abstraction exists, not that anything travels through
        // it.
        let injectedProtocols = injected.intersection(analysis.declaredProtocolNames)

        let boundaries = ArchitectureEvidence(
            "\(Prose.count(injectedProtocols.count, "protocol")) the project declares "
            + "\(injectedProtocols.count == 1 ? "is" : "are") taken as an initializer parameter.",
            basis: .structuralRelationship,
            locations: Self.sortedLocations(
                typeGraph.references.filter {
                    $0.kind == .initializerDependency && injectedProtocols.contains($0.to)
                })
        )

        if let root = roots.first {
            var evidence: [ArchitectureEvidence] = [
                .init("\(root) constructs \(Prose.count(builders[root]?.count ?? 0, "type")) "
                      + "that other types take as initializer parameters.",
                      basis: .structuralRelationship,
                      locations: Self.sortedLocations(
                          typeGraph.references.filter {
                              $0.from == root && $0.kind == .constructorReference
                          }))
            ]
            if roots.count > 1 {
                evidence.append(
                    .init("\(Prose.list(roots)) all do this.", basis: .structuralRelationship)
                )
            }
            if !injectedProtocols.isEmpty { evidence.append(boundaries) }
            return (Finding(value: .compositionRoot, evidence: evidence), root)
        }

        if !injectedProtocols.isEmpty {
            return (
                Finding(
                    value: .protocolBoundaries,
                    evidence: [
                        boundaries,
                        .qualifying(
                            "No type constructs \(Self.compositionRootThreshold) or more of them "
                            + "in one place.",
                            basis: .structuralRelationship
                        ),
                    ]
                ),
                nil
            )
        }

        return (
            Finding(
                value: .unknown,
                evidence: [
                    .init("Nothing constructs the project's own services in one place, and no "
                          + "protocol it declares is taken as an initializer parameter.",
                          basis: .structuralRelationship)
                ]
            ),
            nil
        )
    }

    /// How many of the project's own injected types something must build
    /// before it counts as assembling the app.
    ///
    /// Three rather than two: a type that builds two things is as likely to be
    /// a factory or a preview helper as a composition root.
    private static let compositionRootThreshold = 3

    // MARK: - Helpers

    /// References from a view or view controller to a type in one of the given
    /// roles.
    private func viewsReaching(roles: Set<TypeRole>) -> [TypeReference] {
        let byName = Dictionary(
            typeGraph.nodes.map { ($0.name, $0.role) }, uniquingKeysWith: { first, _ in first }
        )
        return typeGraph.references.filter { reference in
            let from = byName[reference.from]
            guard from == .view || from == .viewController else { return false }
            guard let to = byName[reference.to] else { return false }
            return roles.contains(to)
        }
    }

    private func viewsReaching(role: TypeRole) -> [TypeReference] {
        viewsReaching(roles: [role])
    }

    private func filesImporting(_ module: String) -> Int {
        analysis.importCounts().first { $0.module == module }?.files ?? 0
    }

    private func locations(_ types: [TypeDeclaration]) -> [String] {
        types.map { "\($0.path):\($0.line)" }
    }

    /// Reference locations in the order somebody would open them.
    ///
    /// The graph orders references by what they connect, which is right for a
    /// graph and arbitrary for a list of places to look.
    private static func sortedLocations(_ references: [TypeReference]) -> [String] {
        references
            .sorted { ($0.file, $0.line) < ($1.file, $1.line) }
            .map(\.location)
    }

}
