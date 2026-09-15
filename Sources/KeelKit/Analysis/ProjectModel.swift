import Foundation

/// Everything Keel determined about a project, by reading its files.
///
/// The one representation the rest of Keel is built on. `inspect` renders it,
/// `document` writes from it, `check` validates against it, `--json` serialises
/// it, and the optional AI layer is handed a summary of it. Nothing downstream
/// re-reads the project for itself, so two commands cannot describe the same
/// project differently.
///
/// ## The layers
///
/// Each layer is built from the one above it, and states less than it could
/// rather than more than it knows:
///
/// 1. **What is on disk** — `projects`, `schemes`, `dependencies`,
///    `configurations`, `modules`, `features`. Read from the project file and
///    the directory layout.
/// 2. **What the source declares** — `analysis`. Types, imports, attributes and
///    conformances, from a real parser rather than pattern matching.
/// 3. **What reaches what** — `importGraph` across module boundaries,
///    `typeGraph` within them. Every edge carries the file and line that wrote
///    it.
/// 4. **What depends on what** — `dependencyGraph()`, the two graphs joined and
///    readable at any scope. Derived rather than stored: it is a join of things
///    already here, and keeping a copy would give the copies room to disagree.
/// 5. **What it all amounts to** — `architecture`. Every finding carries its
///    evidence, and every piece of evidence says whether it is a relationship,
///    a declaration, or a naming convention. Those are never collapsed into one
///    number.
///
/// ## The rules this model keeps
///
/// - **One answer per question.** "Is this a view model" is decided in
///   `TypeGraph` and nowhere else; "what protocols does this project declare"
///   in `SourceAnalysis` and nowhere else. A second opinion is how a report
///   comes to contradict itself.
/// - **Undetermined is representable, and preferred to a guess.** Every
///   architecture value has an `unknown` case, and a finding with nothing
///   behind it reports no basis at all.
/// - **Nothing an agent said reaches these fields.** A scan takes a directory
///   and nothing else — no policy, no agent, no network — so AI has no route
///   in. `ModelCoherenceTests` asserts it rather than trusting it.
/// - **Deterministic and stable.** Files are parsed in parallel and every
///   collection is ordered before it is stored, so two scans of one project
///   produce byte-identical JSON.
public struct ProjectModel: Codable, Sendable, Equatable {
    public let name: String
    public let rootPath: String
    /// Present when the project is opened through a workspace.
    public let workspacePath: String?

    public let projects: [XcodeProject]
    public let schemes: [Scheme]
    public let dependencies: [PackageDependency]
    public let configurations: [BuildConfiguration]

    /// Top-level source groupings, taken from the directory layout.
    public let modules: [Module]
    /// Feature folders, when the project is organised that way.
    public let features: [Feature]

    public let source: SourceSummary
    /// What parsing found. Empty only when the project has no Swift at all.
    public let analysis: SourceAnalysis
    /// What the project's own files reach for, and where they said so.
    public let importGraph: ImportGraph
    /// What the project's own types are made of each other.
    ///
    /// Where `importGraph` stops — at the module boundary — this one keeps
    /// going, because a type reference does not need a boundary to cross.
    public let typeGraph: TypeGraph
    /// What those facts add up to, with the evidence behind each conclusion.
    public let architecture: Architecture

    // MARK: - Derived

    /// Imports and type references joined into one answer to "what depends on
    /// what", readable at file, type, layer, feature, module or target scope.
    ///
    /// Built on demand rather than stored. It is a join of `importGraph` and
    /// `typeGraph`, both of which the model already holds — storing the result
    /// would put the same facts in `--json` three times and give them room to
    /// disagree. It is cheap: a few hundred links on a real project.
    public func dependencyGraph() -> DependencyGraph {
        DependencyGraphBuilder(inputs: .init(
            importGraph: importGraph,
            typeGraph: typeGraph,
            modules: modules
        )).build()
    }

