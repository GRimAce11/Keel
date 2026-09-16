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
          "overview":        "Two or three sentences on what this project is and how it is put together.",
          "dependencyFlow":  "One or two sentences on how a request moves through the app, from the dependencies below.",
          "conventions":     ["A convention the facts show this project follows."],
          "boundaries":      ["A boundary the project keeps that is worth keeping."],
          "inconsistencies": ["Somewhere the facts below disagree with each other."],
          "risks":           ["Something a new contributor should be careful about."],
          "readingOrder":    ["Where to start reading, and why."],
          "legacyAreas":     ["Something that looks older than the rest, and what suggests it."],
          "questions":       ["Something a developer should go and find out."]
        }

        Plain sentences only. No Markdown, no headings, no bullet characters — \
        the formatting is not yours to choose.

        Three rules about what you may say.

        Only name types, features and folders that appear in the facts below. \
        A name that is not there will be dropped, and the sentence with it.

        Keep interpretation and advice apart. `overview`, `dependencyFlow`, \
        `conventions`, `boundaries` and `inconsistencies` are for what the \
        facts show. `risks`, `readingOrder`, `legacyAreas` and `questions` are \
        for what you would suggest. Do not phrase a suggestion as something \
        the project already does — it will be published under a heading that \
        says it is advice.

        Do not repeat what Keel has already written. Everything under ALREADY \
        WRITTEN is in the document already, under its own heading and presented \
        as established. Saying it again — in other words, or under a different \
        key — puts one point in the document twice, once as something Keel \
        measured and once as your suggestion, and the reader cannot tell which \
        of the two to trust. Add what those lines do not cover, or leave the \
        key out.

        FACTS

        \(facts())

        ALREADY WRITTEN

        \(alreadyWritten())
        """
    }

    /// How many of one kind of thing to send — edges, findings, concerns. A
    /// prompt listing every reference in a large project would be mostly
    /// noise, and the agent is being asked for a reading rather than a
    /// recount.
    private static let edgeLimit = 25

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
            let basis = finding.support == .undetermined ? "undetermined" : finding.sourceSummary
            lines.append("- \(finding.dimension): \(finding.value) (\(basis))")
            for item in finding.evidence {
                // The statement and how it was established. The stance matters:
                // an agent told only the statements would read a reason to
                // doubt a verdict as a reason to believe it.
                let stance = item.stance == .supporting ? "" : " [\(item.stance.rawValue)]"
                lines.append("    \(item.statement) (\(item.basis.displayName))\(stance)")
                if !item.locations.isEmpty {
                    lines.append("      at \(item.locations.joined(separator: ", "))")
                }
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

        // The same ten the document's "Most imported" table shows, so the
        // agent reads the project's shape from the list the reader will see.
        let imports = model.analysis.importCounts().prefix(10)
        if !imports.isEmpty {
            lines.append("Most imported modules: " + imports
                .map { "\($0.module) (\($0.files))" }
                .joined(separator: ", "))
        }

        if model.testTargets.isEmpty {
            lines.append("Tests: no test target")
        } else {
            lines.append("Tests: " + model.testTargets.map(\.name).joined(separator: ", "))
        }

        lines += relationshipFacts()
        return lines.joined(separator: "\n")
    }

    /// What the project is made of, and what depends on what.
    ///
    /// The facts this phase exists to send. Without them an agent can only
    /// paraphrase a table it was already given; with them it can say that the
    /// Profile feature reaches Authentication and nothing reaches back.
    ///
    /// Still facts, and still not source: every line here was derived by
    /// parsing files the agent never sees, and every one of them already
    /// appears in `keel inspect`.
    private func relationshipFacts() -> [String] {
        var lines: [String] = []
        let graph = model.typeGraph
        let dependencies = model.dependencyGraph()

        let roles = graph.roleCounts()
        if !roles.isEmpty {
            lines.append("")
            lines.append("What the types are for, by role: " + roles
                .map { "\($0.role.displayName) (\($0.count))" }
                .joined(separator: ", "))
            lines.append(
                "Roles marked in the architecture section as coming from naming were "
                + "read from a type-name suffix, not from the code."
            )
        }

        for scope in [DependencyScope.feature, .module, .layer] {
            let edges = dependencies.edges(at: scope)
            guard !edges.isEmpty else { continue }
            lines.append("")
            lines.append("\(scope.displayName) dependencies:")
            for edge in edges.prefix(Self.edgeLimit) {
                lines.append(
                    "- \(edge.from) → \(edge.to) "
                    + "(\(Prose.count(edge.evidence.count, "reference")), "
                    + "first at \(edge.evidence[0].location))"
                )
            }
            if edges.count > Self.edgeLimit {
                lines.append("- and \(edges.count - Self.edgeLimit) more")
            }
        }

        for scope in DependencyScope.structural {
            for cycle in dependencies.cycles(at: scope) {
                lines.append("")
                lines.append(
                    "Cycle at \(scope.displayName.lowercased()) scope: "
                    + cycle.joined(separator: " → ")
                )
            }
        }

        let findings = graph.findings
        if !findings.isEmpty {
            lines.append("")
            lines.append("Relationships Keel flagged as worth a look:")
            for finding in findings.prefix(Self.edgeLimit) {
                lines.append(
                    "- \(finding.headline): \(finding.rule.summary) "
                    + "(\(finding.support.displayName))"
                )
            }
        }

        if graph.isEmpty {
            lines.append("")
            lines.append("No type relationships were found, so nothing can be said about them.")
        }

        return lines
    }

    // MARK: - Already written

    /// What the document already says, sent so that the agent does not say it
    /// again.
    ///
    /// Conclusions rather than facts, and Keel's own: every line here is
    /// rendered into `PROJECT.md` under a heading that presents it as
    /// established. They are sent as exclusions, not as material to work from.
    ///
    /// Conventions and concerns are the two that matter, because the prompt
    /// asks for both by name. An agent never told what `keel check` already
    /// reported writes a `risks` list restating it, and the reader meets the
    /// same finding twice — once under "Known concerns" as measured, once
    /// under "Risks" marked as a suggestion — with nothing to say which is
    /// which. Withholding them does not prevent the overlap; it only prevents
    /// the agent from noticing it.
    private func alreadyWritten() -> String {
        let context = ProjectContext(model: model)
        var lines: [String] = []

        func section(_ title: String, _ items: [String]) {
            guard !items.isEmpty else { return }
            lines.append("\(title):")
            lines += items.prefix(Self.edgeLimit).map { "- \($0)" }
            lines.append("")
        }

        section("Conventions the document states", context.conventions())
        section("Architecture rules the document states", context.architectureRules())
        section("Prohibitions the document states", context.prohibitions())

        // Stated either way. "Keel found nothing" is itself worth knowing:
        // told only silence, an agent cannot tell an unchecked project from a
        // clean one, and tends to fill `risks` with generic caution.
        let concerns = context.concerns()
        if concerns.isEmpty {
            lines.append("Known concerns: none. `keel check` reports nothing.")
        } else {
            lines.append("Known concerns the document already lists:")
            lines += concerns.prefix(Self.edgeLimit).map { concern in
                let location = concern.location.map { " at \($0)" } ?? ""
                return "- [\(concern.severity.displayName)] \(concern.message)\(location)"
            }
            if concerns.count > Self.edgeLimit {
                lines.append("- and \(concerns.count - Self.edgeLimit) more")
            }
        }

        return lines.joined(separator: "\n")
    }
}
