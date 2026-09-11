import Foundation

/// How a project is built, drawn from what analysis found inside it.
///
/// Two rules keep this honest. Nothing is reported without something in the
/// project behind it, and every finding says whether that something was the
/// code itself or a naming convention. Where the evidence does not settle a
/// question, the finding says so rather than offering the likeliest answer:
/// `document` writes from this and `check` validates against it, so a guess
/// made here becomes a false claim there.
public struct Architecture: Codable, Sendable, Equatable {
    public let presentation: Finding<PresentationPattern>
    public let organisation: Finding<Organisation>
    public let featureLayering: Finding<FeatureLayering>
    public let observation: Finding<ObservationStyle>
    public let concurrency: Finding<ConcurrencyStyle>
    public let persistence: Finding<PersistenceStyle>
    public let wiring: Finding<DependencyWiring>

    /// Every finding in one uniform shape, in reading order.
    ///
    /// The findings are separately typed so that `check` can match on a value
    /// rather than on a string. Rendering wants the opposite, so it gets a
    /// flattened view instead of seven near-identical branches.
    public var findings: [ArchitectureFinding] {
        [
            presentation.erased("Presentation"),
            organisation.erased("Organisation"),
            featureLayering.erased("Feature layers"),
            observation.erased("Observation"),
            concurrency.erased("Concurrency"),
            persistence.erased("Persistence"),
            wiring.erased("Wiring"),
        ]
    }

    // MARK: - Summary

    /// One sentence describing the project, built only from findings the
    /// evidence settled.
    ///
    /// Anything undetermined is left out rather than hedged, so every clause
    /// in the sentence is one Keel can point at a fact for.
    public var summary: String {
        var clauses = [presentationClause, organisationClause, wiringClause].compactMap { $0 }

        let foundations = [observationClause, concurrencyClause, persistenceClause].compactMap { $0 }
        if !foundations.isEmpty {
            clauses.append("built on \(Self.list(foundations))")
        }

        guard !clauses.isEmpty else {
            return "Not enough in the project to describe its architecture."
        }
        return clauses.joined(separator: ", ") + "."
    }

    private var presentationClause: String? {
        switch presentation.value {
        case .mvvm: return "SwiftUI MVVM"
        case .modelView: return "SwiftUI with no view models"
        case .mvc: return "UIKit MVC"
        case .mixed: return "SwiftUI and UIKit side by side"
        case .unknown: return nil
        }
    }

    private var organisationClause: String? {
        switch organisation.value {
        case .featureBased: return "organised by feature"
        case .layered: return "organised in layers"
        case .grouped: return "grouped by role"
        case .unknown: return nil
        }
    }

    private var wiringClause: String? {
        switch wiring.value {
        case .compositionRoot: return "wired through a composition root"
        case .protocolBoundaries: return "wired through protocols"
        case .unknown: return nil
        }
    }

    private var observationClause: String? {
        switch observation.value {
        case .observationMacro: return "@Observable"
        case .observableObject: return "ObservableObject"
        case .mixed: return "@Observable and ObservableObject together"
        case .unknown: return nil
        }
    }

    private var concurrencyClause: String? {
        switch concurrency.value {
        case .asyncAwait: return "async/await"
        case .combine: return "Combine"
        case .mixed: return "async/await alongside Combine"
        case .unknown: return nil
        }
    }

    private var persistenceClause: String? {
        switch persistence.value {
        case .swiftData: return "SwiftData"
        case .coreData: return "Core Data"
        case .mixed: return "SwiftData and Core Data"
        case .unknown: return nil
        }
    }

    /// "a, b and c" — no serial comma, matching the prose everywhere else.
    static func list(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        guard items.count > 1 else { return last }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }
}

// MARK: - Finding

/// One conclusion, with the facts that led to it.
public struct Finding<Value: ArchitectureValue>: Codable, Sendable, Equatable {
    public let value: Value
    public let support: Support
    /// The facts the conclusion rests on, phrased so they can be counted and
    /// argued with. A reader who disagrees with the verdict can still check
    /// these.
    public let evidence: [String]

    public init(value: Value, support: Support, evidence: [String]) {
        self.value = value
        self.support = support
        self.evidence = evidence
    }

    func erased(_ dimension: String) -> ArchitectureFinding {
        ArchitectureFinding(
            dimension: dimension,
            value: value.displayName,
            support: support,
            evidence: evidence
        )
    }
}

