import Foundation

/// Writes a project to disk from a resolved configuration.
public struct ProjectGenerator {

    public let configuration: ProjectConfiguration
    let catalog: TemplateCatalog
    let console: Console

    public init(
        configuration: ProjectConfiguration,
        catalog: TemplateCatalog? = nil,
        console: Console = .shared
    ) throws {
        self.configuration = configuration
        self.catalog = try catalog ?? TemplateCatalog()
        self.console = console
    }

    public enum GenerationError: Error, CustomStringConvertible {
        case destinationExists(URL)
        case writeFailed(path: String, underlying: any Error)

        public var description: String {
            switch self {
            case .destinationExists(let url):
                return """
                    \(url.lastPathComponent) already exists at \
                    \(url.deletingLastPathComponent().path). Move it, or choose \
                    a different project name.
                    """
            case .writeFailed(let path, let underlying):
                return "Could not write \(path): \(underlying.localizedDescription)"
            }
        }
    }

    public struct Outcome: Sendable {
        public let projectDirectory: URL
        public let fileCount: Int
        public let didInitializeGitRepository: Bool
    }

    // MARK: - Generation

    /// - Parameter destination: directory to create the project folder inside.
    @discardableResult
    public func generate(in destination: URL, initializeGit: Bool = true) throws -> Outcome {
        let projectDirectory = destination
            .appendingPathComponent(configuration.name.raw, isDirectory: true)
        let fileManager = FileManager.default

        // Refuse rather than merge into an existing directory: writing into
        // someone's project and half-overwriting it is unrecoverable.
        guard !fileManager.fileExists(atPath: projectDirectory.path) else {
            throw GenerationError.destinationExists(projectDirectory)
        }

        let renderer = TemplateRenderer(configuration: configuration)
        try fileManager.createDirectory(at: projectDirectory, withIntermediateDirectories: true)

        var fileCount = 0
        for source in catalog.directories(for: configuration) {
            fileCount += try render(
                tree: source,
                into: projectDirectory,
                with: renderer
            )
        }

        let didInitializeGit = initializeGit ? initializeGitRepository(at: projectDirectory) : false

        return Outcome(
            projectDirectory: projectDirectory,
            fileCount: fileCount,
            didInitializeGitRepository: didInitializeGit
        )
    }

    /// Renders every file under `source` into `destination`, returning how many
    /// were written.
    private func render(tree source: URL, into destination: URL, with renderer: TemplateRenderer) throws -> Int {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var written = 0

        for case let fileURL as URL in enumerator {
            let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory { continue }

            // Tokens apply to every path component, so a template at
            // `__PROJECT_NAME__/App/__PROJECT_NAME__App.swift.tpl` lands at
            // `MyApp/App/MyAppApp.swift`.
            let relativePath = fileURL.path
                .replacingOccurrences(of: source.path + "/", with: "")
                .split(separator: "/")
                .map { renderer.renderPath(String($0)) }
                .joined(separator: "/")

            let target = destination.appendingPathComponent(relativePath)

            do {
                let data = try Data(contentsOf: fileURL)
                // nil means the file is not UTF-8 — an image or other binary
                // asset. Copy those bytes through untouched.
                let output = renderer.renderContents(of: data) ?? data

                // A file whose whole body sat inside a disabled conditional
                // renders to nothing. Writing it would leave an empty source
                // file in the project.
                if renderer.isEffectivelyEmpty(output) { continue }

                try fileManager.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try output.write(to: target)
                written += 1
            } catch {
                throw GenerationError.writeFailed(path: relativePath, underlying: error)
            }
        }

        return written
    }

    // MARK: - Git

    /// A fresh history, so a generated project never inherits Keel's.
    ///
    /// Failure is reported but never fatal: the project is perfectly usable
    /// without a repository, and git may legitimately be absent or have no
    /// identity configured.
    @discardableResult
    private func initializeGitRepository(at directory: URL) -> Bool {
        guard Shell.isAvailable("git") else {
            console.detail("git not found — skipped repository setup")
            return false
        }

        guard Shell.run("git", ["init", "-q", "-b", "main"], in: directory).succeeded else {
            console.detail("git init failed — skipped repository setup")
            return false
        }

        Shell.run("git", ["add", "."], in: directory)
        let commit = Shell.run("git", ["commit", "-q", "-m", "Initial commit from keel"], in: directory)

        if !commit.succeeded {
            // Almost always an unset user.name/user.email. The repository and
            // the staged files are still there, so say what is left to do.
            console.detail("git repository created — commit skipped (is user.email set?)")
        }
        return true
    }
}
