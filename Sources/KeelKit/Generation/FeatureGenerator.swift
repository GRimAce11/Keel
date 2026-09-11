import Foundation

/// Adds one feature to a project that already exists.
///
/// The project decides the shape, not Keel. Where features live, which layers
/// they are divided into, and which infrastructure exists are all read from the
/// project before anything is written — a project generated without networking
/// gets a feature with no networking in it, rather than a compile error and a
/// stack it never asked for.
public struct FeatureGenerator {

    public enum GenerationError: Error, CustomStringConvertible {
        case invalidName(String)
        case alreadyExists(path: String)
        case noSourceDirectory
        case templatesMissing
        case writeFailed(path: String, underlying: Error)

        public var description: String {
            switch self {
            case .invalidName(let reason):
                return reason
            case .alreadyExists(let path):
                return "\(path) already exists. Delete it, or choose another name."
            case .noSourceDirectory:
                return """
                    Keel could not find the app's source directory, so it does not \
                    know where features belong in this project.
                    """
            case .templatesMissing:
                return "Bundled feature templates could not be located. Please open an issue."
            case .writeFailed(let path, let underlying):
                return "Could not write \(path): \(underlying.localizedDescription)"
            }
        }
    }

    public struct Outcome: Sendable, Equatable {
        public let name: String
        /// Relative to the project root.
        public let featurePath: String
        public let writtenFiles: [String]
        /// True when the project picks new files up on its own.
        public let usesSynchronizedFolders: Bool
    }

    public let model: ProjectModel
    public let console: Console

    public init(model: ProjectModel, console: Console = .shared) {
        self.model = model
        self.console = console
    }

    // MARK: - Generate

    public func generate(named rawName: String) throws -> Outcome {
        let name = try validated(rawName)
        let root = URL(fileURLWithPath: model.rootPath)

        guard let featuresDirectory = featuresDirectoryPath() else {
            throw GenerationError.noSourceDirectory
        }

        let featurePath = "\(featuresDirectory)/\(name)"
        if FileManager.default.fileExists(atPath: root.appendingPathComponent(featurePath).path) {
            throw GenerationError.alreadyExists(path: featurePath)
        }

        guard let templates = try? TemplateCatalog().featureDirectory() else {
            throw GenerationError.templatesMissing
        }

        let renderer = TemplateRenderer(
            configuration: try inferredConfiguration(),
            extraTokens: [
                "__FEATURE_NAME__": name,
                "__FEATURES_DIR__": featuresDirectory,
            ]
        )

        let written = try render(tree: templates, into: root, with: renderer)

        return Outcome(
            name: name,
            featurePath: featurePath,
            writtenFiles: written.sorted(),
            usesSynchronizedFolders: model.projects.allSatisfy(\.usesSynchronizedFolders)
        )
    }

    // MARK: - Reading the project

    /// A feature name has to be usable as a Swift type name, because it becomes
    /// one in five different files.
    private func validated(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            throw GenerationError.invalidName("A feature needs a name.")
        }
        guard name.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            throw GenerationError.invalidName(
                "`\(name)` is not usable as a type name. Letters and digits only."
            )
        }
        guard let first = name.first, first.isLetter else {
            throw GenerationError.invalidName("`\(name)` must start with a letter.")
        }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Where this project keeps its features, relative to the root.
    ///
    /// An existing feature container is reused whatever it is called, since the
    /// project already decided. Only a project with none gets Keel's default,
    /// and even then it goes inside the app's own source directory rather than
    /// somewhere Keel picked.
    func featuresDirectoryPath() -> String? {
        if let container = model.modules.first(where: { $0.role == .features }) {
            return container.path
        }

        let layout = LayoutScanner(
            root: URL(fileURLWithPath: model.rootPath),
            targetNames: model.allTargets.map(\.name)
        )
        guard let source = layout.sourceDirectory() else { return nil }

        let prefix = model.rootPath + "/"
        let path = source.standardizedFileURL.path
        let relative = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
        return "\(relative)/Features"
    }

    /// What the project already has, so the feature is built from the same
    /// parts rather than introducing new ones.
    ///
    /// Read from declarations rather than assumed: a project without an
    /// `APIClientProtocol` has no networking layer to depend on, whatever its
    /// folder names suggest.
    func inferredConfiguration() throws -> ProjectConfiguration {
        var components: Set<Component> = []
        let analysis = model.analysis.excludingTests()
        let names = Set(analysis.declaredTypes.map(\.name))

        if names.contains("APIClientProtocol") || names.contains("APIClient") {
            components.insert(.networking)
        }
        if names.contains(where: { $0.hasSuffix("Container") }) {
            components.insert(.dependencyInjection)
        }
        if !model.testTargets.isEmpty {
            components.insert(.testing)
        }

        return ProjectConfiguration(
            name: try ProjectName(model.name),
            bundleIdentifierPrefix: model.appTargets.compactMap(\.bundleIdentifier).first
                ?? "com.example",
            components: components
        )
    }

    // MARK: - Writing

    private func render(
        tree source: URL,
        into destination: URL,
        with renderer: TemplateRenderer
    ) throws -> [String] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var written: [String] = []

        for case let fileURL as URL in enumerator {
            let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory { continue }

            let relativePath = fileURL.path
                .replacingOccurrences(of: source.path + "/", with: "")
                .split(separator: "/")
                .map { renderer.renderPath(String($0)) }
                .joined(separator: "/")

            let target = destination.appendingPathComponent(relativePath)

            do {
                let data = try Data(contentsOf: fileURL)
                let output = renderer.renderContents(of: data) ?? data

                // A file whose whole body sat inside a disabled conditional
                // renders to nothing — the test file for a project with no test
                // target, say.
                if renderer.isEffectivelyEmpty(output) { continue }

                // Never overwrite. Adding a feature must not silently replace
                // something already there.
                guard !fileManager.fileExists(atPath: target.path) else { continue }

                try fileManager.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try output.write(to: target)
                written.append(relativePath)
            } catch {
                throw GenerationError.writeFailed(path: relativePath, underlying: error)
            }
        }

        return written
    }
}
