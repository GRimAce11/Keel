import Foundation

/// Something Keel can send one prompt to and read one answer from.
///
/// Deliberately this small. Keel's AI layer interprets facts the deterministic
/// core already established — it does not need streaming, tools, or a
/// conversation, and every capability this protocol does not have is one no
/// future command can quietly come to depend on.
public protocol AIProvider: Sendable {
    /// Exactly what running this provider will execute, for showing a person
    /// before anything runs.
    var invocation: String { get }

    func complete(prompt: String) throws -> String
}

public enum AIError: Error, CustomStringConvertible, Equatable {
    case noAgentSelected
    case agentNotInstalled(command: String)
    case agentFailed(command: String, exitCode: Int32, message: String)
    case emptyResponse(command: String)

    public var description: String {
        switch self {
        case .noAgentSelected:
            return """
                No AI agent is selected. Run `keel ai` to see what is installed, \
                then `keel ai use <id>` to choose one.
                """
        case .agentNotInstalled(let command):
            return "`\(command)` is not on your PATH. It may have been uninstalled since it was selected."
        case .agentFailed(let command, let exitCode, let message):
            let detail = message.isEmpty ? "" : "\n\(message)"
            return "`\(command)` exited \(exitCode).\(detail)"
        case .emptyResponse(let command):
            return "`\(command)` ran but returned nothing."
        }
    }
}

/// Runs a locally installed agent as a subprocess.
///
/// The only implementation Keel ships, and it never runs on its own: something
/// has to hand it a prompt, and the only things that do are commands a person
/// typed.
public struct CommandLineAgent: AIProvider {

    public let selection: AgentSelection
    /// The resolved executable, so invocation does not depend on `PATH` being
    /// the same as it was when the agent was detected.
    public let executablePath: String

    public init(selection: AgentSelection, executablePath: String) {
        self.selection = selection
        self.executablePath = executablePath
    }

    /// Builds a provider for the stored selection, or explains why it cannot.
    public static func resolve(
        store: AgentStore = AgentStore(),
        detector: AgentDetector = AgentDetector()
    ) throws -> CommandLineAgent {
        guard let selection = store.load() else { throw AIError.noAgentSelected }
        guard let path = detector.locate(selection.command) else {
            throw AIError.agentNotInstalled(command: selection.command)
        }
        return CommandLineAgent(selection: selection, executablePath: path)
    }

    public var invocation: String { selection.displayCommand }

    public func complete(prompt: String) throws -> String {
        let result = Shell.run(executablePath, selection.arguments(replacing: prompt))

        guard result.succeeded else {
            throw AIError.agentFailed(
                command: selection.command,
                exitCode: result.exitCode,
                message: result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let answer = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw AIError.emptyResponse(command: selection.command) }
        return answer
    }
}

extension AgentSelection {
    /// Arguments with the prompt placeholder filled in.
    func arguments(replacing prompt: String) -> [String] {
        arguments.map { $0.replacingOccurrences(of: Agent.promptToken, with: prompt) }
    }
}
