import Foundation
import Testing
@testable import KeelKit

/// Detection and invocation are tested against fake executables in a temporary
/// directory.
///
/// Pointing tests at whatever agents happen to be installed would make them
/// pass or fail on a property of the machine, and running a real agent would
/// spend someone's quota to assert a string.
@Suite("AgentDetector")
struct AgentDetectorTests {

    /// A directory holding executables with the given names.
    private func withFakeBin<T>(_ commands: [String], _ body: (String) throws -> T) throws -> T {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-bin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for command in commands {
            let file = directory.appendingPathComponent(command)
            try "#!/bin/sh\necho ok\n".write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: file.path
            )
        }
        return try body(directory.path)
    }

    @Test("Finds installed agents and reports where they are")
    func findsInstalledAgents() throws {
        try withFakeBin(["claude", "gemini"]) { bin in
            let detected = AgentDetector(path: bin).detect()

            #expect(detected.map(\.agent.id) == ["claude", "gemini"])
            #expect(detected.first?.path == "\(bin)/claude")
        }
    }

    @Test("An agent that is not installed is simply absent")
    func omitsMissingAgents() throws {
        try withFakeBin(["claude"]) { bin in
            let detected = AgentDetector(path: bin).detect()
            #expect(!detected.contains { $0.agent.id == "codex" })
        }
    }

    @Test("Nothing is detected on an empty PATH")
    func detectsNothingWithoutPath() {
        #expect(AgentDetector(path: "").detect().isEmpty)
        #expect(AgentDetector(path: "/nonexistent-\(UUID().uuidString)").detect().isEmpty)
    }

    @Test("A directory named like an agent is not mistaken for one")
    func ignoresDirectories() throws {
        // Directories carry the executable bit, so the name alone is not enough.
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-bin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("claude"), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(AgentDetector(path: root.path).locate("claude") == nil)
    }

    @Test("Earlier PATH entries win, as the shell would resolve them")
    func respectsPathOrder() throws {
        try withFakeBin(["claude"]) { first in
            try withFakeBin(["claude"]) { second in
                let detector = AgentDetector(path: "\(first):\(second)")
                #expect(detector.locate("claude") == "\(first)/claude")
            }
        }
    }
}

// MARK: - Selection

@Suite("AgentSelection")
struct AgentSelectionTests {

    private func withStore<T>(_ body: (AgentStore) throws -> T) throws -> T {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-ai-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        return try body(AgentStore(url: directory.appendingPathComponent("ai.json")))
    }

    @Test("A selection round-trips through the config file")
    func roundTrips() throws {
        try withStore { store in
            #expect(store.load() == nil)

            let agent = try #require(Agent.known(id: "claude"))
            let selection = AgentSelection(agent: agent)
            try store.save(selection)

            #expect(store.load() == selection)
        }
    }

    @Test("Clearing removes the file, which is what absent means")
    func clears() throws {
        try withStore { store in
            let agent = try #require(Agent.known(id: "codex"))
            try store.save(AgentSelection(agent: agent))
            try store.clear()

            #expect(store.load() == nil)
            #expect(!FileManager.default.fileExists(atPath: store.url.path))
            // Clearing twice is not an error; the end state is the same.
            try store.clear()
        }
    }

    @Test("A config file Keel cannot parse reads as no selection")
    func treatsGarbageAsNoSelection() throws {
        try withStore { store in
            try FileManager.default.createDirectory(
                at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try "not json".write(to: store.url, atomically: true, encoding: .utf8)

            // The safe reading of an unparseable file is that nothing was
            // chosen — the default is always Keel alone.
            #expect(store.load() == nil)
        }
    }

    @Test("The stored invocation is the one shown and the one run")
    func invocationIsSingleSourced() throws {
        let agent = try #require(Agent.known(id: "claude"))
        let selection = AgentSelection(agent: agent)

        #expect(selection.displayCommand == "claude -p {prompt}")
        #expect(selection.arguments(replacing: "hello") == ["-p", "hello"])
    }

    @Test("A prompt with spaces is quoted for display but passed as one argument")
    func handlesPromptsWithSpaces() throws {
        let agent = try #require(Agent.known(id: "gemini"))
        let selection = AgentSelection(agent: agent)

        // One argument, not split on whitespace — the process is spawned
        // directly, so there is no shell to re-split it.
        #expect(selection.arguments(replacing: "two words") == ["-p", "two words"])
    }
}

// MARK: - Provider

@Suite("CommandLineAgent")
struct CommandLineAgentTests {

