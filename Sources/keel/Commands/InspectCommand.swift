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

        let inspection: ProjectModel
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

    private func render(_ inspection: ProjectModel, console: Console) {
        console.heading(inspection.name)

        if let workspace = inspection.workspacePath {
            console.detail("Workspace         \(workspace)")
        }
        if !inspection.platforms.isEmpty {
            console.detail("Platform          \(inspection.platforms.joined(separator: ", "))")
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
        renderModules(inspection, console: console)
        renderFeatures(inspection, console: console)
        renderSchemes(inspection, console: console)
        renderPackages(inspection, console: console)
        renderSource(inspection, console: console)
        renderDeclarations(inspection, console: console)
        renderArchitecture(inspection, console: console)
    }

    /// What the facts above add up to.
    ///
    /// Reported last and with its evidence attached, so a reader who disagrees
    /// with a conclusion can see exactly which counts produced it. The right
    /// column says whether a finding came from the code or from what someone
    /// named a folder — a distinction worth more than the verdict itself.
    private func renderArchitecture(_ inspection: ProjectModel, console: Console) {
        let architecture = inspection.architecture
        let findings = architecture.findings

        console.heading("Architecture")
        console.detail(architecture.summary)
        // Worth saying, because these counts are deliberately smaller than the
        // ones above: a test double imitates production code on purpose.
        console.detail("Counted from the app's own source; test targets are left out.")
        console.write()

        let labelWidth = findings.map(\.dimension.count).max() ?? 0
        let valueWidth = findings.map(\.value.count).max() ?? 0
        let indent = String(repeating: " ", count: labelWidth + 2)

        for finding in findings {
            let label = finding.dimension.padding(toLength: labelWidth, withPad: " ", startingAt: 0)
            // An undetermined finding already says so in its value; repeating
            // it in the support column would be noise.
            let support = finding.support == .undetermined
                ? ""
                : "  \(finding.support.displayName)"
            let value = finding.value.padding(
                toLength: support.isEmpty ? finding.value.count : valueWidth,
                withPad: " ",
                startingAt: 0
            )
            console.detail("\(label)  \(value)\(support)")

            for line in finding.evidence {
                console.detail("\(indent)\(line)")
            }
        }
    }

    private func renderTargets(_ inspection: ProjectModel, console: Console) {
        let targets = inspection.allTargets
        guard !targets.isEmpty else { return }

        console.heading("Targets (\(targets.count))")
        let width = targets.map(\.name.count).max() ?? 0
        for target in targets {
            let name = target.name.padding(toLength: max(width, 1), withPad: " ", startingAt: 0)
            console.detail("\(name)  \(target.productType.displayName)")
        }
    }

    private func renderModules(_ inspection: ProjectModel, console: Console) {
        guard !inspection.modules.isEmpty else { return }

        console.heading("Modules (\(inspection.modules.count))")
        let width = inspection.modules.map(\.name.count).max() ?? 0
        for module in inspection.modules {
            let name = module.name.padding(toLength: max(width, 1), withPad: " ", startingAt: 0)
            let files = module.swiftFileCount == 1 ? "1 file" : "\(module.swiftFileCount) files"
            console.detail("\(name)  \(files)")
        }
    }

    private func renderFeatures(_ inspection: ProjectModel, console: Console) {
        guard !inspection.features.isEmpty else { return }

        console.heading("Features (\(inspection.features.count))")
        let width = inspection.features.map(\.name.count).max() ?? 0
        for feature in inspection.features {
            let name = feature.name.padding(toLength: max(width, 1), withPad: " ", startingAt: 0)
            let layers = feature.layers.isEmpty ? "" : "  \(feature.layers.joined(separator: ", "))"
            let files = feature.swiftFileCount == 1 ? "1 file" : "\(feature.swiftFileCount) files"
            console.detail("\(name)  \(files)\(layers)")
        }
    }

    private func renderSchemes(_ inspection: ProjectModel, console: Console) {
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

    private func renderPackages(_ inspection: ProjectModel, console: Console) {
        guard !inspection.dependencies.isEmpty else { return }

        console.heading("Package dependencies (\(inspection.dependencies.count))")
        let width = inspection.dependencies.map(\.name.count).max() ?? 0
        for package in inspection.dependencies {
            let name = package.name.padding(toLength: max(width, 1), withPad: " ", startingAt: 0)
            console.detail("\(name)  \(package.requirement ?? "")")
        }
    }

    private func renderDeclarations(_ inspection: ProjectModel, console: Console) {
        let analysis = inspection.analysis
        guard !analysis.types.isEmpty else { return }

        console.heading("Declarations")

        // Counted by kind, so the shape of the codebase is visible at a glance.
        let kinds: [(TypeDeclaration.Kind, String)] = [
            (.structure, "Structs"), (.classType, "Classes"),
            (.enumeration, "Enums"), (.protocolType, "Protocols"),
            (.actorType, "Actors"), (.extensionOf, "Extensions"),
        ]
        for (kind, label) in kinds {
            let count = analysis.types(ofKind: kind).count
            guard count > 0 else { continue }
            console.detail("\(label.padding(toLength: 18, withPad: " ", startingAt: 0))\(count)")
        }

        console.detail("\("Functions".padding(toLength: 18, withPad: " ", startingAt: 0))\(analysis.functionCount)")
        if analysis.asyncFunctionCount > 0 {
            console.detail("\("  async".padding(toLength: 18, withPad: " ", startingAt: 0))\(analysis.asyncFunctionCount)")
        }
        if analysis.throwingFunctionCount > 0 {
            console.detail("\("  throwing".padding(toLength: 18, withPad: " ", startingAt: 0))\(analysis.throwingFunctionCount)")
        }

        renderPatterns(analysis, console: console)
        renderImports(analysis, console: console)
    }

    /// Counts of the patterns that say how a codebase is built.
    private func renderPatterns(_ analysis: SourceAnalysis, console: Console) {
        let patterns: [(String, Int)] = [
            ("@Observable", analysis.types(withAttribute: "Observable").count),
            ("ObservableObject", analysis.types(conformingTo: "ObservableObject").count),
            ("@MainActor", analysis.types(withAttribute: "MainActor").count),
            ("@Model", analysis.types(withAttribute: "Model").count),
            ("SwiftUI View", analysis.types(conformingTo: "View").count),
            ("ViewModels", analysis.types(namedWithSuffix: "ViewModel").count),
            ("Repositories", analysis.types(namedWithSuffix: "Repository").count),
        ].filter { $0.1 > 0 }

        guard !patterns.isEmpty else { return }

        console.heading("Patterns")
        let width = patterns.map(\.0.count).max() ?? 0
        for (name, count) in patterns {
            console.detail("\(name.padding(toLength: max(width, 1), withPad: " ", startingAt: 0))  \(count)")
        }
    }

    /// The most-imported modules, which is the clearest signal of what a
    /// codebase is actually built on.
    private func renderImports(_ analysis: SourceAnalysis, console: Console) {
        let counts = analysis.importCounts().prefix(8)
        guard !counts.isEmpty else { return }

        console.heading("Most imported")
        let width = counts.map(\.module.count).max() ?? 0
        for entry in counts {
            let name = entry.module.padding(toLength: max(width, 1), withPad: " ", startingAt: 0)
            console.detail("\(name)  \(entry.files) file\(entry.files == 1 ? "" : "s")")
        }
    }

    private func renderSource(_ inspection: ProjectModel, console: Console) {
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

        if !inspection.configurations.isEmpty {
            let names = Array(Set(inspection.configurations.map(\.name))).sorted()
            console.detail("Configurations    \(names.joined(separator: ", "))")
        }

        if inspection.testTargets.isEmpty {
            console.warn("No test target found.")
        }
    }
}
