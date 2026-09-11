import Foundation

/// Works out how a project is built, from the layout and the parsed source.
///
/// Each rule is written as "what would have to be true": a project is not
/// MVVM because it resembles the diagram, it is MVVM because it declares
/// views *and* it declares the types that hold their state. Every rule records
/// the counts it used, so a reader can reject the conclusion and still trust
/// the numbers.
///
/// Where a rule can only appeal to a name — a folder called `Features`, a type
/// called `ArticleViewModel` — it says so through `Support.conventional`
/// instead of dressing a convention up as a fact.
struct ArchitectureDetector {

    /// Top-level folder names that mean a layer rather than a feature.
    private static let layerNames: Set<String> = [
        "data", "domain", "presentation", "ui", "view", "views",
        "model", "models", "viewmodel", "viewmodels",
    ]

    /// Name endings a composition root goes by. Deliberately short: a wider
    /// list would start matching types that merely hold things.
    private static let compositionRootSuffixes = ["Container", "Assembler", "Resolver"]

    let modules: [Module]
    let features: [Feature]
    /// Parsed source with tests already removed — see
    /// `SourceAnalysis.excludingTests()`.
    let analysis: SourceAnalysis

    func detect() -> Architecture {
        Architecture(
            presentation: presentation(),
            organisation: organisation(),
            featureLayering: featureLayering(),
            observation: observation(),
            concurrency: concurrency(),
            persistence: persistence(),
            wiring: wiring()
        )
    }

    // MARK: - Presentation

    private func presentation() -> Finding<PresentationPattern> {
        // `View` on its own would match any protocol of that name, so SwiftUI
        // has to actually be imported for a conformance to mean a screen.
        let views = filesImporting("SwiftUI") > 0 ? analysis.types(conformingTo: "View").count : 0
        let controllers = viewControllers()

        switch (views > 0, !controllers.isEmpty) {
        case (false, false):
            return Finding(
                value: .unknown,
                support: .undetermined,
                evidence: ["No SwiftUI view and no view controller declared."]
            )

        case (true, true):
            return Finding(
                value: .mixed,
                support: .observed,
                evidence: [
                    "\(count(views, "SwiftUI view")) declared.",
                    "\(count(controllers.count, "view controller")) declared.",
                ]
            )

        case (false, true):
            return Finding(
                value: .mvc,
                support: .observed,
                evidence: [
                    "\(count(controllers.count, "view controller")) declared.",
                    "No type conforms to SwiftUI's View.",
                ]
            )

        case (true, false):
            return swiftUIPresentation(views: views)
        }
    }

    /// SwiftUI is in use; the question is whether screen state lives outside
    /// the view.
    private func swiftUIPresentation(views: Int) -> Finding<PresentationPattern> {
        let viewModels = analysis.types(namedWithSuffix: "ViewModel")

        guard !viewModels.isEmpty else {
            return Finding(
                value: .modelView,
                support: .conventional,
                evidence: [
                    "\(count(views, "SwiftUI view")) declared.",
                    "No type is named with a ViewModel suffix.",
                ]
            )
        }

        // The name alone is a convention. A view model that is `@Observable`
        // or an `ObservableObject` is doing the job its name claims, which is
        // the difference between reporting a habit and reporting a design.
        let observable = viewModels.filter {
            $0.hasAttribute("Observable") || $0.conforms(to: "ObservableObject")
        }

        var evidence = [
            "\(count(views, "SwiftUI view")) declared.",
            "\(count(viewModels.count, "type")) named with a ViewModel suffix.",
        ]
        if observable.isEmpty {
            evidence.append("None of them is @Observable or an ObservableObject, so the name is the only evidence.")
        } else {
            evidence.append(
                "\(observable.count) of those \(observable.count == 1 ? "is" : "are") @Observable or an ObservableObject."
            )
        }

        return Finding(
            value: .mvvm,
            support: observable.isEmpty ? .conventional : .observed,
            evidence: evidence
        )
    }

    /// A view controller by inheritance, or failing that by name.
    ///
    /// Inheriting from something ending in `ViewController` is the real
    /// signal; the name check catches a subclass of a project's own base class
    /// that syntax cannot follow back to UIKit.
    private func viewControllers() -> [TypeDeclaration] {
        analysis.declaredTypes.filter { type in
            type.inheritedTypes.contains { $0.hasSuffix("ViewController") }
                || type.name.hasSuffix("ViewController")
        }
    }

