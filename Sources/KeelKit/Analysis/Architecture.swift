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

    // What the project declares.
    public let presentation: Finding<PresentationPattern>
    public let uiCoexistence: Finding<UICoexistence>
    public let observation: Finding<ObservationStyle>
    public let concurrency: Finding<ConcurrencyStyle>
    public let persistence: Finding<PersistenceStyle>

    // How it is laid out.
    public let organisation: Finding<Organisation>
    public let featureLayering: Finding<FeatureLayering>

    // What its types actually do to each other. Read from the type and
    // dependency graphs rather than from declarations, which is the difference
    // between describing a codebase and describing its naming.
    public let presentationFlow: Finding<PresentationFlow>
    public let featureIsolation: Finding<FeatureIsolation>
    public let layerBoundaries: Finding<LayerBoundaries>
    public let dependencyDirection: Finding<DependencyDirection>
    public let persistenceAccess: Finding<DataAccess>
    public let networkingAccess: Finding<DataAccess>
    public let wiring: Finding<DependencyWiring>

    /// The type that assembles the app, when the wiring finding found one.
    ///
    /// Carried rather than looked up again, because a second search would let
    /// the document contradict the finding: detection may have found a root
    /// called `AppState`, and anything hunting for a `*Container` would miss
    /// it and quietly drop the rule.
    public let compositionRoot: String?

    /// Every dimension defaults to undetermined, so a caller states only what
    /// it actually knows and the rest says so rather than being invented.
    public init(
        presentation: Finding<PresentationPattern> = .undetermined,
        uiCoexistence: Finding<UICoexistence> = .undetermined,
        observation: Finding<ObservationStyle> = .undetermined,
        concurrency: Finding<ConcurrencyStyle> = .undetermined,
        persistence: Finding<PersistenceStyle> = .undetermined,
        organisation: Finding<Organisation> = .undetermined,
        featureLayering: Finding<FeatureLayering> = .undetermined,
        presentationFlow: Finding<PresentationFlow> = .undetermined,
        featureIsolation: Finding<FeatureIsolation> = .undetermined,
        layerBoundaries: Finding<LayerBoundaries> = .undetermined,
        dependencyDirection: Finding<DependencyDirection> = .undetermined,
        persistenceAccess: Finding<DataAccess> = .undetermined,
        networkingAccess: Finding<DataAccess> = .undetermined,
        wiring: Finding<DependencyWiring> = .undetermined,
        compositionRoot: String? = nil
    ) {
        self.presentation = presentation
        self.uiCoexistence = uiCoexistence
        self.observation = observation
        self.concurrency = concurrency
        self.persistence = persistence
        self.organisation = organisation
        self.featureLayering = featureLayering
        self.presentationFlow = presentationFlow
        self.featureIsolation = featureIsolation
        self.layerBoundaries = layerBoundaries
        self.dependencyDirection = dependencyDirection
        self.persistenceAccess = persistenceAccess
        self.networkingAccess = networkingAccess
        self.wiring = wiring
        self.compositionRoot = compositionRoot
    }

    /// Every finding in one uniform shape, in reading order.
    ///
    /// The findings are separately typed so that `check` can match on a value
    /// rather than on a string. Rendering wants the opposite, so it gets a
    /// flattened view instead of fourteen near-identical branches.
    public var findings: [ArchitectureFinding] {
        [
            presentation.erased("Presentation"),
            presentationFlow.erased("Screen data"),
            uiCoexistence.erased("UI frameworks"),
            observation.erased("Observation"),
            concurrency.erased("Concurrency"),
            organisation.erased("Organisation"),
            featureLayering.erased("Feature layers"),
            featureIsolation.erased("Feature isolation"),
            layerBoundaries.erased("Layer boundaries"),
            dependencyDirection.erased("Dependency flow"),
            wiring.erased("Wiring"),
            persistence.erased("Persistence"),
            persistenceAccess.erased("Persistence reach"),
            networkingAccess.erased("Networking reach"),
        ]
    }

    // MARK: - Summary

    /// One sentence describing the project, built only from findings the
    /// evidence settled.
    ///
    /// Anything undetermined is left out rather than hedged, so every clause
    /// in the sentence is one Keel can point at a fact for.
    public var summary: String {
        var clauses = [presentationClause, flowClause, organisationClause, wiringClause]
            .compactMap { $0 }

        let foundations = [observationClause, concurrencyClause, persistenceClause].compactMap { $0 }
        if !foundations.isEmpty {
            clauses.append("built on \(Prose.list(foundations))")
        }

        guard !clauses.isEmpty else {
            return "Not enough in the project to describe its architecture."
        }
        return clauses.joined(separator: ", ") + "."
    }

    /// A second paragraph, for what the relationships say rather than what the
    /// declarations do.
    ///
    /// Kept apart from `summary` because it is a different kind of claim, and
    /// running the two together would let "views hold repositories" read as
    /// softly as "organised by feature".
    public var flowSummary: [String] {
        var lines: [String] = []

        switch presentationFlow.value {
        case .throughViewModels:
            lines.append("Screens get their data through view models.")
        case .viewsReachData:
            lines.append("Screens hold repositories or clients themselves.")
        case .mixed:
            lines.append("Some screens go through view models and some reach the data layer directly.")
        case .unknown:
            break
        }

        switch featureIsolation.value {
        case .isolated: lines.append("No feature depends on another.")
        case .coupled: lines.append("Features depend on each other.")
        case .unknown: break
        }

        switch dependencyDirection.value {
        case .featuresOnShared: lines.append("Dependencies run from features towards shared code.")
        case .sharedOnFeatures: lines.append("Shared code depends on a feature, which inverts the usual direction.")
        case .unknown: break
        }

        return lines
    }

    private var flowClause: String? {
        switch presentationFlow.value {
        case .throughViewModels: return "screens fed through view models"
        case .viewsReachData: return "screens reaching the data layer directly"
        case .mixed: return "screens fed both ways"
        case .unknown: return nil
        }
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

}

