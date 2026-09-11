import ArgumentParser
import KeelKit

@main
struct Keel: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keel",
        abstract: "Create, understand, and maintain iOS projects from the terminal.",
        discussion: """
            keel generates new iOS projects and analyses existing ones. \
            Everything it reports is derived from your project by static \
            analysis — no AI is required, and none is ever invoked without \
            you choosing it.
            """,
        version: KeelVersion.current,
        subcommands: [
            New.self,
            Add.self,
            Document.self,
            Inspect.self,
            Check.self,
            Doctor.self,
            AI.self,
        ]
    )
}
