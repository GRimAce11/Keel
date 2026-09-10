import Foundation

/// Discovers how a project is organised on disk.
///
/// Xcode's project file says almost nothing about structure — with synchronized
/// folder groups it says nothing at all. The directory layout is the only place
/// that information exists, so it is read directly.
///
/// What this produces is a description of the folders, not a claim about the
/// code inside them. A directory called `Core` is reported with the role
/// `core` because that is what the name means by convention, and the role is
/// kept separate from the name so the distinction stays visible.
struct LayoutScanner {

    /// Directories that are never the project's own source.
    static let excludedDirectories: Set<String> = [
        ".build", ".git", "DerivedData", "Pods", "Carthage",
        "node_modules", "build", ".swiftpm", "vendor", "fastlane",
    ]

    /// Names that hold one folder per feature.
    private static let featureContainerNames: Set<String> = [
        "features", "modules", "screens",
    ]

    let root: URL
    /// Names of the project's targets, used to find its source directory.
    let targetNames: [String]

    // MARK: - Modules

    /// The immediate subdirectories of the app's source directory.
    func modules() -> [Module] {
        guard let sourceRoot = sourceDirectory() else { return [] }

        return subdirectories(of: sourceRoot)
            .map { directory in
                Module(
                    name: directory.lastPathComponent,
                    path: relativePath(of: directory),
                    swiftFileCount: swiftFileCount(in: directory),
                    role: Module.Role(directoryName: directory.lastPathComponent)
                )
            }
            // A folder holding no Swift at all — an asset catalog, say — is not
            // a module worth reporting.
            .filter { $0.swiftFileCount > 0 || $0.role == .resources }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Features

    func features() -> [Feature] {
        guard let sourceRoot = sourceDirectory() else { return [] }

        let containers = subdirectories(of: sourceRoot).filter {
            Self.featureContainerNames.contains($0.lastPathComponent.lowercased())
        }

        return containers
            .flatMap(subdirectories(of:))
            .map { directory in
                Feature(
                    name: directory.lastPathComponent,
                    path: relativePath(of: directory),
                    layers: subdirectories(of: directory)
                        .map(\.lastPathComponent)
                        .sorted(),
                    swiftFileCount: swiftFileCount(in: directory)
                )
            }
            .filter { $0.swiftFileCount > 0 }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Source directory

    /// The directory holding the app's own code.
    ///
    /// By overwhelming convention that is a folder named after the target, so
    /// a target name is matched first. Falling back to "the subdirectory with
    /// the most Swift in it" would be a guess, so when no name matches, nothing
    /// is reported rather than something invented.
    func sourceDirectory() -> URL? {
        let candidates = subdirectories(of: root)

        for name in targetNames {
            if let match = candidates.first(where: { $0.lastPathComponent == name }) {
                return match
            }
        }

        // A project nested one level down, as `ios/MyApp/MyApp`, is common
        // enough to be worth one extra hop.
        for directory in candidates {
            for name in targetNames {
                let nested = directory.appendingPathComponent(name, isDirectory: true)
                if isDirectory(nested) { return nested }
            }
        }

        return nil
    }

    // MARK: - Helpers

    private func subdirectories(of directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return contents.filter { url in
            guard isDirectory(url) else { return false }
            // An .xcodeproj and an .xcassets are directories too, but neither
            // is a module.
            guard url.pathExtension.isEmpty else { return false }
            return !Self.excludedDirectories.contains(url.lastPathComponent)
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    private func swiftFileCount(in directory: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var count = 0
        for case let url as URL in enumerator {
            if isDirectory(url) {
                if Self.excludedDirectories.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if url.pathExtension == "swift" { count += 1 }
        }
        return count
    }

    private func relativePath(of url: URL) -> String {
        let path = url.standardizedFileURL.path
        let prefix = root.standardizedFileURL.path + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }
}