// MARK: - Evidence

/// What kind of thing a piece of evidence is.
///
/// The distinction the whole analysis turns on, and it is deliberately not a
/// scale. "This type is marked `@Observable`" and "this view holds this view
/// model as a property" are both certain, and they are certain about different
/// things: one is a declaration, the other is a relationship between two. A
/// third kind — "types called `*ViewModel` exist" — is neither, and collapsing
/// all three into a single confidence number is how a naming habit ends up
/// reported as a design.
///
/// The chain runs observed fact → structural relationship → architecture
/// inference. A `Finding` is always the third; these are the first two and the
/// convention that is neither.
public enum EvidenceBasis: String, Codable, Sendable, Equatable, CaseIterable {
    /// The code says it outright: an attribute, a conformance, an import, a
    /// declaration.
    case observedFact
    /// One type's resolved relationship to another, from the type graph.
    case structuralRelationship
    /// A convention: a type-name suffix, a folder name. Right often enough to
    /// report, never strong enough to assert.
    case namingConvention

    public var displayName: String {
        switch self {
        case .observedFact: return "from the code"
        case .structuralRelationship: return "from relationships"
        case .namingConvention: return "from naming"
        }
    }

    /// How much weight this kind of evidence carries, strongest first.
    ///
    /// A relationship outranks a bare declaration because it says more: that
    /// a project declares a `ProfileViewModel` is a smaller fact than that a
    /// `ProfileView` holds one.
    var rank: Int {
        switch self {
        case .structuralRelationship: return 2
        case .observedFact: return 1
        case .namingConvention: return 0
        }
    }
}

/// One fact behind a conclusion, with where to go and check it.
public struct ArchitectureEvidence: Codable, Sendable, Equatable {
    /// Phrased so it can be counted and argued with. A reader who rejects the
    /// verdict can still use this.
    public let statement: String
    public let basis: EvidenceBasis
    /// `file:line` for each place this was read, at most a handful.
    ///
    /// Capped on purpose: a statement covering two hundred types would
    /// otherwise print two hundred lines, and the graphs carry every one of
    /// them for anything that needs the full set.
    public let locations: [String]
    public let stance: Stance

    public init(_ statement: String, basis: EvidenceBasis, locations: [String] = []) {
        self.init(statement, basis: basis, locations: locations, stance: .supporting)
    }

    /// Something true and worth printing that weakens the conclusion.
    public static func qualifying(
        _ statement: String,
        basis: EvidenceBasis,
        locations: [String] = []
    ) -> ArchitectureEvidence {
        ArchitectureEvidence(statement, basis: basis, locations: locations, stance: .qualifying)
    }

