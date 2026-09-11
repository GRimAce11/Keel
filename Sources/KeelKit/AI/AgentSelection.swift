import Foundation

/// The agent Keel has been told it may use, and exactly how to run it.
///
/// The invocation is stored rather than looked up, for two reasons. It is the
/// thing `keel ai` prints, so what Keel says it will run is read from the same
/// place as what it runs. And when an agent changes its flags, the fix is
/// editing one file instead of waiting for a Keel release.
public struct AgentSelection: Codable, Sendable, Equatable {
    public let agentID: String
    public let command: String
    public let arguments: [String]

    public init(agentID: String, command: String, arguments: [String]) {
        self.agentID = agentID
        self.command = command
        self.arguments = arguments
    }

    public init(agent: Agent) {
        self.init(
            agentID: agent.id,
            command: agent.command,
            arguments: agent.promptArguments
        )
    }

    /// The command line as a person would type it, for display.
    public var displayCommand: String {
        ([command] + arguments)
            .map { $0.contains(" ") ? "\"\($0)\"" : $0 }
            .joined(separator: " ")
    }
}

/// Where the selection lives on disk.
///
/// User-level rather than per-project: which agents are installed is a fact
/// about the machine, and nobody wants to re-choose in every repository. It is
/// a plain JSON file in a documented location precisely so it can be read,
/// edited and deleted without Keel's help.
public struct AgentStore {

    public let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL()
    }

    public static func defaultURL() -> URL {
        let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        return base
            .appendingPathComponent("keel", isDirectory: true)
            .appendingPathComponent("ai.json")
    }

    /// The stored selection, or `nil` when none was made.
    ///
    /// A malformed file reads as "no selection" rather than as an error. The
    /// default is always Keel alone, so the safe reading of a file Keel cannot
    /// parse is that no agent was chosen.
    public func load() -> AgentSelection? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AgentSelection.self, from: data)
    }

    public func save(_ selection: AgentSelection) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(selection).write(to: url, options: .atomic)
    }

    /// Forgets the selection. Removing the file is the whole operation: absent
    /// means "Keel alone", which is also what a fresh install means.
    public func clear() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