    /// Every name this project actually contains.
    ///
    /// What an agent's interpretation is checked against. An agent given facts
    /// and asked to interpret them has stopped interpreting the moment it names
    /// a `PaymentService` that does not exist — and the invented name is
    /// exactly what a reader would go looking for. This is the vocabulary such
    /// a claim has to be drawn from.
    ///
    /// Declared types are included under both their qualified and simple names,
    /// since a sentence would say `StorageKey` where the model says
    /// `AuthManager.StorageKey`.
    public var vocabulary: Set<String> {
        var names: Set<String> = []

        for type in analysis.declaredTypes {
            names.insert(type.name)
            names.insert(TypeName.simple(of: type.name))
        }
        names.formUnion(features.map(\.name))
        names.formUnion(modules.map(\.name))
        names.formUnion(allTargets.map(\.name))
        names.formUnion(dependencies.map(\.name))
        names.formUnion(importGraph.edges.map(\.module))
        names.formUnion(schemes.map(\.name))
        names.insert(name)

        return names
    }

    public var allTargets: [Target] {
        projects.flatMap(\.targets)
    }

    public var testTargets: [Target] {
        allTargets.filter(\.productType.isTestBundle)
    }

    public var appTargets: [Target] {
        allTargets.filter { $0.productType == .application }
    }

    /// Target names whose directory could hold the app's own source, app
    /// targets first.
    ///
    /// Test bundles are excluded: a test target's folder is definitionally not
    /// the app's source, and anything looking for the source directory takes
    /// the first name that matches — so including them made the answer depend
    /// on the order Xcode happened to write the targets in.
    public var sourceTargetNames: [String] {
        Self.sourceTargetNames(from: allTargets)
    }

    public static func sourceTargetNames(from targets: [Target]) -> [String] {
        targets
            .filter { !$0.productType.isTestBundle }
            .sorted { lhs, _ in lhs.productType == .application }
            .map(\.name)
    }

    /// The platforms the targets build for, derived from their SDK.
    public var platforms: [String] {
        let names = allTargets.compactMap(\.platform).map(Platform.displayName(forSDK:))
        return Array(Set(names)).sorted()
    }

    /// The lowest deployment target across every target that declares one.
    ///
    /// Compared numerically: "9.0" is lower than "17.0", which a string
    /// comparison gets backwards.
    public var minimumDeploymentTarget: String? {
        allTargets
            .compactMap(\.deploymentTarget)
            .min { VersionNumber($0) < VersionNumber($1) }
    }

    public var swiftVersion: String? {
        allTargets.compactMap(\.swiftVersion).max { VersionNumber($0) < VersionNumber($1) }
    }
}

// MARK: - Project

public struct XcodeProject: Codable, Sendable, Equatable {
    public let name: String
    public let path: String
    /// The `objectVersion` in the pbxproj, which indicates the Xcode
    /// generation that wrote it.
    public let objectVersion: Int
    /// Whether new files on disk are picked up without editing the pbxproj.
    public let usesSynchronizedFolders: Bool
    public let targets: [Target]
}

// MARK: - Target

public struct Target: Codable, Sendable, Equatable {
    public let name: String
    public let productType: ProductType
    public let bundleIdentifier: String?
    public let deploymentTarget: String?
    public let swiftVersion: String?
    public let platform: String?
    /// `SWIFT_STRICT_CONCURRENCY`, when the project sets it.
    public let strictConcurrency: String?
}

public enum ProductType: String, Codable, Sendable, Equatable {
    case application
    case unitTestBundle
    case uiTestBundle
    case framework
    case staticLibrary
    case appExtension
    case watchApp
    case other

    init(identifier: String) {
        switch identifier {
        case "com.apple.product-type.application":
            self = .application
        case "com.apple.product-type.bundle.unit-test":
            self = .unitTestBundle
        case "com.apple.product-type.bundle.ui-testing":
            self = .uiTestBundle
        case "com.apple.product-type.framework":
            self = .framework
        case "com.apple.product-type.library.static":
            self = .staticLibrary
        case "com.apple.product-type.app-extension":
            self = .appExtension
        case "com.apple.product-type.application.watchapp2",
             "com.apple.product-type.application.watchapp":
            self = .watchApp
        default:
            self = .other
        }
    }

    public var isTestBundle: Bool {
        self == .unitTestBundle || self == .uiTestBundle
    }