    /// Something true and worth printing that the conclusion does not rest on.
    public static func context(
        _ statement: String,
        basis: EvidenceBasis,
        locations: [String] = []
    ) -> ArchitectureEvidence {
        ArchitectureEvidence(statement, basis: basis, locations: locations, stance: .context)
    }

    private init(_ statement: String, basis: EvidenceBasis, locations: [String], stance: Stance) {
        self.statement = statement
        self.basis = basis
        self.locations = Array(locations.prefix(Self.locationLimit))
        self.stance = stance
    }

    /// What an item is doing under the conclusion it sits below.
    ///
    /// Three, not two, because the middle case is the one that quietly
    /// corrupts a confidence score. "One SwiftUI view is declared" is an
    /// observed fact sitting under a verdict of MVVM — and it supports the
    /// *SwiftUI* half of that, not the *MVVM* half. Counting it as support
    /// would make every project with a view and a type called `*ViewModel`
    /// report its MVVM as coming from the code, when the only thing linking
    /// the two is the name.
    public enum Stance: String, Codable, Sendable, Equatable {
        /// Argues for the conclusion.
        case supporting
        /// Argues against it, and is printed anyway.
        case qualifying
        /// Sets the scene without bearing on the verdict.
        case context
    }

    static let locationLimit = 5
}

// MARK: - Finding

/// One conclusion, with the facts that led to it.
///
/// A finding is always an inference — the third link in the chain. What it
/// rests on is in `evidence`, each item saying which of the first two links it
/// is, so the difference between "the code says so" and "somebody named it
/// that" survives all the way to the report.
public struct Finding<Value: ArchitectureValue>: Codable, Sendable, Equatable {
    public let value: Value
    public let support: Support
    public let evidence: [ArchitectureEvidence]

    /// Derives how firmly the conclusion is supported, rather than letting each
    /// rule decide for itself.
    ///
    /// The rule is mechanical so it cannot be got wrong one rule at a time: a
    /// conclusion resting only on names is `conventional`, whatever it
    /// concludes and however confident the rule that wrote it felt. That is the
    /// one thing about this analysis that must never drift.
    public init(value: Value, evidence: [ArchitectureEvidence]) {
        self.value = value
        self.evidence = evidence

        let supporting = evidence.filter { $0.stance == .supporting }
        if value.isUnknown || supporting.isEmpty {
            support = .undetermined
        } else if supporting.contains(where: { $0.basis != .namingConvention }) {
            support = .observed
        } else {
            support = .conventional
        }
    }

    /// A finding with nothing behind it.
    ///
    /// The honest starting point, and what a dimension stays if no rule finds
    /// anything to say about it.
    public static var undetermined: Finding { Finding(value: .unknown, evidence: []) }

    /// Which kinds of evidence contributed, strongest first.
    ///
    /// Empty when nothing was settled. An undetermined finding still carries
    /// evidence — it says why Keel could not tell — but that evidence explains
    /// an absence rather than supporting a verdict, and reporting a basis for a
    /// conclusion nobody reached is how a report starts contradicting itself.
    public var bases: [EvidenceBasis] {
        guard support != .undetermined else { return [] }
        return EvidenceBasis.allCases
            .filter { basis in evidence.contains { $0.basis == basis && $0.stance == .supporting } }
            .sorted { $0.rank > $1.rank }
    }

    /// What to print in the column that says where a finding came from.
    ///
    /// The strongest kind of evidence behind it, named as itself. "From
    /// relationships" is a different claim from "from the code", and a report
    /// that prints the same word for both has thrown away the distinction this
    /// phase exists to keep.
    public var sourceSummary: String {
        bases.first?.displayName ?? Support.undetermined.displayName
    }

    func erased(_ dimension: String) -> ArchitectureFinding {
        ArchitectureFinding(
            dimension: dimension,
            value: value.displayName,
            support: support,
            bases: bases,
            sourceSummary: sourceSummary,
            evidence: evidence
        )
    }
}

/// How directly the evidence supports a finding.
///
/// Coarser than `EvidenceBasis` and kept alongside it rather than merged: this
/// answers "how firmly", the basis answers "on what". A finding can rest
/// firmly on a naming convention — every type in the project really is called
/// that — and still not be a fact about the design.
public enum Support: String, Codable, Sendable, Equatable {
    /// Something other than a name says so.
    case observed
    /// Only a convention says so — a folder name, a type-name suffix.
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
    public let bases: [EvidenceBasis]
    public let sourceSummary: String
    public let evidence: [ArchitectureEvidence]
}