    // MARK: - Organisation

    private func organisation() -> Finding<Organisation> {
        guard !modules.isEmpty else {
            return Finding(
                value: .unknown,
                support: .undetermined,
                evidence: ["No top-level source folders to read a layout from."]
            )
        }

        if !features.isEmpty {
            let containers = modules.filter { $0.role == .features }.map(\.name)
            var evidence = ["\(count(features.count, "feature folder")) found."]
            if !containers.isEmpty {
                evidence.append("Held under \(Architecture.list(containers)).")
            }
            return Finding(value: .featureBased, support: .conventional, evidence: evidence)
        }

        let layers = modules.filter { Self.layerNames.contains($0.name.lowercased()) }
        if layers.count > 1 {
            return Finding(
                value: .layered,
                support: .conventional,
                evidence: ["Top level divided into \(Architecture.list(layers.map(\.name)))."]
            )
        }

        let named = modules.filter { $0.role != .other }
        if named.count > 1 {
            return Finding(
                value: .grouped,
                support: .conventional,
                evidence: ["Top level divided into \(Architecture.list(named.map(\.name)))."]
            )
        }

        return Finding(
            value: .unknown,
            support: .undetermined,
            evidence: [
                "\(count(modules.count, "top-level folder")), not divided by feature, by layer or by role."
            ]
        )
    }

    // MARK: - Feature layers

