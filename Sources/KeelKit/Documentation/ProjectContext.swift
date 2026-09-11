import Foundation

/// The part of `PROJECT.md` written for whoever reads it next — often a coding
/// agent, sometimes a new contributor.
///
/// Every rule here is a description of what the project already does, not a
/// preference Keel holds. "View models are @MainActor" is printed when this
/// project's view models are, and withheld when they are not — a rule nobody
/// follows is worse than no rule, because the next person will follow it into
/// an inconsistency.
///
/// The prohibitions come from `ProjectChecker`, and so does the list of current
/// concerns. That is deliberate: the things a reader is told not to do are
/// exactly the things `keel check` will object to, so following the document
/// and passing the checker cannot come apart.
public struct ProjectContext {

    public let model: ProjectModel

    public init(model: ProjectModel) {
        self.model = model
    }

    private var analysis: SourceAnalysis { model.analysis.excludingTests() }

    // MARK: - Rules

    /// What the project does, stated as the rule it amounts to.
    public func architectureRules() -> [String] {
        var rules: [String] = []
        let architecture = model.architecture

        let viewModels = analysis.types(namedWithSuffix: "ViewModel")
        if !viewModels.isEmpty, viewModels.allSatisfy({ $0.hasAttribute("MainActor") }) {
            rules.append("View models are `@MainActor`.")
        }

        switch architecture.observation.value {
        case .observationMacro: rules.append("Observable state lives in `@Observable` types.")
        case .observableObject: rules.append("Observable state lives in `ObservableObject` types.")
        default: break
        }

        if case .compositionRoot = architecture.wiring.value,
           let root = analysis.declaredTypes.first(where: { $0.name.hasSuffix("Container") }) {
            rules.append("Dependencies are composed in `\(root.name)` and injected downwards.")
        }

        let names = Set(analysis.declaredTypes.map(\.name))
        if names.contains("APIClientProtocol") || names.contains("APIClient") {
            rules.append("Networking goes through `APIClient`, not `URLSession` directly.")
        }

        let repositories = analysis.types(namedWithSuffix: "Repository")
            .filter { $0.kind != .protocolType }
        let protocols = Set(analysis.declaredTypes.filter { $0.kind == .protocolType }.map(\.name))
        if !repositories.isEmpty, repositories.allSatisfy({ type in
            analysis.types.filter { $0.name == type.name }
                .flatMap(\.inheritedTypes)
                .contains(where: protocols.contains)
        }) {
            rules.append("Repositories sit behind a protocol, so they can be stubbed in tests.")
        }

        if case .asyncAwait = architecture.concurrency.value {
            rules.append("Asynchronous work uses `async`/`await`.")
        }

        switch architecture.persistence.value {
        case .swiftData: rules.append("Persistence is SwiftData.")
        case .coreData: rules.append("Persistence is Core Data.")
        default: break
        }

        return rules
    }

    public func conventions() -> [String] {
        var conventions: [String] = []

        if case .featureBased = model.architecture.organisation.value {
            conventions.append("Code is organised by feature, not by layer.")
        }
        if case .layered = model.architecture.featureLayering.value,
           let layers = model.features.first?.layers, !layers.isEmpty {
            conventions.append(
                "Every feature is divided into \(Architecture.list(layers.map { "`\($0)`" }))."
            )
        }
        if !analysis.types(namedWithSuffix: "ViewModel").isEmpty {
            conventions.append("A screen's state type is named `<Feature>ViewModel`.")
        }
        if !analysis.types(namedWithSuffix: "Repository").isEmpty {
            conventions.append("A feature's data source is named `<Feature>Repository`.")
        }
        if model.source.usesSwiftTesting {
            conventions.append("Tests use Swift Testing (`@Test`, `#expect`), not XCTest.")
        }

        return conventions
    }

    public func dependencyRules() -> [String] {
        guard !model.dependencies.isEmpty else {
            return [
                "There are no package dependencies. Everything is Foundation, SwiftUI and the SDKs."
            ]
        }
        return [
            "Packages in use: \(Architecture.list(model.dependencies.map { "`\($0.name)`" }))."
        ]
    }

    /// Prohibitions, taken from the rules `keel check` enforces.
    ///
    /// Only rules that apply to this project appear: telling someone not to
    /// break a convention the project does not follow is noise.
    public func prohibitions() -> [String] {
        var rules = ["Do not leave a scheme unshared — CI cannot build what it cannot see."]

        if !analysis.types(namedWithSuffix: "ViewModel").isEmpty {
            rules.append("Do not add a view model that is not `@MainActor`.")
            rules.append("Do not add a view model that nothing can observe.")
        }
        if !analysis.types(namedWithSuffix: "Repository").isEmpty {
            rules.append("Do not add a repository with no protocol in front of it.")
        }
        if model.source.importsSwiftUI {
            rules.append("Do not import networking or storage in a file that declares a view.")
        }
        if model.source.usesSwiftData {
            rules.append("Do not use `@Model` in a file that does not import SwiftData.")
        }

        rules.append("Run `keel check` before committing; it enforces all of the above.")
        return rules
    }

    // MARK: - Working on it

    public func commands() -> [(command: String, purpose: String)] {
        var commands: [(String, String)] = []

        if let scheme = model.schemes.first(where: \.isShared)?.name ?? model.schemes.first?.name {
            let destination = "-destination 'platform=iOS Simulator,name=iPhone 16'"
            commands.append((
                "xcodebuild build -scheme \(scheme) \(destination)", "Build"
            ))
            if !model.testTargets.isEmpty {
                commands.append((
                    "xcodebuild test -scheme \(scheme) \(destination)", "Test"
                ))
            }
        }

        commands.append(("keel check", "Validate against the rules above"))
        commands.append(("keel document --check", "Confirm this file is still current"))
        return commands
    }

    /// Where to start reading, by role rather than by guess.
    public func importantFiles() -> [(path: String, purpose: String)] {
        var files: [(String, String)] = []

        // Nested types are excluded: a `L10n.App` enum is not the app entry
        // point, and matching on the qualified name would say it was.
        let topLevel = analysis.declaredTypes.filter { !$0.name.contains(".") }

        func first(_ purpose: String, where match: (TypeDeclaration) -> Bool) {
            guard let type = topLevel.first(where: match) else { return }
            files.append((type.path, purpose))
        }

        first("App entry point") { $0.hasAttribute("main") || $0.name == "\(model.name)App" }
        first("First screen") { $0.name == "RootView" }
        first("Composition root") { $0.name.hasSuffix("Container") }
        first("Networking") { $0.name == "APIClient" }
        first("Screen state contract") { $0.name == "ViewState" }

        // Stable order, and no duplicate rows when one type matches twice.
        var seen = Set<String>()
        return files.filter { seen.insert($0.0).inserted }
    }

    /// What `keel check` says about the project right now.
    public func concerns() -> [Diagnostic] {
        ProjectChecker(model: model).check()
    }
}
