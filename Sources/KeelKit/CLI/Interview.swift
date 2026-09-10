import Foundation

/// Turns answers into a `ProjectConfiguration`.
///
/// Command line flags always win: a component explicitly disabled with
/// `--no-networking` is never asked about, so a scripted run behaves
/// predictably and an interactive run only asks what is still open.
public struct Interview {

    let answers: any AnswerProvider
    let console: Console

    public init(answers: any AnswerProvider, console: Console = .shared) {
        self.answers = answers
        self.console = console
    }

    /// - Parameters:
    ///   - name: the validated project name.
    ///   - bundleIdentifierPrefix: from `--bundle-id`, or nil to ask.
    ///   - minimumIOSVersion: from `--ios`, or nil to ask.
    ///   - preselected: components already decided by flags. Anything absent
    ///     is asked about.
    public func run(
        name: ProjectName,
        bundleIdentifierPrefix: String? = nil,
        minimumIOSVersion: String? = nil,
        preselected: [Component: Bool] = [:]
    ) -> ProjectConfiguration {

        if answers.isInteractive { console.heading("Project") }

        let prefix = bundleIdentifierPrefix ?? answers.text(
            "Bundle identifier prefix",
            default: ProjectConfiguration.Defaults.bundleIdentifierPrefix
        )

        let version = minimumIOSVersion ?? answers.text(
            "Minimum iOS version",
            default: ProjectConfiguration.Defaults.minimumIOSVersion
        )

        if answers.isInteractive { console.heading("Include") }

        var selected: Set<Component> = []
        for component in Component.allCases {
            let include: Bool
            if let decided = preselected[component] {
                include = decided
            } else {
                include = answers.confirm(
                    component.title,
                    detail: component.summary,
                    default: component.isEnabledByDefault
                )
            }
            if include { selected.insert(component) }
        }

        return ProjectConfiguration(
            name: name,
            bundleIdentifierPrefix: prefix,
            minimumIOSVersion: version,
            components: selected
        )
    }
}
