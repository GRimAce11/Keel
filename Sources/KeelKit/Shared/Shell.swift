import Foundation

/// Minimal process runner for the few external commands Keel needs.
enum Shell {

    struct Result {
        let exitCode: Int32
        let standardOutput: String
        let standardError: String

        var succeeded: Bool { exitCode == 0 }
    }

    /// Runs a command and captures its output.
    ///
    /// Never throws on a non-zero exit — callers decide whether a failure
    /// matters, and for `git init` it does not.
    @discardableResult
    static func run(
        _ executable: String,
        _ arguments: [String],
        in directory: URL? = nil
    ) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        if let directory { process.currentDirectoryURL = directory }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return Result(exitCode: -1, standardOutput: "", standardError: error.localizedDescription)
        }

        // Read before waiting: a command that fills the pipe buffer deadlocks
        // if the parent waits for exit first.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Result(
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: outData, as: UTF8.self),
            standardError: String(decoding: errData, as: UTF8.self)
        )
    }

    static func isAvailable(_ executable: String) -> Bool {
        run("which", [executable]).succeeded
    }
}
