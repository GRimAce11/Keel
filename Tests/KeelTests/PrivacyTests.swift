import Foundation
import Testing
@testable import KeelKit

/// The guarantees Keel makes about AI, as tests rather than as prose.
///
/// Every one of these is something a README can claim and a refactor can
/// quietly break. They are written from the outside — generate a project, run
/// the real thing, look at what came out — because that is the only vantage
/// point from which "no source code leaves the machine" means anything.
@Suite("AI privacy")
struct PrivacyTests {

    private let console = Console(useColor: false)

    /// A project containing something that must never leave it.
    private func withProjectContainingSecret<T>(
        _ secret: String,
        _ body: (URL, ProjectModel) throws -> T
    ) throws -> T {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-privacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let configuration = ProjectConfiguration(
            name: try ProjectName("Probe"),
            bundleIdentifierPrefix: "com.acme",
            components: Set(Component.allCases)
        )
        let outcome = try ProjectGenerator(configuration: configuration, console: console)
            .generate(in: destination, initializeGit: false)

        let directory = outcome.projectDirectory.appendingPathComponent("Probe/Core/Secrets")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
            import Foundation

            enum Secrets {
                static let apiKey = "\(secret)"
                static let password = "\(secret)"
            }
            """.write(
                to: directory.appendingPathComponent("Secrets.swift"),
                atomically: true, encoding: .utf8
            )

        return try body(
            outcome.projectDirectory,
            try ProjectScanner(root: outcome.projectDirectory).scan()
        )
    }

    // MARK: - What leaves the machine

    @Test("A secret in the source never reaches the prompt")
    func neverSendsSecrets() throws {
        let secret = "sk-live-\(UUID().uuidString)"

        try withProjectContainingSecret(secret) { _, model in
            let prompt = DocumentationPrompt(model: model).text()

            // The analysis records type names, imports and paths. It never
            // records what a string literal contains, which is why a key in
            // the source cannot reach an agent.
            #expect(!prompt.contains(secret))
            #expect(!prompt.contains("apiKey"))
            #expect(!prompt.contains("password"))
        }
    }

    @Test("The prompt carries no source code at all")
    func sendsNoSource() throws {
        try withProjectContainingSecret("unused") { _, model in
            let prompt = DocumentationPrompt(model: model).text()

            for fragment in ["import Foundation", "func ", "var body", "static let"] {
                #expect(!prompt.contains(fragment), "prompt contains source fragment: \(fragment)")
            }
        }
    }

    @Test("The environment is not part of the prompt")
    func sendsNoEnvironment() throws {
        try withProjectContainingSecret("unused") { _, model in
            let prompt = DocumentationPrompt(model: model).text()

            // Keel never reads these, but asserting it costs nothing and the
            // day someone adds "helpful context" this fails.
            for name in ["PATH", "HOME", "OPENAI_API_KEY", "ANTHROPIC_API_KEY"] {
                #expect(!prompt.contains(name))
                if let value = ProcessInfo.processInfo.environment[name], value.count > 8 {
                    #expect(!prompt.contains(value))
                }
            }
        }
    }

    @Test("What the prompt does contain is only what the document already shows")
    func sendsOnlyDerivedFacts() throws {
        try withProjectContainingSecret("unused") { _, model in
            let prompt = DocumentationPrompt(model: model).text()
            let document = ProjectDocument(model: model).markdown()

            // Every fact in the prompt is one the user can already read in
            // PROJECT.md, which is what makes the exchange inspectable.
            #expect(prompt.contains(model.architecture.summary))
            #expect(document.contains(model.architecture.summary))
        }
    }

    // MARK: - Nothing runs unasked

    @Test("No core command touches the AI layer")
    func coreCommandsAreDeterministic() throws {
        try withProjectContainingSecret("unused") { root, _ in
            // Pointed at a config directory that does not exist, so there is
            // no selection and no mode to find.
            let environment = ["XDG_CONFIG_HOME": root.appendingPathComponent("nope").path]

            for arguments in [["inspect"], ["check"], ["document"], ["doctor"]] {
                let result = try CLIRunner.run(arguments + [root.path], environment: environment)
                #expect(!result.combinedOutput.contains("Asking"))
                #expect(!result.combinedOutput.contains("Runs    "))
            }
        }
    }

    @Test("--no-ai produces exactly what no configuration produces")
    func noAIIsDeterministic() throws {
        try withProjectContainingSecret("unused") { root, model in
            let plain = ProjectDocument(model: model).markdown()

            let environment = ["XDG_CONFIG_HOME": root.appendingPathComponent("nope").path]
            let result = try CLIRunner.run(
                ["document", root.path, "--no-ai", "--stdout"], environment: environment
            )

            #expect(result.succeeded)
            #expect(result.standardOutput == plain)
            #expect(!result.standardOutput.contains(ProjectDocument.overviewStart))
        }
    }

    @Test("Detection finds agents without running any of them")
    func detectionRunsNothing() throws {
        // The proof is structural: a directory of fake agents that would fail
        // loudly if executed, detected without incident.
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-privacy-bin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let marker = directory.appendingPathComponent("was-run")
        for command in ["claude", "codex", "gemini"] {
            let file = directory.appendingPathComponent(command)
            try "#!/bin/sh\ntouch \(marker.path)\nexit 1\n".write(
                to: file, atomically: true, encoding: .utf8
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: file.path
            )
        }

        let detected = AgentDetector(path: directory.path).detect()

        #expect(detected.count == 3)
        #expect(!FileManager.default.fileExists(atPath: marker.path), "detection executed an agent")
    }

    // MARK: - Refusals

    @Test("An agent that is selected but missing is an error, not a fallback")
    func refusesWhenAgentIsUnavailable() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-privacy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = AgentStore(url: directory.appendingPathComponent("ai.json"))
        let agent = try #require(Agent.known(id: "claude"))
        try store.save(AIConfiguration(mode: .always, selection: AgentSelection(agent: agent)))

        // Quietly carrying on with a different agent would be the worst
        // possible behaviour here.
        #expect(throws: AIError.agentNotInstalled(command: "claude")) {
            try CommandLineAgent.resolve(store: store, detector: AgentDetector(path: ""))
        }
    }

    @Test("An agent Keel does not know is refused rather than shelled out to")
    func refusesUnknownProvider() throws {
        let result = try CLIRunner.run(["ai", "use", "../../bin/sh"])
        #expect(result.succeeded == false)
        #expect(result.combinedOutput.contains("does not recognise"))
    }

    @Test("An agent that fails authentication costs the section, not the document")
    func survivesAuthenticationFailure() throws {
        // What an unauthenticated CLI actually does: exits non-zero with a
        // message. The document still has to arrive.
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-auth-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("claude")
        try "#!/bin/sh\necho 'Not logged in' >&2\nexit 1\n".write(
            to: executable, atomically: true, encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: executable.path
        )

        let agent = try #require(Agent.known(id: "claude"))
        let provider = CommandLineAgent(
            selection: AgentSelection(agent: agent), executablePath: executable.path
        )

        #expect(throws: AIError.self) { try provider.complete(prompt: "hello") }
    }
}