    public var displayName: String {
        switch self {
        case .application: return "App"
        case .unitTestBundle: return "Unit tests"
        case .uiTestBundle: return "UI tests"
        case .framework: return "Framework"
        case .staticLibrary: return "Static library"
        case .appExtension: return "Extension"
        case .watchApp: return "Watch app"
        case .other: return "Other"
        }
    }
}

// MARK: - Platform

public enum Platform {
    /// `iphoneos` -> `iOS`. Reported as the name a developer would use.
    public static func displayName(forSDK sdk: String) -> String {
        switch sdk.lowercased() {
        case let value where value.hasPrefix("iphone"): return "iOS"
        case let value where value.hasPrefix("macosx"): return "macOS"
        case let value where value.hasPrefix("watch"): return "watchOS"
        case let value where value.hasPrefix("appletv"): return "tvOS"
        case let value where value.hasPrefix("xr"): return "visionOS"
        default: return sdk
        }
    }
}

// MARK: - Scheme

public struct Scheme: Codable, Sendable, Equatable {
    public let name: String
    /// Shared schemes are committed; user schemes are not, so CI cannot see
    /// them. A project whose only scheme is a user scheme will fail on a fresh
    /// clone, which is worth reporting.
    public let isShared: Bool
}

// MARK: - Configurations

public struct BuildConfiguration: Codable, Sendable, Equatable {
    public let name: String
    public let projectName: String
}

// MARK: - Packages

public struct PackageDependency: Codable, Sendable, Equatable {
    public let name: String
    public let url: String?
    public let requirement: String?
    public let isLocal: Bool
}

// MARK: - Modules

/// A top-level source grouping, taken from the directory layout.
public struct Module: Codable, Sendable, Equatable {
    public let name: String
    public let path: String
    public let swiftFileCount: Int
    public let role: Role

    /// What a directory is for, inferred from its name.
    ///
    /// This is a naming convention, not a fact about the code, so it stays a
    /// separate field from the name rather than being asserted as structure.
    public enum Role: String, Codable, Sendable, Equatable {
        case app
        case core
        case features
        case shared
        case designSystem
        case resources
        case tests
        case other

        init(directoryName: String) {
            switch directoryName.lowercased() {
            case "app", "application": self = .app
            case "core", "infrastructure", "services": self = .core
            case "features", "modules", "screens": self = .features
            case "shared", "common", "components", "utilities": self = .shared
            case "designsystem", "design", "ui", "theme": self = .designSystem
            case "resources", "assets": self = .resources
            case "tests", "test": self = .tests
            default: self = .other
            }
        }
    }
}

// MARK: - Features

/// A feature folder, with whatever layers it is divided into.
public struct Feature: Codable, Sendable, Equatable {
    public let name: String
    public let path: String
    /// Immediate subdirectories, e.g. `Data`, `Domain`, `Presentation`.
    public let layers: [String]
    public let swiftFileCount: Int
}

// MARK: - Source

public struct SourceSummary: Codable, Sendable, Equatable {
    public let swiftFileCount: Int
    public let lineCount: Int
    public let importsSwiftUI: Bool
    public let importsUIKit: Bool
    public let usesObservationMacro: Bool
    public let usesObservableObject: Bool
    public let usesAsyncAwait: Bool
    public let usesCombine: Bool
    public let usesSwiftData: Bool
    public let usesCoreData: Bool
    public let usesSwiftTesting: Bool
    public let usesXCTest: Bool

    /// How the app builds its UI, where that can be told from imports alone.
    public var uiFramework: String {
        switch (importsSwiftUI, importsUIKit) {
        case (true, true): return "SwiftUI and UIKit"
        case (true, false): return "SwiftUI"
        case (false, true): return "UIKit"
        case (false, false): return "Unknown"
        }
    }
}

// MARK: - Version comparison

/// Compares dotted version strings numerically.
///
/// String comparison puts "9.0" after "17.0", which would report the wrong
/// minimum deployment target for any project still supporting a single-digit
/// major.
struct VersionNumber: Comparable {
    let components: [Int]

    init(_ string: String) {
        components = string.split(separator: ".").map { Int($0) ?? 0 }
    }

    static func < (lhs: VersionNumber, rhs: VersionNumber) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}
