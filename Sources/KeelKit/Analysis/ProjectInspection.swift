import Foundation

/// What Keel determined about an existing project, entirely by reading files.
///
/// Every value here is a fact taken from the project itself. Nothing is
/// guessed, and nothing is filled in by an AI layer — anything Keel could not
/// determine is absent rather than invented.
public struct ProjectInspection: Codable, Sendable, Equatable {
    public let name: String
    public let rootPath: String
    /// Present when the project is opened through a workspace.
    public let workspacePath: String?
    public let projects: [XcodeProject]
    public let schemes: [Scheme]
    public let packages: [PackageDependency]
    public let source: SourceSummary

    public var allTargets: [Target] {
        projects.flatMap(\.targets)
    }

    public var testTargets: [Target] {
        allTargets.filter(\.productType.isTestBundle)
    }

    public var appTargets: [Target] {
        allTargets.filter { $0.productType == .application }
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

// MARK: - Scheme

public struct Scheme: Codable, Sendable, Equatable {
    public let name: String
    /// Shared schemes are committed; user schemes are not, so CI cannot see
    /// them. A project whose only scheme is a user scheme will fail on a fresh
    /// clone, which is worth reporting.
    public let isShared: Bool
}

// MARK: - Packages

public struct PackageDependency: Codable, Sendable, Equatable {
    public let name: String
    public let url: String?
    public let requirement: String?
    public let isLocal: Bool
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
