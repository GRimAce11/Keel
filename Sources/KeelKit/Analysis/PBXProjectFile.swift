import Foundation

/// Reads an Xcode `project.pbxproj`.
///
/// A pbxproj is an OpenStep property list, which `PropertyListSerialization`
/// parses natively — so Keel reads real project files with no third-party
/// dependency and no shelling out to `xcodebuild`. That also means inspection
/// works on a project that does not currently build.
struct PBXProjectFile {

    enum ParseError: Error, CustomStringConvertible {
        case unreadable(path: String)
        case malformed(path: String)
        case noRootObject(path: String)

        var description: String {
            switch self {
            case .unreadable(let path):
                return """
                    Could not read \(path) — there is no project.pbxproj inside it. \
                    That usually means a leftover or half-written project directory \
                    rather than a real one.
                    """
            case .malformed(let path):
                return "\(path) is not a readable Xcode project file."
            case .noRootObject(let path):
                return "\(path) has no root object — the project file may be corrupt."
            }
        }
    }

    /// Every object in the file, keyed by its identifier.
    private let objects: [String: [String: Any]]
    private let rootObjectID: String

    let path: URL
    let objectVersion: Int
    /// Whether the project picks files up from the folder tree.
    ///
    /// With synchronized groups, writing a file into the right directory is
    /// all it takes. Without them a file has to be registered in the pbxproj,
    /// and anything Keel writes will be invisible in Xcode until someone adds
    /// it — which is worth saying rather than leaving to be discovered.
    let usesSynchronizedFolders: Bool

    init(path: URL) throws {
        self.path = path

        guard let data = try? Data(contentsOf: path.appendingPathComponent("project.pbxproj")) else {
            throw ParseError.unreadable(path: path.lastPathComponent)
        }

        var format = PropertyListSerialization.PropertyListFormat.openStep
        guard
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format),
            let root = plist as? [String: Any],
            let objects = root["objects"] as? [String: [String: Any]]
        else {
            throw ParseError.malformed(path: path.lastPathComponent)
        }

        guard let rootObjectID = root["rootObject"] as? String else {
            throw ParseError.noRootObject(path: path.lastPathComponent)
        }

