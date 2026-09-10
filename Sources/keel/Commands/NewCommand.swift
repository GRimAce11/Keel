import ArgumentParser
import Foundation
import KeelKit

struct New: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Create a new iOS project.",
        discussion: """
            Run with no flags to be asked about each component:

              keel new MyApp

            Or take every default without being asked, for CI and scripts:

              keel new MyApp --yes
            """
    )

    @Argument(help: "Name of the project. Becomes the Xcode target and Swift module name.")
    var name: String

    @Option(
        name: .customLong("bundle-id"),
        help: ArgumentHelp("Bundle identifier prefix. The project slug is appended.", valueName: "prefix")
    )
    var bundleIdentifierPrefix: String?

    @Option(
        name: .customLong("ios"),
        help: ArgumentHelp("Minimum iOS version.", valueName: "version")
    )
    var minimumIOSVersion: String?

    @Option(
        name: [.customShort("o"), .customLong("output")],
        help: ArgumentHelp("Directory to create the project in.", valueName: "path")
    )
    var output: String?

    @Flag(name: [.customShort("y"), .customLong("yes")], help: "Accept every default without asking.")
    var assumeDefaults = false

    @Flag(name: .customLong("no-git"), help: "Skip initialising a git repository.")
    var noGit = false

    @Flag(name: .customLong("minimal"), help: "App skeleton only — no optional components.")
    var minimal = false

    @Flag(name: .customLong("no-networking"), help: "Skip the networking layer.")
    var noNetworking = false

    @Flag(name: .customLong("no-dependency-injection"), help: "Skip the DI container.")
    var noDependencyInjection = false

    @Flag(name: .customLong("no-persistence"), help: "Skip persistence.")
    var noPersistence = false

    @Flag(name: .customLong("no-authentication"), help: "Skip authentication.")
    var noAuthentication = false

    @Flag(name: .customLong("no-keychain"), help: "Skip Keychain storage.")
    var noKeychain = false

    @Flag(name: .customLong("no-localization"), help: "Skip localization.")
    var noLocalization = false

    @Flag(name: .customLong("no-testing"), help: "Skip the unit test target.")
    var noTesting = false

    @Flag(name: .customLong("no-design-system"), help: "Skip the design system.")
    var noDesignSystem = false

    @Flag(name: .customLong("no-example-feature"), help: "Skip the example feature.")
    var noExampleFeature = false

    func run() throws {
        let console = Console.shared

        let projectName: ProjectName
        do {
            projectName = try ProjectName(name)
        } catch let error as ProjectName.ValidationError {
            console.error(error.description)
            throw ExitCode.failure
        }

        if projectName.wasSanitized {
            console.warn("Using \"\(projectName.raw)\" as the project name (from \"\(projectName.original)\").")
        }

        // Nobody is there to answer a piped or CI invocation, and blocking on
        // readLine would hang it rather than fail it.
        let answers: any AnswerProvider = (assumeDefaults || !InteractivePrompt.isAvailable)
            ? DefaultAnswers()
            : InteractivePrompt(console: console)

        let configuration = Interview(answers: answers, console: console).run(
            name: projectName,
            bundleIdentifierPrefix: bundleIdentifierPrefix,
            minimumIOSVersion: minimumIOSVersion,
            preselected: preselectedComponents()
        )

        report(configuration, console: console)
        try generate(configuration, console: console)
    }

    private func generate(_ configuration: ProjectConfiguration, console: Console) throws {
        let destination = URL(
            fileURLWithPath: output ?? FileManager.default.currentDirectoryPath
        ).standardizedFileURL

        do {
            let generator = try ProjectGenerator(configuration: configuration, console: console)
            let outcome = try generator.generate(in: destination, initializeGit: !noGit)

            console.success("Wrote \(outcome.fileCount) files")
            if outcome.didInitializeGitRepository {
                console.success("Initialized git repository")
            }

            let path = outcome.projectDirectory.path.replacingOccurrences(
                of: FileManager.default.currentDirectoryPath + "/",
                with: ""
            )
            console.write()
            console.success("\(configuration.name.raw) is ready.")
            console.write()
            console.write("  cd \(path)")
            console.write("  open \(configuration.name.raw).xcodeproj")
            console.write()

        } catch let error as ProjectGenerator.GenerationError {
            console.error(error.description)
            throw ExitCode.failure
        } catch let error as TemplateCatalog.CatalogError {
            console.error(error.description)
            throw ExitCode.failure
        }
    }

    /// Flags resolve to explicit answers; anything not named on the command
    /// line is left out so the interview asks about it.
    private func preselectedComponents() -> [Component: Bool] {
        if minimal {
            return Dictionary(uniqueKeysWithValues: Component.allCases.map { ($0, false) })
        }

        let disabled: [Component: Bool] = [
            .networking: noNetworking,
            .dependencyInjection: noDependencyInjection,
            .persistence: noPersistence,
            .authentication: noAuthentication,
            .keychain: noKeychain,
            .localization: noLocalization,
            .testing: noTesting,
            .designSystem: noDesignSystem,
            .exampleFeature: noExampleFeature,
        ]

        return disabled.filter(\.value).mapValues { _ in false }
    }

    private func report(_ configuration: ProjectConfiguration, console: Console) {
        // Dependency resolution may have dropped something that was asked for.
        // Say so before anything is written, not after.
        for adjustment in configuration.adjustments {
            console.warn("Skipping \(adjustment.component.title) — \(adjustment.reason).")
        }

        console.heading("Configuration")
        console.detail("Name              \(configuration.name.raw)")
        console.detail("Bundle identifier \(configuration.bundleIdentifier)")
        console.detail("Minimum iOS       \(configuration.minimumIOSVersion)")

        let included = Component.allCases
            .filter(configuration.includes)
            .map(\.title)
        console.detail("Components        \(included.isEmpty ? "none" : included.joined(separator: ", "))")
        console.write()
    }
}
