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

    public init(model: ProjectModel) {
        self.model = model
    }

    public func check() -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        diagnostics += missingImports()
        diagnostics += unsharedSchemes()
        diagnostics += viewModelIsolation()
        diagnostics += viewModelObservability()
        diagnostics += viewsOwningInfrastructure()
        diagnostics += repositoriesWithoutProtocols()
        diagnostics += featureLayering()
        diagnostics += testing()
        return diagnostics.ordered()
    }

    // MARK: - Errors

    /// An attribute used without the framework that defines it.
    ///
    /// Structural and certain: the file says `@Model` and does not say
    /// `import SwiftData`, so it cannot build. This is the kind of thing a
    /// compiler would catch — on a project that compiles.
    private func missingImports() -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []

        for file in analysis.files {
            let imports = Set(file.imports)
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

            return Set(file.imports)
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
                detail: model.architecture.featureLayering.evidence.joined(separator: " ")
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

    /// Production code only, for the same reason architecture detection uses
    /// it: a test double is an imitation on purpose.
    private var analysis: SourceAnalysis {
        model.analysis.excludingTests()
    }

    private var viewModels: [TypeDeclaration] {
        analysis.types(namedWithSuffix: "ViewModel")
    }
}
