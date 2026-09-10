import ArgumentParser
import Foundation
import KeelKit

struct Inspect: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Report the structure of an existing iOS project.",
        discussion: """
            Reads the project's own files — no xcodebuild, no network, no AI. \
            That means it also works on a project that does not currently \
            compile, which is often when you most need to understand it.
            """
    )

    @Argument(help: "Project directory. Defaults to the working directory.")
    var path: String?

    @Flag(name: .customLong("json"), help: "Emit JSON instead of a report.")
    var json = false

    func run() throws {
        let console = Console.shared
        let root = URL(fileURLWithPath: path ?? FileManager.default.currentDirectoryPath)

        let inspection: ProjectInspection
        do {
            inspection = try ProjectScanner(root: root).scan()
        } catch let error as ProjectScanner.ScanError {
            console.error(error.description)
            throw ExitCode.failure
        }

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(inspection), as: UTF8.self))
            return
        }

        render(inspection, console: console)
    }

    // MARK: - Report

    private func render(_ inspection: ProjectInspection, console: Console) {
        console.heading(inspection.name)

        if let workspace = inspection.workspacePath {
            console.detail("Workspace         \(workspace)")
        }
        if let platform = inspection.allTargets.compactMap(\.platform).first {
            console.detail("Platform          \(platform)")
        }
        if let deployment = inspection.minimumDeploymentTarget {
            console.detail("Minimum OS        \(deployment)")
        }
        if let swift = inspection.swiftVersion {
            console.detail("Swift             \(swift)")
        }
        if let bundleID = inspection.appTargets.compactMap(\.bundleIdentifier).first {
            console.detail("Bundle identifier \(bundleID)")
        }

        renderTargets(inspection, console: console)
        renderSchemes(inspection, console: console)
        renderPackages(inspection, console: console)
        renderSource(inspection, console: console)
    }

    private func renderTargets(_ inspection: ProjectInspection, console: Console) {
        let targets = inspection.allTargets
        guard !targets.isEmpty else { return }

        console.heading("Targets (\(targets.count))")
        let width = targets.map(\.name.count).max() ?? 0
        for target in targets {
            let name = target.name.padding(toLength: max(width, 1), withPad: " ", startingAt: 0)
            console.detail("\(name)  \(target.productType.displayName)")
        }
    }

    private func renderSchemes(_ inspection: ProjectInspection, console: Console) {
        guard !inspection.schemes.isEmpty else { return }

        console.heading("Schemes (\(inspection.schemes.count))")
        for scheme in inspection.schemes {
            console.detail("\(scheme.name)\(scheme.isShared ? "" : "  (not shared)")")
        }

        // A scheme that is not shared lives under xcuserdata, which is
        // gitignored — CI cannot see it, and neither can a colleague.
        let unshared = inspection.schemes.filter { !$0.isShared }
        if !unshared.isEmpty {
            console.warn(
                "\(unshared.count) scheme\(unshared.count == 1 ? " is" : "s are") not shared, "
                + "so a fresh clone and CI cannot build \(unshared.count == 1 ? "it" : "them")."
            )
        }
    }

    private func renderPackages(_ inspection: ProjectInspection, console: Console) {
        guard !inspection.packages.isEmpty else { return }

        console.heading("Package dependencies (\(inspection.packages.count))")
        let width = inspection.packages.map(\.name.count).max() ?? 0
        for package in inspection.packages {
            let name = package.name.padding(toLength: max(width, 1), withPad: " ", startingAt: 0)
            console.detail("\(name)  \(package.requirement ?? "")")
        }
    }

    private func renderSource(_ inspection: ProjectInspection, console: Console) {
        let source = inspection.source
        guard source.swiftFileCount > 0 else { return }

        console.heading("Source")
        console.detail("Swift files       \(source.swiftFileCount)")
        console.detail("Lines             \(source.lineCount)")
        console.detail("UI                \(source.uiFramework)")

        var observation: [String] = []
        if source.usesObservationMacro { observation.append("@Observable") }
        if source.usesObservableObject { observation.append("ObservableObject") }
        if source.usesCombine { observation.append("Combine") }
        if !observation.isEmpty {
            console.detail("Observation       \(observation.joined(separator: ", "))")
        }

        if source.usesAsyncAwait {
            console.detail("Concurrency       async/await")
        }
        if let strict = inspection.allTargets.compactMap(\.strictConcurrency).first {
            console.detail("Strict concurrency \(strict)")
        }

        var persistence: [String] = []
        if source.usesSwiftData { persistence.append("SwiftData") }
        if source.usesCoreData { persistence.append("Core Data") }
        if !persistence.isEmpty {
            console.detail("Persistence       \(persistence.joined(separator: ", "))")
        }

        var testing: [String] = []
        if source.usesSwiftTesting { testing.append("Swift Testing") }
        if source.usesXCTest { testing.append("XCTest") }
        if !inspection.testTargets.isEmpty {
            testing.append("\(inspection.testTargets.count) test target\(inspection.testTargets.count == 1 ? "" : "s")")
        }
        console.detail("Testing           \(testing.isEmpty ? "none detected" : testing.joined(separator: ", "))")

        if inspection.testTargets.isEmpty {
            console.warn("No test target found.")
        }
    }
}
