import Foundation

/// Finds and reads an existing iOS project.
///
/// Everything is determined by reading files on disk — no `xcodebuild`, no
/// network, no AI. That means inspection also works on a project that does not
/// currently compile, which is often exactly when someone needs to understand
/// it.
public struct ProjectScanner {

    public enum ScanError: Error, CustomStringConvertible {
        case noProjectFound(path: String)
        case unreadableProject(String)

        public var description: String {
            switch self {
            case .noProjectFound(let path):
                return """
                    No .xcodeproj or .xcworkspace found in \(path). \
                    Run keel inspect from a project directory, or pass a path.
                    """
            case .unreadableProject(let detail):
                return detail
            }
        }
    }

    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    // MARK: - Scan

    public func scan() throws -> ProjectModel {
        let workspaces = try entries(withExtension: "xcworkspace")
            // An .xcodeproj contains its own .xcworkspace; only a standalone
            // one means the project is opened through a workspace.
            .filter { $0.deletingLastPathComponent().pathExtension != "xcodeproj" }

        let projectPaths = try entries(withExtension: "xcodeproj")

        guard !projectPaths.isEmpty || !workspaces.isEmpty else {
            throw ScanError.noProjectFound(path: root.path)
        }

        var projects: [XcodeProject] = []
        var packages: [PackageDependency] = []
        var configurations: [BuildConfiguration] = []

        for path in projectPaths.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let file: PBXProjectFile
            do {
                file = try PBXProjectFile(path: path)
            } catch let error as PBXProjectFile.ParseError {
                throw ScanError.unreadableProject(error.description)
            }

            projects.append(
                XcodeProject(
                    name: path.deletingPathExtension().lastPathComponent,
                    path: relativePath(of: path),
                    objectVersion: file.objectVersion,
                    targets: file.targets()
                )
            )
            packages.append(contentsOf: file.packages())
            configurations += file.configurationNames().map {
                BuildConfiguration(name: $0, projectName: path.deletingPathExtension().lastPathComponent)
            }
        }

        // The same package can be referenced by several projects in a
        // workspace; report it once.
        var seen = Set<String>()
        let uniquePackages = packages.filter { seen.insert($0.url ?? $0.name).inserted }

        let name = workspaces.first?.deletingPathExtension().lastPathComponent
            ?? projects.first?.name
            ?? root.lastPathComponent

        let sourceScanner = SourceScanner(root: root)

        // Structure comes from the directory layout: with synchronized folder
        // groups the project file says nothing about it at all.
        let layout = LayoutScanner(
            root: root,
            targetNames: projects.flatMap(\.targets).map(\.name)
        )

        let modules = layout.modules()
        let features = layout.features()
        let summary = sourceScanner.scan()
        let analysis = analyze(files: sourceScanner.swiftFiles())

        return ProjectModel(
            name: name,
            rootPath: root.path,
            workspacePath: workspaces.first.map(relativePath(of:)),
            projects: projects,
            schemes: schemes(in: projectPaths + workspaces),
            dependencies: uniquePackages.sorted { $0.name.lowercased() < $1.name.lowercased() },
            configurations: configurations,
            modules: modules,
            features: features,
            source: summary,
            analysis: analysis,
            architecture: ArchitectureDetector(
                modules: modules,
                features: features,
                // Detection reads production code only. A test double imitates
                // the real thing on purpose, and counting one would let the
                // test suite change the architecture Keel reports.
                analysis: analysis.excludingTests()
            ).detect()
        )
    }

    // MARK: - Source

    /// Parses every Swift file the source scanner found.
    ///
    /// Files are parsed in parallel: a few hundred files is normal and each
    /// parse is independent, so this is the one place concurrency is worth the
    /// complexity.
    private func analyze(files: [URL]) -> SourceAnalysis {
        let analyzer = SwiftSourceAnalyzer()
        let root = self.root

        var results = [FileAnalysis?](repeating: nil, count: files.count)
        results.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: files.count) { index in
                // Each iteration writes to its own slot, so no two threads
                // touch the same memory.
                buffer[index] = analyzer.analyze(fileAt: files[index], relativeTo: root)
            }
        }

        return SourceAnalysis(files: results.compactMap { $0 })
    }

    // MARK: - Schemes

    /// Shared schemes live in the container; user schemes live under
    /// `xcuserdata` and are usually gitignored.
    private func schemes(in containers: [URL]) -> [Scheme] {
        var found: [Scheme] = []

        for container in containers {
            let shared = container
                .appendingPathComponent("xcshareddata")
                .appendingPathComponent("xcschemes")
            found += schemeNames(in: shared).map { Scheme(name: $0, isShared: true) }

            let userData = container.appendingPathComponent("xcuserdata")
            for directory in (try? FileManager.default.contentsOfDirectory(
                at: userData,
                includingPropertiesForKeys: nil
            )) ?? [] {
                let userSchemes = directory.appendingPathComponent("xcschemes")
                found += schemeNames(in: userSchemes).map { Scheme(name: $0, isShared: false) }
            }
        }

        // A scheme shared in one place and user-local in another counts as
        // shared, which is what determines whether CI can see it.
        var byName: [String: Scheme] = [:]
        for scheme in found {
            if let existing = byName[scheme.name], existing.isShared { continue }
            byName[scheme.name] = scheme
        }
        return byName.values.sorted { $0.name < $1.name }
    }

    private func schemeNames(in directory: URL) -> [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents
            .filter { $0.pathExtension == "xcscheme" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    // MARK: - Helpers

    /// Finds containers at the root, then one level down.
    ///
    /// A deep search would wander into Pods and checked-out packages, each of
    /// which brings its own projects and would drown the real one.
    private func entries(withExtension pathExtension: String) throws -> [URL] {
        let fileManager = FileManager.default
        var results: [URL] = []

        func collect(in directory: URL) {
            let contents = (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            results += contents.filter { $0.pathExtension == pathExtension }
        }

        collect(in: root)
        if results.isEmpty {
            let subdirectories = (try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for directory in subdirectories
            where (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                collect(in: directory)
            }
        }

        return results
    }

    private func relativePath(of url: URL) -> String {
        let path = url.standardizedFileURL.path
        let prefix = root.path + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }
}