/// How directly the evidence supports a finding.
///
/// The distinction is the whole point: a type marked `@Observable` is a fact
/// about the code, and a type *named* `ArticleViewModel` is a fact about what
/// someone called it. Both are worth reporting; only one of them is proof.
public enum Support: String, Codable, Sendable, Equatable {
    /// The code itself says so — an attribute, a conformance, a declaration.
    case observed
    /// A convention says so — a folder name, a type-name suffix. Right often
    /// enough to report, never strong enough to assert.
    case conventional
    /// Nothing in the project settles the question.
    case undetermined

    public var displayName: String {
        switch self {
        case .observed: return "from the code"
        case .conventional: return "from naming"
        case .undetermined: return "undetermined"
        }
    }
}

/// A finding with its value rendered as text, for output that does not care
/// which dimension it came from.
public struct ArchitectureFinding: Sendable, Equatable {
    public let dimension: String
    public let value: String
    public let support: Support
    public let evidence: [String]
}

// MARK: - Values

/// A value a finding can carry. Every one of them has an `unknown` case,
/// because "Keel could not tell" has to be representable.
public protocol ArchitectureValue: Codable, Sendable, Equatable {
    var displayName: String { get }
}

/// How the app gets pixels on screen and where screen state lives.
public enum PresentationPattern: String, ArchitectureValue {
    /// SwiftUI views alongside types that hold their state.
    case mvvm
    /// SwiftUI views owning their own state, with no view-model layer.
    case modelView
    /// UIKit view controllers.
    case mvc
    /// Both, which is what a migration looks like from the outside.
    case mixed
    case unknown

    public var displayName: String {
        switch self {
        case .mvvm: return "MVVM"
        case .modelView: return "SwiftUI, no view models"
        case .mvc: return "UIKit MVC"
        case .mixed: return "SwiftUI and UIKit"
        case .unknown: return "Undetermined"
        }
    }
}

/// What the top level of the source tree is divided by.
public enum Organisation: String, ArchitectureValue {
    /// One folder per feature, each holding its own stack.
    case featureBased
    /// Divided by layer first — `Data`, `Domain`, `Presentation`.
    case layered
    /// Divided by role — `App`, `Core`, `Shared`.
    case grouped
    case unknown

    public var displayName: String {
        switch self {
        case .featureBased: return "Feature-based"
        case .layered: return "Layered"
        case .grouped: return "Grouped by role"
        case .unknown: return "Undetermined"
        }
    }
}

/// Whether feature folders are divided the same way as each other.
public enum FeatureLayering: String, ArchitectureValue {
    /// Every feature is divided, and divided alike.
    case layered
    /// Divided, but not consistently — the case worth knowing about.
    case inconsistent
    /// No feature has subfolders.
    case flat
    case unknown

    public var displayName: String {
        switch self {
        case .layered: return "Consistent"
        case .inconsistent: return "Inconsistent"
        case .flat: return "Flat"
        case .unknown: return "Undetermined"
        }
    }
}

/// How types tell SwiftUI that something changed.
public enum ObservationStyle: String, ArchitectureValue {
    case observationMacro
    case observableObject
    case mixed
    case unknown

    public var displayName: String {
        switch self {
        case .observationMacro: return "@Observable"
        case .observableObject: return "ObservableObject"
        case .mixed: return "@Observable and ObservableObject"
        case .unknown: return "Undetermined"
        }
    }
}

/// How the app does work that takes time.
public enum ConcurrencyStyle: String, ArchitectureValue {
    case asyncAwait
    case combine
    case mixed
    case unknown

    public var displayName: String {
        switch self {
        case .asyncAwait: return "async/await"
        case .combine: return "Combine"
        case .mixed: return "async/await and Combine"
        case .unknown: return "Undetermined"
        }
    }
}

/// What the app stores data with, where a framework says so.
///
/// `unknown` means no persistence framework is imported — not that the app
/// stores nothing. `UserDefaults` and a file on disk leave no import behind.
public enum PersistenceStyle: String, ArchitectureValue {
    case swiftData
    case coreData
    case mixed
    case unknown

    public var displayName: String {
        switch self {
        case .swiftData: return "SwiftData"
        case .coreData: return "Core Data"
        case .mixed: return "SwiftData and Core Data"
        case .unknown: return "None imported"
        }
    }
}

/// How a type gets hold of what it depends on.
public enum DependencyWiring: String, ArchitectureValue {
    /// One type builds the app's dependencies and hands them down.
    case compositionRoot
    /// Dependencies are abstracted behind the project's own protocols, with
    /// no single place that assembles them.
    case protocolBoundaries
    case unknown

    public var displayName: String {
        switch self {
        case .compositionRoot: return "Composition root"
        case .protocolBoundaries: return "Protocol boundaries"
        case .unknown: return "Undetermined"
        }
    }
}