        self.objects = objects
        self.rootObjectID = rootObjectID
        self.usesSynchronizedFolders = objects.values.contains {
            ($0["isa"] as? String) == "PBXFileSystemSynchronizedRootGroup"
        }
        self.objectVersion = (root["objectVersion"] as? String).flatMap(Int.init)
            ?? (root["objectVersion"] as? Int)
            ?? 0
    }

    // MARK: - Lookup

    private func object(_ id: String) -> [String: Any]? {
        objects[id]
    }

    private func objects(_ ids: [String]) -> [[String: Any]] {
        ids.compactMap { objects[$0] }
    }

    private var rootProject: [String: Any]? {
        object(rootObjectID)
    }

    // MARK: - Targets

    func targets() -> [Target] {
        guard let ids = rootProject?["targets"] as? [String] else { return [] }

        // Settings declared on the project are inherited by every target that
        // does not override them, so they have to be resolved first.
        let projectSettings = buildSettings(
            forConfigurationList: rootProject?["buildConfigurationList"] as? String
        )

        return objects(ids).compactMap { target in
            guard let name = target["name"] as? String else { return nil }

            let productType = (target["productType"] as? String).map(ProductType.init)
                ?? .other
            let settings = buildSettings(
                forConfigurationList: target["buildConfigurationList"] as? String
            )

            func setting(_ key: String) -> String? {
                settings[key] ?? projectSettings[key]
            }

            return Target(
                name: name,
                productType: productType,
                bundleIdentifier: setting("PRODUCT_BUNDLE_IDENTIFIER"),
                deploymentTarget: setting("IPHONEOS_DEPLOYMENT_TARGET")
                    ?? setting("MACOSX_DEPLOYMENT_TARGET")
                    ?? setting("WATCHOS_DEPLOYMENT_TARGET")
                    ?? setting("TVOS_DEPLOYMENT_TARGET"),
                swiftVersion: setting("SWIFT_VERSION"),
                platform: setting("SDKROOT"),
                strictConcurrency: setting("SWIFT_STRICT_CONCURRENCY")
            )
        }
    }

    /// Merges the build settings of every configuration in a list.
    ///
    /// Debug and Release usually agree on the values inspection cares about —
    /// deployment target, Swift version, bundle identifier. Where they differ,
    /// the first configuration wins, which is deterministic rather than
    /// correct-for-all-cases; reporting per-configuration values would be
    /// noise for the questions this command answers.
    private func buildSettings(forConfigurationList id: String?) -> [String: String] {
        guard
            let id,
            let list = object(id),
            let configurationIDs = list["buildConfigurations"] as? [String]
        else { return [:] }

        var merged: [String: String] = [:]
        for configuration in objects(configurationIDs) {
            guard let settings = configuration["buildSettings"] as? [String: Any] else { continue }
            for (key, value) in settings where merged[key] == nil {
                if let string = value as? String {
                    merged[key] = string
                }
            }
        }
        return merged
    }

    // MARK: - Configurations

    /// The project's build configuration names, in declaration order.
    ///
    /// Read from the project level rather than a target's, because that is
    /// where the set of configurations is defined — a target can only pick from
    /// them, not add to them.
    func configurationNames() -> [String] {
        guard
            let id = rootProject?["buildConfigurationList"] as? String,
            let list = object(id),
            let ids = list["buildConfigurations"] as? [String]
        else { return [] }

        return objects(ids).compactMap { $0["name"] as? String }
    }

    // MARK: - Packages

    /// Product names the project links from its packages.
    ///
    /// A package's name and the products it vends are different things —
    /// `socket.io-client-swift` vends `SocketIO` — so matching an import
    /// against the package name misses most of them. The project file lists the
    /// products outright, which turns a guess into a fact.
    func packageProductNames() -> Set<String> {
        Set(
            objects.values.compactMap { object in
                guard (object["isa"] as? String) == "XCSwiftPackageProductDependency" else {
                    return nil
                }
                return object["productName"] as? String
            }
        )
    }

    func packages() -> [PackageDependency] {
        guard let ids = rootProject?["packageReferences"] as? [String] else { return [] }

        return objects(ids).compactMap { reference in
            switch reference["isa"] as? String {
            case "XCRemoteSwiftPackageReference":
                guard let url = reference["repositoryURL"] as? String else { return nil }
                return PackageDependency(
                    name: Self.packageName(fromRepositoryURL: url),
                    url: url,
                    requirement: Self.describe(requirement: reference["requirement"]),
                    isLocal: false
                )

            case "XCLocalSwiftPackageReference":
                guard let relativePath = reference["relativePath"] as? String else { return nil }
                return PackageDependency(
                    name: (relativePath as NSString).lastPathComponent,
                    url: relativePath,
                    requirement: "local",
                    isLocal: true
                )

            default:
                return nil
            }
        }
    }

    /// `https://github.com/apple/swift-argument-parser.git` -> `swift-argument-parser`
    static func packageName(fromRepositoryURL url: String) -> String {
        var name = (url as NSString).lastPathComponent
        if name.hasSuffix(".git") { name.removeLast(4) }
        return name.isEmpty ? url : name
    }

    /// Renders a package requirement as the short form Xcode shows.
    static func describe(requirement: Any?) -> String? {
        guard let requirement = requirement as? [String: Any],
              let kind = requirement["kind"] as? String else { return nil }

        switch kind {
        case "upToNextMajorVersion":
            return (requirement["minimumVersion"] as? String).map { "from \($0)" }
        case "upToNextMinorVersion":
            return (requirement["minimumVersion"] as? String).map { "up to next minor from \($0)" }
        case "exactVersion":
            return (requirement["version"] as? String).map { "exactly \($0)" }
        case "versionRange":
            guard let lower = requirement["minimumVersion"] as? String,
                  let upper = requirement["maximumVersion"] as? String else { return kind }
            return "\(lower) ..< \(upper)"
        case "branch":
            return (requirement["branch"] as? String).map { "branch \($0)" }
        case "revision":
            return (requirement["revision"] as? String).map { "revision \($0.prefix(7))" }
        default:
            return kind
        }
    }
}
