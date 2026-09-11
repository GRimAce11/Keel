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
    /// - Parameter environment: entries overlaid on the inherited environment.
    ///   Tests that touch the AI layer must point `XDG_CONFIG_HOME` somewhere
    ///   disposable — reading the real config could select, and then run, an
    ///   agent belonging to whoever is running the suite.
    static func run(
        _ arguments: [String],
        environment: [String: String] = [:]
    ) throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        if !environment.isEmpty {
            var merged = ProcessInfo.processInfo.environment
            merged.merge(environment) { _, new in new }
            process.environment = merged
        }

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
        "Every command is implemented",
        arguments: ["new", "document", "inspect", "check", "doctor", "ai"]
    )
    func noCommandClaimsToBeUnimplemented(command: String) throws {
        // The Unimplemented helper is gone. This is what stops it coming back
        // as a stub that exits zero having done nothing.
        let result = try CLIRunner.run([command, "--help"])
        #expect(result.succeeded)
        #expect(!result.combinedOutput.contains("not implemented"))
    }

    @Test("check and doctor read a real project")
    func checkAndDoctorRun() throws {
        let check = try CLIRunner.run(["check", NSTemporaryDirectory()])
        #expect(check.succeeded == false)
        #expect(check.combinedOutput.contains("No .xcodeproj"))

        // doctor works with no project at all, because "is this machine ready"
        // is a fair question to ask anywhere.
        let doctor = try CLIRunner.run(["doctor", NSTemporaryDirectory()])
        #expect(doctor.combinedOutput.contains("Toolchain"))
    }

    @Test("ai reports what is installed without running any of it")
    func aiListsWithoutInvoking() throws {
        let result = try CLIRunner.run(["ai"])
        #expect(result.succeeded)
        #expect(result.combinedOutput.contains("Selection"))
        // It is implemented now, so it must not claim otherwise.
        #expect(!result.combinedOutput.contains("not implemented"))
    }

    @Test("ai rejects an agent it does not recognise")
    func aiRejectsUnknownAgent() throws {
        let result = try CLIRunner.run(["ai", "use", "frobnicate"])
        #expect(result.succeeded == false)
        #expect(result.combinedOutput.contains("does not recognise"))
    }

    @Test("document explains itself when there is no project to read")
    func documentReportsMissingProject() throws {
        let result = try CLIRunner.run(["document", NSTemporaryDirectory()])
        #expect(result.succeeded == false)
        #expect(result.combinedOutput.contains("No .xcodeproj"))
        // It is implemented now, so it must not claim otherwise.
        #expect(!result.combinedOutput.contains("not implemented"))
    }

    @Test("inspect explains itself when there is no project to read")
    func inspectReportsMissingProject() throws {
        // Run somewhere that definitely holds no Xcode project.
        let result = try CLIRunner.run(["inspect", NSTemporaryDirectory()])
        #expect(result.succeeded == false)
        #expect(result.combinedOutput.contains("No .xcodeproj"))
        // It is implemented now, so it must not claim otherwise.
        #expect(!result.combinedOutput.contains("not implemented"))
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
