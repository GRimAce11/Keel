import Foundation

/// Finds which known agents are installed, by looking at `PATH`.
///
/// Nothing here executes anything. Detection reads directory entries and
/// checks the executable bit — it never runs `which`, and never runs the agent
/// itself, not even for a version string. Keel is allowed to notice that an
/// agent exists; running one is a separate act that only happens when asked.
public struct AgentDetector {

    /// Directories to search, in `PATH` order.
    public let searchPaths: [String]

    /// Reads `PATH` from the environment. Injectable so tests can search a
    /// directory they control rather than whatever the machine happens to have.
    public init(path: String? = nil) {
        let raw = path ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
        searchPaths = raw.split(separator: ":").map(String.init).filter { !$0.isEmpty }
    }

    /// Every known agent that is installed, in catalogue order.
    public func detect(among agents: [Agent] = Agent.known) -> [DetectedAgent] {
        agents.compactMap { agent in
            locate(agent.command).map { DetectedAgent(agent: agent, path: $0) }
        }
    }

    /// The first executable on `PATH` with this name.
    public func locate(_ command: String) -> String? {
        let fileManager = FileManager.default
        for directory in searchPaths {
            let candidate = (directory as NSString).appendingPathComponent(command)
            if fileManager.isExecutableFile(atPath: candidate) {
                // A directory can carry the executable bit; only a file runs.
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory),
                      !isDirectory.boolValue
                else { continue }
                return candidate
            }
        }
        return nil
    }
}
