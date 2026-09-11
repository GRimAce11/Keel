import Foundation

/// Turns parsed imports into a graph of what depends on what.
///
/// Classification is conservative. A module Keel cannot place is `unknown`
/// rather than assumed to be an Apple framework — the list of Apple frameworks
/// is long and Keel's copy of it is necessarily incomplete, so an optimistic
/// default would quietly mislabel every in-house framework as system.
struct ImportGraphBuilder {

    /// Apple frameworks common in iOS code.
    ///
    /// Not exhaustive and not meant to be: anything missing lands in `unknown`,
    /// which is honest. The alternative — treating unrecognised names as
    /// system — would hide exactly the project-local dependencies this graph
    /// exists to show.
    static let appleFrameworks: Set<String> = [
        "Foundation", "Swift", "Combine", "Dispatch", "os", "OSLog", "Observation",
        "SwiftUI", "UIKit", "AppKit", "SwiftData", "CoreData", "CloudKit",
        "CoreGraphics", "CoreImage", "CoreLocation", "CoreMotion", "CoreText",
        "CoreBluetooth", "CoreML", "CoreAudio", "CoreMedia", "CoreTelephony",
        "AVFoundation", "AVKit", "Photos", "PhotosUI", "MediaPlayer",
        "MapKit", "Contacts", "ContactsUI", "EventKit", "HealthKit", "HomeKit",
        "Security", "LocalAuthentication", "CryptoKit", "Network", "SystemConfiguration",
        "StoreKit", "PassKit", "WidgetKit", "ActivityKit", "AppIntents", "Intents",
        "UserNotifications", "BackgroundTasks", "WatchKit", "WatchConnectivity",
        "ARKit", "RealityKit", "SceneKit", "SpriteKit", "Metal", "MetalKit",
        "QuartzCore", "ImageIO", "PDFKit", "QuickLook", "VisionKit", "Vision",
        "NaturalLanguage", "Speech", "SafariServices", "WebKit", "MessageUI",
        "Social", "GameKit", "GameController", "Accelerate", "simd",
        "XCTest", "Testing", "UniformTypeIdentifiers", "TipKit", "Charts",
        "Translation", "SwiftUICore", "DeveloperToolsSupport",
        "AppTrackingTransparency", "AdSupport", "VideoToolbox", "AudioToolbox",
        "CoreServices", "CoreFoundation", "Darwin", "MachO", "ObjectiveC",
        "CallKit", "PushKit", "FileProvider", "Charts", "MessageUI",
        "AuthenticationServices", "DeviceCheck", "MetricKit", "OSLog",
        "AVFAudio", "CarPlay", "CoreSpotlight", "CoreNFC", "NearbyInteraction",
        "GroupActivities", "ShazamKit", "SensorKit", "ScreenTime", "Symbols",
    ]

    let model: ModelInputs

    /// What the builder needs, before a `ProjectModel` exists to hold it.
    struct ModelInputs {
        let rootPath: String
        let targets: [Target]
        let modules: [Module]
        let features: [Feature]
        let packages: [PackageDependency]
        /// Product names read from the project file, which is what imports
        /// actually name.
        let packageProducts: Set<String>
        let analysis: SourceAnalysis
    }

    func build() -> ImportGraph {
        // Every target that produces its own module. One app target and its
        // test bundle is the ordinary case, and it means one module.
        let productModules = Set(model.targets.flatMap { Self.moduleNames(forTarget: $0.name) })
        // Products first, since that is what an import statement names.
        let packageNames = model.packageProducts.union(model.packages.map(\.name))

        let edges = model.analysis.files.flatMap { file -> [ImportEdge] in
            let owner = ownership(of: file.path)
            return file.imports.map { declaration in
                ImportEdge(
                    file: file.path,
                    line: declaration.line,
                    module: declaration.module,
                    kind: classify(
                        declaration.module,
                        productModules: productModules,
                        packageNames: packageNames
                    ),
                    owner: owner
                )
            }
        }

        return ImportGraph(
            edges: edges,
            isSingleModule: model.targets.filter { !$0.productType.isTestBundle }.count <= 1
        )
    }

    /// What a target can be imported as.
    ///
    /// Swift module names cannot contain spaces or punctuation, so a target
    /// called `HitsRadioWatch Watch App` is imported as
    /// `HitsRadioWatch_Watch_App`. Comparing an import against the raw target
    /// name misses it and reports a project dependency as unknown.
    static func moduleNames(forTarget name: String) -> [String] {
        let sanitised = String(name.map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "_" })
        return sanitised == name ? [name] : [name, sanitised]
    }

    // MARK: - Classification

    func classify(
        _ module: String,
        productModules: Set<String>,
        packageNames: Set<String>
    ) -> ImportKind {
        // A submodule import — `os.log` — belongs to its root.
        let root = module.split(separator: ".").first.map(String.init) ?? module

        if productModules.contains(module) || productModules.contains(root) {
            return .project
        }
        if Self.appleFrameworks.contains(module) || Self.appleFrameworks.contains(root) {
            return .system
        }
        // Product names come from the project file and are exact. The
        // case-insensitive fallback catches a package whose product Keel could
        // not read, and is a name match rather than a fact.
        if packageNames.contains(module)
            || packageNames.contains(where: { $0.compare(module, options: .caseInsensitive) == .orderedSame })
        {
            return .package
        }
        return .unknown
    }

    // MARK: - Ownership

    /// Places a file by matching its path against the layout already scanned.
    ///
    /// Longest match wins, so a file inside a feature is attributed to the
    /// feature rather than to the `Features` folder above it.
    func ownership(of path: String) -> FileOwnership {
        let target = model.targets
            .map(\.name)
            .filter { path == $0 || path.hasPrefix($0 + "/") }
            .max(by: { $0.count < $1.count })

        if let feature = model.features
            .filter({ path.hasPrefix($0.path + "/") })
            .max(by: { $0.path.count < $1.path.count })
        {
            return FileOwnership(
                target: target,
                module: model.modules.first { path.hasPrefix($0.path + "/") }?.name,
                feature: feature.name,
                layer: layer(of: path, within: feature)
            )
        }

        let module = model.modules
            .filter { path.hasPrefix($0.path + "/") }
            .max(by: { $0.path.count < $1.path.count })

        return FileOwnership(target: target, module: module?.name, feature: nil, layer: nil)
    }

    /// The feature subfolder a file sits in, when the feature has any.
    private func layer(of path: String, within feature: Feature) -> String? {
        let remainder = path.dropFirst(feature.path.count + 1)
        guard let first = remainder.split(separator: "/").first.map(String.init),
              feature.layers.contains(first)
        else { return nil }
        return first
    }
}
