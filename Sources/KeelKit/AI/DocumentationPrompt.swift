import Foundation

/// Builds the prompt `keel document --ai` sends.
///
/// It sends facts, not code. Everything below was already derived by static
/// analysis and already appears in the document — so the agent is being asked
/// to interpret a summary the project's own files produced, not to read the
/// project. Nobody's source leaves the machine.
///
/// It asks for data, not prose to paste. The agent fills named fields and Keel
/// writes the Markdown, so the shape of the document never depends on the agent
/// having followed formatting instructions.
///
/// The prompt is a value rather than a side effect so it can be printed,
/// inspected and tested. `--show-prompt` exists because "Keel never invokes an
/// agent silently" is worth more when you can see exactly what it would say.
public struct DocumentationPrompt {

    public let model: ProjectModel

    public init(model: ProjectModel) {
        self.model = model
    }

    public func text() -> String {
        """
        You are helping describe an iOS codebase to a developer who has never \
        seen it.

        Reply with a single JSON object and nothing else. Use only the facts \
        listed under FACTS below. They were derived by static analysis of the \
        project and they are all you know: do not invent file names, classes, \
        libraries, history or intentions that are not listed. Where a fact is \
        marked undetermined, leave it alone rather than guessing.

        The object has these keys, all optional — omit any you cannot fill from \
        the facts rather than padding it:

        {
          "overview":    "Two or three sentences on what this project is and how it is put together.",
          "dataFlow":    "One or two sentences on how a request moves through the app.",
          "conventions": ["A convention the facts show this project follows."],
          "risks":       ["Something a new contributor should be careful about."],
          "onboarding":  ["Where to start reading, and why."]
        }

        Plain sentences only. No Markdown, no headings, no bullet characters — \
        the formatting is not yours to choose.

        FACTS

        \(facts())
        """
    }

    // MARK: - Facts

    private func facts() -> String {
        var lines: [String] = ["Project: \(model.name)"]
        lines.append("Summary: \(model.architecture.summary)")

        if !model.platforms.isEmpty {
            lines.append("Platform: \(model.platforms.joined(separator: ", "))")
        }
        if let deployment = model.minimumDeploymentTarget {
            lines.append("Minimum OS: \(deployment)")
        }
        if let swift = model.swiftVersion {
            lines.append("Swift: \(swift)")
        }
        if model.source.swiftFileCount > 0 {
            lines.append("Size: \(model.source.swiftFileCount) Swift files, \(model.source.lineCount) lines")
        }

        lines.append("")
        lines.append("Architecture, with what each conclusion rests on:")
        for finding in model.architecture.findings {
            let basis = finding.support == .undetermined ? "undetermined" : finding.support.displayName
            lines.append("- \(finding.dimension): \(finding.value) (\(basis))")
            for item in finding.evidence {
                lines.append("    \(item)")
            }
        }

        if !model.modules.isEmpty {
            lines.append("")
            lines.append("Top-level folders: " + model.modules
                .map { "\($0.name) (\($0.swiftFileCount) files)" }
                .joined(separator: ", "))
        }

        if !model.features.isEmpty {
            lines.append("")
            lines.append("Features:")
            for feature in model.features {
                let layers = feature.layers.isEmpty
                    ? "no subfolders"
                    : feature.layers.joined(separator: ", ")
                lines.append("- \(feature.name): \(layers), \(feature.swiftFileCount) files")
            }
        }

        if !model.allTargets.isEmpty {
            lines.append("")
            lines.append("Targets: " + model.allTargets
                .map { "\($0.name) (\($0.productType.displayName))" }
                .joined(separator: ", "))
        }

        lines.append("")
        lines.append(
            model.dependencies.isEmpty
                ? "Package dependencies: none"
                : "Package dependencies: " + model.dependencies.map(\.name).joined(separator: ", ")
        )

        let patterns = model.analysis.notablePatterns()
        if !patterns.isEmpty {
            lines.append("Patterns in use: " + patterns
                .map { "\($0.name) (\($0.count))" }
                .joined(separator: ", "))
        }

        if model.testTargets.isEmpty {
            lines.append("Tests: no test target")
        } else {
            lines.append("Tests: " + model.testTargets.map(\.name).joined(separator: ", "))
        }

        return lines.joined(separator: "\n")
    }
}
