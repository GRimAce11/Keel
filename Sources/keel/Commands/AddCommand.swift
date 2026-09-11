import ArgumentParser
import Foundation
import KeelKit

struct Add: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add to a project that already exists.",
        subcommands: [Feature.self],
        defaultSubcommand: Feature.self
    )
}

extension Add {
    struct Feature: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "feature",
            abstract: "Generate a feature into an existing project.",
            discussion: """
                The project decides the shape. Where features live and which \
                infrastructure exists are read from the project first, so a \
                project generated without networking gets a feature with no \
                networking in it rather than a stack it never asked for.
                """
        )

        @Argument(help: "Feature name, used as a Swift type name.")
        var name: String

        @Argument(help: "Project directory. Defaults to the working directory.")
        var path: String?

        func run() throws {
            let console = Console.shared
            let root = URL(fileURLWithPath: path ?? FileManager.default.currentDirectoryPath)

            let model: ProjectModel
            do {
                model = try ProjectScanner(root: root).scan()
            } catch let error as ProjectScanner.ScanError {
                console.error(error.description)
                throw ExitCode.failure
            }

            let outcome: FeatureGenerator.Outcome
            do {
                outcome = try FeatureGenerator(model: model, console: console)
                    .generate(named: name)
            } catch let error as FeatureGenerator.GenerationError {
                console.error(error.description)
                throw ExitCode.failure
            } catch let error as ProjectName.ValidationError {
                console.error(error.description)
                throw ExitCode.failure
            }

            console.success("Added \(outcome.name) to \(outcome.featurePath)")
            for file in outcome.writtenFiles {
                console.detail(file)
            }

            if !outcome.usesSynchronizedFolders {
                // Without synchronized groups these files exist on disk and are
                // invisible in Xcode, which looks like Keel having done nothing.
                console.warn(
                    "This project does not use synchronized folder groups, so Xcode "
                    + "will not see these files until you add them to the project."
                )
            }

            console.write()
            console.detail("Wire it up from your navigation, then run `keel check`.")
        }
    }
}
