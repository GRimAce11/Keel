import ArgumentParser
import Foundation
import KeelKit

/// Commands that are declared but not built yet.
///
/// They are present from the first release so `keel --help` describes the whole
/// tool rather than only the part that exists today. Each one exits non-zero
/// with a specific message — a command that silently does nothing is worse
/// than one that says it cannot.
enum Unimplemented {
    static func report(_ command: String, _ summary: String) throws -> Never {
        let console = Console.shared
        console.error("`keel \(command)` is not implemented yet.")
        console.detail(summary)
        throw ExitCode.failure
    }
}

struct Check: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Validate a project against its architecture rules."
    )

    func run() throws {
        try Unimplemented.report(
            "check",
            "It will verify things like ViewModels being @MainActor and Views not calling networking directly."
        )
    }
}

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Diagnose the toolchain and the project in the working directory."
    )

    func run() throws {
        try Unimplemented.report(
            "doctor",
            "It will check Xcode, Swift, the iOS SDK, and project integrity."
        )
    }
}
