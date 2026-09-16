import ArgumentParser
import Foundation
import KeelKit

struct Diff: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diff",
        abstract: "Report how the architecture changed between two revisions.",
        discussion: """
            `keel check` says what is wrong with a codebase. On a project you \
            inherited that is a long list and no action. This says what \
            changed, and which of it is worse — a cycle that was not there \
            before, shared code that now depends on a feature — so it can \
            fail a pull request without failing every build.

            Your working tree is never touched. Each revision is read in a \
            temporary worktree and removed afterwards.
            """
    )

    @Argument(help: "What to compare: `main`, `main..HEAD`, or nothing for HEAD.")
    var revisions: String?

    @Argument(help: "Project directory. Defaults to the working directory.")
    var path: String?

    @Flag(name: .customLong("json"), help: "Emit the delta as JSON.")
    var asJSON = false

    func run() throws {
        let console = Console.shared
        let root = URL(fileURLWithPath: path ?? FileManager.default.currentDirectoryPath)
        let comparison = GitRevision.Comparison.parse(revisions)

        let delta: ArchitectureDelta
        do {
            delta = try compare(comparison, at: root)
        } catch let failure as GitRevision.Failure {
            console.error(failure.description)
            if let remedy = failure.remedy { console.detail(remedy) }
            throw ExitCode(2)
        } catch let error as ProjectScanner.ScanError {
            console.error(error.description)
            throw ExitCode(2)
        }

        if asJSON {
            try emitJSON(delta, comparison: comparison)
        } else {
            render(delta, comparison: comparison, console: console)
        }

        // Only a regression fails. A branch that adds a feature is not a
        // problem, and a command that said so would be turned off.
        if delta.hasRegressions { throw ExitCode.failure }
    }

    // MARK: - Comparing

    private func compare(
        _ comparison: GitRevision.Comparison,
        at root: URL
    ) throws -> ArchitectureDelta {
        let (repository, relativePath) = try GitRevision.locate(root)

        func scan(_ revision: String) throws -> ProjectModel {
            let sha = try GitRevision.resolve(revision, in: repository)
            return try GitRevision.withWorktree(sha, of: repository) { worktree in
                let directory = relativePath.isEmpty
                    ? worktree
                    : worktree.appendingPathComponent(relativePath)
                do {
                    return try ProjectScanner(root: directory).scan()
                } catch {
                    // A revision from before the project existed is a real
                    // answer, not a crash.
                    throw GitRevision.Failure.noProject(revision: revision)
                }
            }
        }

        let before = try scan(comparison.before)
        let after = try comparison.after.map(scan)
            ?? ProjectScanner(root: root).scan()

        return ArchitectureDelta(before: before, after: after)
    }

    // MARK: - Report

    private func render(
        _ delta: ArchitectureDelta,
        comparison: GitRevision.Comparison,
        console: Console
    ) {
        console.heading(comparison.label)

        guard !delta.isEmpty else {
            console.success("No architectural change.")
            return
        }

        section("Regressions", delta.regressions, glyph: .failure, console: console)
        section("Changes", delta.changes, glyph: .warn, console: console)
        section("Fixed", delta.fixed, glyph: .success, console: console)

        console.write()
        console.detail(summary(delta))
        if delta.hasRegressions {
            console.detail("Regressions fail this command. Changes and fixes do not.")
        }
    }

    private enum Glyph { case failure, warn, success }

    private func section(
        _ title: String,
        _ entries: [ArchitectureDelta.Entry],
        glyph: Glyph,
        console: Console
    ) {
        guard !entries.isEmpty else { return }
        console.heading("\(title) (\(entries.count))")

        for entry in entries {
            switch glyph {
            case .failure: console.failure(entry.headline)
            case .warn: console.warn(entry.headline)
            case .success: console.success(entry.headline)
            }
            if !entry.subject.isEmpty {
                console.paragraph(entry.subject)
            }
            // Where it came from, like every other Keel finding. A diff that
            // says a cycle appeared without saying where is one people stop
            // reading.
            for location in entry.locations {
                console.detail("  \(location)")
            }
        }
    }

    private func summary(_ delta: ArchitectureDelta) -> String {
        [
            count(delta.regressions.count, "regression"),
            count(delta.changes.count, "change"),
            "\(delta.fixed.count) fixed",
        ].joined(separator: ", ") + "."
    }

    private func count(_ number: Int, _ singular: String) -> String {
        "\(number) \(singular)\(number == 1 ? "" : "s")"
    }

    // MARK: - JSON

    private func emitJSON(
        _ delta: ArchitectureDelta,
        comparison: GitRevision.Comparison
    ) throws {
        struct Payload: Encodable {
            struct Item: Encodable {
                let standing: String
                let headline: String
                let subject: String
                let locations: [String]
            }
            let before: String
            let after: String
            let regressions: Int
            let entries: [Item]
        }

        let payload = Payload(
            before: comparison.before,
            after: comparison.after ?? "working tree",
            regressions: delta.regressions.count,
            entries: delta.entries.map {
                .init(
                    standing: $0.standing.rawValue,
                    headline: $0.headline,
                    subject: $0.subject,
                    locations: $0.locations
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(payload), as: UTF8.self))
    }
}