    /// A fake agent whose behaviour the test chooses.
    private func withFakeAgent<T>(
        script: String,
        _ body: (CommandLineAgent) throws -> T
    ) throws -> T {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-agent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("claude")
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: executable.path
        )

        let agent = try #require(Agent.known(id: "claude"))
        return try body(
            CommandLineAgent(
                selection: AgentSelection(agent: agent),
                executablePath: executable.path
            )
        )
    }

    @Test("The prompt reaches the agent and its answer comes back")
    func passesThePromptThrough() throws {
        // Echoing the last argument proves the prompt arrived intact rather
        // than as the literal placeholder.
        try withFakeAgent(script: "#!/bin/sh\necho \"$2\"\n") { provider in
            let answer = try provider.complete(prompt: "say this back")
            #expect(answer == "say this back")
        }
    }

    @Test("A failing agent is reported with its exit code and message")
    func reportsFailure() throws {
        try withFakeAgent(script: "#!/bin/sh\necho 'rate limited' >&2\nexit 7\n") { provider in
            #expect(throws: AIError.agentFailed(
                command: "claude", exitCode: 7, message: "rate limited"
            )) {
                try provider.complete(prompt: "hello")
            }
        }
    }

    @Test("An agent that says nothing is a failure, not an empty answer")
    func reportsEmptyResponse() throws {
        try withFakeAgent(script: "#!/bin/sh\nexit 0\n") { provider in
            #expect(throws: AIError.emptyResponse(command: "claude")) {
                try provider.complete(prompt: "hello")
            }
        }
    }

    @Test("Resolving without a selection refuses rather than picking one")
    func refusesToChooseForYou() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-ai-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AgentStore(url: directory.appendingPathComponent("ai.json"))

        // An installed agent is not a selected one. This is the rule the whole
        // AI layer rests on: detection never implies permission.
        #expect(throws: AIError.noAgentSelected) {
            try CommandLineAgent.resolve(store: store, detector: AgentDetector())
        }
    }

    @Test("A selection whose agent has been uninstalled says so")
    func reportsUninstalledAgent() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-ai-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = AgentStore(url: directory.appendingPathComponent("ai.json"))
        let agent = try #require(Agent.known(id: "claude"))
        try store.save(AgentSelection(agent: agent))

        #expect(throws: AIError.agentNotInstalled(command: "claude")) {
            try CommandLineAgent.resolve(store: store, detector: AgentDetector(path: ""))
        }
    }
}

// MARK: - Catalogue

@Suite("Agent catalogue")
struct AgentCatalogueTests {

    @Test("Every known agent can be looked up by its id")
    func idsResolve() {
        for agent in Agent.known {
            #expect(Agent.known(id: agent.id) == agent)
        }
        #expect(Agent.known(id: "frobnicate") == nil)
    }

    @Test("Every known agent has somewhere to put the prompt")
    func everyAgentTakesAPrompt() {
        // An invocation with no placeholder would send the agent an empty
        // request and look like the agent had ignored it.
        for agent in Agent.known {
            #expect(
                agent.promptArguments.contains { $0.contains(Agent.promptToken) },
                "\(agent.id) has no \(Agent.promptToken) placeholder"
            )
            #expect(agent.arguments(for: "x").contains("x"), "\(agent.id) drops the prompt")
        }
    }

    @Test("Ids are unique, since they are what selection is keyed on")
    func idsAreUnique() {
        #expect(Set(Agent.known.map(\.id)).count == Agent.known.count)
    }
}
