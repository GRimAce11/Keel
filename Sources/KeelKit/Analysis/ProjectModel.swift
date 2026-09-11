import Foundation

/// Everything Keel determined about a project, by reading its files.
///
/// This is the one representation the rest of Keel is built on: `inspect`
/// renders it, `document` will write from it, `check` will validate against it,
/// and the optional AI layer will interpret it. Nothing downstream re-reads the
/// project for itself, so there is a single definition of every fact.
///
/// Every value here comes from the project. Nothing is guessed, and anything
/// Keel could not determine is absent rather than invented.
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
    /// What those facts add up to, with the evidence behind each conclusion.
    public let architecture: Architecture

    // MARK: - Derived

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
