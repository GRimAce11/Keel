import Foundation

/// Locates the template directories that a configuration should draw from.
///
/// Templates are bundled inside the binary rather than fetched at run time.
/// That keeps generation working offline, makes output reproducible for a
/// given Keel version, and removes a class of failure — a network hiccup — from
/// a command whose whole job is to write local files.
public struct TemplateCatalog {

    /// Directory every project gets, whatever was selected.
    public static let baseDirectoryName = "Base"

    public let root: URL

    public enum CatalogError: Error, CustomStringConvertible {
        case templatesMissing

        public var description: String {
            switch self {
            case .templatesMissing:
                return """
                    Bundled templates could not be located. This is a packaging \
                    fault in keel itself — please open an issue.
                    """
            }
        }
    }

    /// - Parameter root: the template tree to read. Defaults to the copy
    ///   bundled with the binary; tests pass a synthetic tree.
    public init(root: URL? = nil) throws {
        guard let resolved = root ?? Self.bundledRoot else {
            throw CatalogError.templatesMissing
        }
        self.root = resolved
    }

    static var bundledRoot: URL? {
        Bundle.module.url(forResource: "Templates", withExtension: nil)
    }

    // MARK: - Selection

    /// `Base`, then one directory per selected component, in a stable order.
    ///
    /// A component with no directory on disk is skipped rather than treated as
    /// an error: a component that only toggles conditional blocks inside shared
    /// files contributes no files of its own, and should not need an empty
    /// folder to say so.
    public func directories(for configuration: ProjectConfiguration) -> [URL] {
        var result: [URL] = []

        if let base = existingDirectory(named: Self.baseDirectoryName) {
            result.append(base)
        }

        // allCases order, not Set order, so generation is deterministic.
        for component in Component.allCases where configuration.includes(component) {
            if let directory = existingDirectory(named: component.templateDirectoryName) {
                result.append(directory)
            }
        }

        return result
    }

    private func existingDirectory(named name: String) -> URL? {
        let url = root.appendingPathComponent(name, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return url
    }
}

// MARK: - Component mapping

public extension Component {
    /// Directory name inside the template tree, upper camel cased to match the
    /// component's title rather than its raw value.
    var templateDirectoryName: String {
        switch self {
        case .networking: return "Networking"
        case .dependencyInjection: return "DependencyInjection"
        case .persistence: return "Persistence"
        case .authentication: return "Authentication"
        case .keychain: return "Keychain"
        case .localization: return "Localization"
        case .testing: return "Testing"
        case .designSystem: return "DesignSystem"
        case .exampleFeature: return "ExampleFeature"
        }
    }
}