    private func featureLayering() -> Finding<FeatureLayering> {
        guard !features.isEmpty else {
            return Finding(
                value: .unknown,
                support: .undetermined,
                evidence: ["The project is not organised into feature folders."]
            )
        }

        let divided = features.filter { !$0.layers.isEmpty }

        guard !divided.isEmpty else {
            return Finding(
                value: .flat,
                support: .conventional,
                evidence: [
                    features.count == 1
                        ? "The \(features[0].name) feature folder has no subfolders."
                        : "None of the \(count(features.count, "feature folder")) is divided into subfolders."
                ]
            )
        }

        guard divided.count == features.count else {
            return Finding(
                value: .inconsistent,
                support: .conventional,
                evidence: [
                    "\(divided.count) of \(features.count) features are divided into subfolders; "
                    + "\(Architecture.list(features.filter { $0.layers.isEmpty }.map(\.name))) "
                    + "\(features.count - divided.count == 1 ? "is" : "are") flat."
                ]
            )
        }

        // Same names in the same order, which is what "divided alike" means
        // when the only thing on disk is folder names.
        let shapes = Set(features.map { $0.layers.joined(separator: "/") })
        guard shapes.count == 1, let layers = features.first?.layers else {
            return Finding(
                value: .inconsistent,
                support: .conventional,
                evidence: [
                    "Every feature is divided, but not into the same layers: "
                    + "\(shapes.sorted().map { $0.replacingOccurrences(of: "/", with: " + ") }.joined(separator: "; "))."
                ]
            )
        }

        let subject = features.count == 1
            ? "The \(features[0].name) feature is"
            : "All \(features.count) features are"

        return Finding(
            value: .layered,
            support: .conventional,
            evidence: ["\(subject) divided into \(Architecture.list(layers))."]
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
                support: .undetermined,
                evidence: ["No type is @Observable or an ObservableObject."]
            )

        case (true, true):
            return Finding(
                value: .mixed,
                support: .observed,
                evidence: [
                    "\(count(macro.count, "type")) marked @Observable.",
                    "\(count(objects.count, "type")) conforming to ObservableObject.",
                ]
            )

        case (true, false):
            return Finding(
                value: .observationMacro,
                support: .observed,
                evidence: ["\(count(macro.count, "type")) marked @Observable."]
            )

        case (false, true):
            return Finding(
                value: .observableObject,
                support: .observed,
                evidence: ["\(count(objects.count, "type")) conforming to ObservableObject."]
            )
        }
    }

    // MARK: - Concurrency

    private func concurrency() -> Finding<ConcurrencyStyle> {
        let asyncFunctions = analysis.asyncFunctionCount
        let actors = analysis.types(ofKind: .actorType).count
        let isolated = analysis.types(withAttribute: "MainActor").count
        let combineFiles = filesImporting("Combine")

        var evidence: [String] = []
        if asyncFunctions > 0 { evidence.append("\(count(asyncFunctions, "async function")).") }
        if actors > 0 { evidence.append("\(count(actors, "actor")) declared.") }
        if isolated > 0 { evidence.append("\(count(isolated, "type")) isolated to @MainActor.") }
        if combineFiles > 0 { evidence.append("Combine imported by \(count(combineFiles, "file")).") }

        switch (asyncFunctions > 0, combineFiles > 0) {
        case (true, true):
            return Finding(value: .mixed, support: .observed, evidence: evidence)
        case (true, false):
            return Finding(value: .asyncAwait, support: .observed, evidence: evidence)
        case (false, true):
            return Finding(value: .combine, support: .observed, evidence: evidence)
        case (false, false):
            // Actors and @MainActor can be present without either, and are
            // worth keeping in the evidence even when they settle nothing.
            evidence.append("No async function, and Combine is not imported.")
            return Finding(value: .unknown, support: .undetermined, evidence: evidence)
        }
    }

    // MARK: - Persistence

    private func persistence() -> Finding<PersistenceStyle> {
        let swiftDataFiles = filesImporting("SwiftData")
        let coreDataFiles = filesImporting("CoreData")
        let models = analysis.types(withAttribute: "Model").count
        let managedObjects = analysis.declaredTypes.filter { $0.conforms(to: "NSManagedObject") }.count

        var swiftData = ["SwiftData imported by \(count(swiftDataFiles, "file"))."]
        if models > 0 { swiftData.append("\(count(models, "type")) marked @Model.") }

        var coreData = ["CoreData imported by \(count(coreDataFiles, "file"))."]
        if managedObjects > 0 {
            coreData.append("\(count(managedObjects, "type")) inheriting from NSManagedObject.")
        }

        switch (swiftDataFiles > 0, coreDataFiles > 0) {
        case (true, true):
            return Finding(value: .mixed, support: .observed, evidence: swiftData + coreData)
        case (true, false):
            return Finding(value: .swiftData, support: .observed, evidence: swiftData)
        case (false, true):
            return Finding(value: .coreData, support: .observed, evidence: coreData)
        case (false, false):
            // Not the same as "stores nothing": UserDefaults and a file on
            // disk leave no import behind.
            return Finding(
                value: .unknown,
                support: .undetermined,
                evidence: ["Neither SwiftData nor CoreData is imported."]
            )
        }
    }

    // MARK: - Wiring

    private func wiring() -> Finding<DependencyWiring> {
        // Sorted, so which one gets named does not depend on the order the
        // file system handed the files over.
        let roots = analysis.declaredTypes
            .filter { type in
                type.kind != .protocolType
                    && Self.compositionRootSuffixes.contains { type.name.hasSuffix($0) }
            }
            .sorted { $0.name < $1.name }

        // A protocol the project declares, with something in the project
        // conforming to it, is the structural half of dependency inversion —
        // and unlike a name, it is a fact.
        let declaredProtocols = Set(
            analysis.declaredTypes.filter { $0.kind == .protocolType }.map(\.name)
        )
        let conformances = analysis.types.filter { type in
            type.kind != .protocolType
                && type.inheritedTypes.contains(where: declaredProtocols.contains)
        }
        let conformers = Set(conformances.map(\.name))
        let satisfied = Set(conformances.flatMap { $0.inheritedTypes.filter(declaredProtocols.contains) })

        let boundaries = "\(count(conformers.count, "type")) conforming to "
            + "\(count(satisfied.count, "protocol")) the project declares."

        if let root = roots.first {
            var evidence = [
                roots.count == 1
                    ? "\(root.name) declared in \(root.path)."
                    : "\(Architecture.list(roots.map(\.name))) declared."
            ]
            if !conformers.isEmpty { evidence.append(boundaries) }
            return Finding(value: .compositionRoot, support: .conventional, evidence: evidence)
        }

        if !conformers.isEmpty {
            return Finding(
                value: .protocolBoundaries,
                support: .observed,
                evidence: [
                    boundaries,
                    "No type is named \(Architecture.list(Self.compositionRootSuffixes)).",
                ]
            )
        }

        return Finding(
            value: .unknown,
            support: .undetermined,
            evidence: ["No composition root, and nothing conforming to a protocol the project declares."]
        )
    }

    // MARK: - Helpers

    private func filesImporting(_ module: String) -> Int {
        analysis.importCounts().first { $0.module == module }?.files ?? 0
    }

    /// "1 view" / "4 views". Evidence has to be countable to be arguable.
    private func count(_ number: Int, _ singular: String) -> String {
        "\(number) \(singular)\(number == 1 ? "" : "s")"
    }
}
