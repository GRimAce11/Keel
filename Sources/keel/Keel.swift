import ArgumentParser
import KeelKit

@main
struct Keel: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keel",
        abstract: "Understand an iOS codebase you did not write — from the terminal.",
        discussion: """
            keel reads an iOS project and reports what it is made of — which \
            features depend on which, which boundaries the project keeps, and \
            where it breaks its own rules — with the file and line behind \
            every claim. No build, no network, and no AI unless you choose it.

            It creates projects too, with `keel new`. But the reason to reach \
            for keel is the codebase you already have — start with `keel \
            explore` if you are not sure which command you want.
            """,
        version: KeelVersion.current,
        // Ordered the way the README lists them: what you reach for on a
        // codebase you inherited first, and creating one last.
        subcommands: [
            Explore.self,
            Inspect.self,
            Check.self,
            Diff.self,
            Document.self,
            Doctor.self,
            New.self,
            Add.self,
            AI.self,
        ]
    )
}