// MARK: - Values

/// A value a finding can carry. Every one of them has an `unknown` case,
/// because "Keel could not tell" has to be representable.
public protocol ArchitectureValue: Codable, Sendable, Equatable {
    var displayName: String { get }
    /// The "could not tell" case.
    ///
    /// Every conforming enum declares `case unknown`, which satisfies this on
    /// its own — an enum case with no associated value is already a static
    /// member of the right type. So the requirement costs no boilerplate and
    /// cannot drift away from the case it names.
    static var unknown: Self { get }
}

public extension ArchitectureValue {
    /// `Finding` needs this to derive support without asking each rule, so an
    /// undetermined verdict can never come back marked as established.
    var isUnknown: Bool { self == Self.unknown }
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

/// How a screen gets what it shows.
///
/// Read from relationships, not from whether types called `*ViewModel` exist.
/// A project can be full of them and still have every view holding its own
/// repository, which is the thing worth knowing and the thing counting names
/// cannot tell you.
public enum PresentationFlow: String, ArchitectureValue {
    /// Views reach view models, and the data layer sits behind those.
    case throughViewModels
    /// Views hold repositories or networking clients themselves.
    case viewsReachData
    /// Both, which is what a half-finished refactor looks like.
    case mixed
    case unknown

    public var displayName: String {
        switch self {
        case .throughViewModels: return "Through view models"
        case .viewsReachData: return "Views reach data"
        case .mixed: return "Mixed"
        case .unknown: return "Undetermined"
        }
    }
}

/// Where SwiftUI and UIKit meet, in a project that has both.
public enum UICoexistence: String, ArchitectureValue {
    case swiftUIOnly
    case uiKitOnly
    /// Both, with a type that bridges them — a representable, or a hosting
    /// controller. The seam is named rather than left to be found.
    case bridged
    /// Both, with no bridge Keel can see. Two apps in one target, or a
    /// migration that has not met in the middle yet.
    case sideBySide
    case unknown

    public var displayName: String {
        switch self {
        case .swiftUIOnly: return "SwiftUI"
        case .uiKitOnly: return "UIKit"
        case .bridged: return "SwiftUI and UIKit, bridged"
        case .sideBySide: return "SwiftUI and UIKit, side by side"
        case .unknown: return "Undetermined"
        }
    }
}

/// Whether features keep to themselves.
public enum FeatureIsolation: String, ArchitectureValue {
    case isolated
    /// At least one feature refers to another's types. Reported, not judged:
    /// nothing in a project layout says features may not use each other.
    case coupled
    case unknown

    public var displayName: String {
        switch self {
        case .isolated: return "Isolated"
        case .coupled: return "Coupled"
        case .unknown: return "Undetermined"
        }
    }
}

/// Whether dependencies respect the order the layer folders imply.
public enum LayerBoundaries: String, ArchitectureValue {
    case respected
    /// Something deeper in the stack refers to something above it —
    /// a data type naming a presentation one.
    case crossed
    case unknown

    public var displayName: String {
        switch self {
        case .respected: return "Respected"
        case .crossed: return "Crossed"
        case .unknown: return "Undetermined"
        }
    }
}

/// Which way dependencies run between shared code and features.
public enum DependencyDirection: String, ArchitectureValue {
    case featuresOnShared
    case sharedOnFeatures
    case unknown

    public var displayName: String {
        switch self {
        case .featuresOnShared: return "Features → shared"
        case .sharedOnFeatures: return "Shared → features"
        case .unknown: return "Undetermined"
        }
    }
}

/// How far up the stack a framework or service is reached for.
///
/// The question behind it is always the same: can this be swapped out, or is
/// it wired into the screens. `unknown` means nothing of the kind was found,
/// not that the answer is unclear.
public enum DataAccess: String, ArchitectureValue {
    /// Only the data layer touches it.
    case isolated
    /// View models reach it, with no repository in between.
    case viewModels
    /// Views reach it directly.
    case views
    /// Views and something else both do.
    case mixed
    case unknown

    public var displayName: String {
        switch self {
        case .isolated: return "Behind the data layer"
        case .viewModels: return "Reached by view models"
        case .views: return "Reached by views"
        case .mixed: return "Mixed across layers"
        case .unknown: return "None found"
        }
    }
}
