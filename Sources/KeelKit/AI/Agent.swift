import Foundation

/// An AI agent Keel knows how to talk to.
///
/// Keel recognises agents; it does not bundle, install, or require one. Every
/// core command works with none of these present, which is what keeps the AI
/// layer optional rather than load-bearing.
public struct Agent: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let vendor: String
    /// The executable Keel looks for on `PATH`.
    public let command: String
    /// Arguments for a single non-interactive prompt. The `Agent.promptToken`
    /// placeholder is replaced with the prompt text.
    public let promptArguments: [String]

    public init(
        id: String,
        name: String,
        vendor: String,
        command: String,
        promptArguments: [String]
    ) {
        self.id = id
        self.name = name
        self.vendor = vendor
        self.command = command
        self.promptArguments = promptArguments
    }

    /// Stands in for the prompt inside `promptArguments`.
    public static let promptToken = "{prompt}"

    /// Arguments with the prompt substituted in.
    public func arguments(for prompt: String) -> [String] {
        promptArguments.map {
            $0.replacingOccurrences(of: Self.promptToken, with: prompt)
        }
    }

    // MARK: - Catalogue

    /// The agents Keel recognises, with the arguments it would use to send one
    /// prompt.
    ///
    /// These invocations are Keel's best current understanding, not a promise:
    /// a CLI can change its flags in a release Keel has never seen. That is why
    /// the selected invocation is written into the config file where it can be
    /// corrected, rather than compiled in where only a new Keel could fix it.
    public static let known: [Agent] = [
        Agent(
            id: "claude",
            name: "Claude Code",
            vendor: "Anthropic",
            command: "claude",
            promptArguments: ["-p", promptToken]
        ),
        Agent(
            id: "codex",
            name: "Codex CLI",
            vendor: "OpenAI",
            command: "codex",
            promptArguments: ["exec", promptToken]
        ),
        Agent(
            id: "gemini",
            name: "Gemini CLI",
            vendor: "Google",
            command: "gemini",
            promptArguments: ["-p", promptToken]
        ),
        Agent(
            id: "ollama",
            name: "Ollama",
            vendor: "Ollama",
            command: "ollama",
            // The model is part of the invocation and every installation has a
            // different one, so this default is the likeliest to need editing.
            promptArguments: ["run", "llama3.2", promptToken]
        ),
    ]

    public static func known(id: String) -> Agent? {
        known.first { $0.id == id }
    }
}

/// An agent that is actually installed, with where it was found.
public struct DetectedAgent: Sendable, Equatable {
    public let agent: Agent
    public let path: String

    public init(agent: Agent, path: String) {
        self.agent = agent
        self.path = path
    }
}
