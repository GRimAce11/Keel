import Foundation
import Testing
@testable import KeelKit

/// Drives the real `keel` binary.
///
/// The CLI surface — exit codes, `--help`, how an unknown option is rejected —
/// is behaviour users depend on, and it lives in ArgumentParser rather than in
/// any type we could call directly. Launching the built executable is the only
/// way to test it honestly.
struct CLIRunner {

    struct Result {
        let exitCode: Int32
        let standardOutput: String
        let standardError: String

        var combinedOutput: String { standardOutput + standardError }
        var succeeded: Bool { exitCode == 0 }
    }

    /// The package root, derived from this file's own location.
    ///
    /// `Bundle.main` is not usable here: Swift Testing does not necessarily run
    /// inside an `.xctest` bundle, and when it does not, `Bundle.main` points
    /// at the toolchain's test runner rather than at the build products.
    static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)      // Tests/KeelTests/CLITests.swift
            .deletingLastPathComponent()     // Tests/KeelTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // package root
    }

    static var executable: URL {
        let buildDirectory = packageRoot.appendingPathComponent(".build")
        // Whichever configuration was built most recently is the one under test.
        let candidates = ["debug", "release"]
            .map { buildDirectory.appendingPathComponent($0).appendingPathComponent("keel") }
            .filter { FileManager.default.isExecutableFile(atPath: $0.path) }

        return candidates.max { left, right in
            modificationDate(of: left) < modificationDate(of: right)
        } ?? buildDirectory.appendingPathComponent("debug/keel")
    }

    private static func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    @discardableResult
    static func run(_ arguments: [String]) throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Result(
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: outData, as: UTF8.self),
            standardError: String(decoding: errData, as: UTF8.self)
        )
    }
}

@Suite("CLI")
struct CLITests {

    @Test("The binary was built and is executable")
    func binaryExists() {
        #expect(FileManager.default.isExecutableFile(atPath: CLIRunner.executable.path))
    }

    @Test("--version reports the package version")
    func reportsVersion() throws {
        let result = try CLIRunner.run(["--version"])
        #expect(result.succeeded)
        #expect(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == KeelVersion.current)
    }

    @Test("--help lists every command")
    func helpListsCommands() throws {
        let result = try CLIRunner.run(["--help"])
        #expect(result.succeeded)

        // Every command is advertised from the first release, so `--help`
        // describes the whole tool rather than only the finished parts.
        for command in ["new", "document", "inspect", "check", "doctor", "ai"] {
            #expect(result.combinedOutput.contains(command), "help should mention \(command)")
        }
    }

    @Test("Running with no arguments prints help rather than failing silently")
    func noArgumentsShowsHelp() throws {
        let result = try CLIRunner.run([])
        #expect(result.combinedOutput.contains("USAGE"))
    }

    @Test("An unknown command is rejected")
    func rejectsUnknownCommand() throws {
        let result = try CLIRunner.run(["frobnicate"])
        #expect(result.succeeded == false)
    }

    @Test("An unknown option is rejected")
    func rejectsUnknownOption() throws {
        let result = try CLIRunner.run(["new", "MyApp", "--not-a-real-option"])
        #expect(result.succeeded == false)
        #expect(result.combinedOutput.lowercased().contains("unknown"))
    }

    @Test(
        "Unimplemented commands exit non-zero and say so",
        arguments: ["document", "inspect", "check", "doctor", "ai"]
    )
    func unimplementedCommandsReportClearly(command: String) throws {
        let result = try CLIRunner.run([command])
        // Exiting zero would let a CI pipeline "pass" a step that did nothing.
        #expect(result.succeeded == false)
        #expect(result.combinedOutput.contains("not implemented"))
    }
}

@Suite("KeelVersion")
struct KeelVersionTests {

    @Test("Version is a three-part semantic version")
    func versionIsSemantic() {
        let parts = KeelVersion.current.split(separator: ".")
        #expect(parts.count == 3)
        #expect(parts.allSatisfy { Int($0) != nil })
    }
}
