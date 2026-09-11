import Foundation

/// When Keel may use the agent it has been given.
///
/// Separate from *which* agent, because the two questions have different
/// answers: having an agent installed and selected says nothing about whether
/// you want it used without being asked.
public enum AIMode: String, Codable, Sendable, Equatable, CaseIterable {
    /// Never, unless a flag on this run says otherwise. The default.
    case never
    /// Ask, when there is someone there to ask.
    case ask
    /// Use it without asking. Only ever set deliberately.
    case always

    /// How much permission each mode grants, so two sources can be combined by
    /// taking the more restrictive.
    var permissiveness: Int {
        switch self {
        case .never: return 0
        case .ask: return 1
        case .always: return 2
        }
    }

    public var displayName: String {
        switch self {
        case .never: return "never — Keel alone unless --ai is passed"
        case .ask: return "ask — Keel asks before using an agent"
        case .always: return "always — Keel uses the selected agent"
        }
    }
}

// MARK: - Stored configuration

/// What the user has configured, at user level.
public struct AIConfiguration: Codable, Sendable, Equatable {
    public var mode: AIMode
    public var selection: AgentSelection?

    public init(mode: AIMode = .never, selection: AgentSelection? = nil) {
        self.mode = mode
        self.selection = selection
    }

    /// Reads the current shape, and the shape Keel wrote before modes existed.
    ///
    /// An older file holds a bare selection with no mode. Reading it as
    /// `never` is the safe interpretation: choosing an agent was never
    /// permission to use it unasked.
    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           container.contains(.mode) {
            mode = try container.decode(AIMode.self, forKey: .mode)
            selection = try container.decodeIfPresent(AgentSelection.self, forKey: .selection)
            return
        }
        mode = .never
        selection = try? AgentSelection(from: decoder)
    }
}

// MARK: - Project configuration

/// What a repository asks for, read from `.keel/config.json`.
///
/// A project may only ever *restrict*. Cloning someone's repository must not
/// hand their configuration permission to run an agent on your machine, so a
/// project asking for `always` is combined with the user's setting by taking
/// the more restrictive of the two.
public struct ProjectAIConfiguration: Codable, Sendable, Equatable {
    public let mode: AIMode?

    public init(mode: AIMode?) {
        self.mode = mode
    }

    public static let fileName = ".keel/config.json"

    public static func load(from root: URL) -> ProjectAIConfiguration? {
        let url = root.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        struct File: Decodable { let ai: ProjectAIConfiguration? }
        return (try? JSONDecoder().decode(File.self, from: data))?.ai
    }
}

// MARK: - Resolution

/// The decision, once every source has had its say.
public struct AIPolicy: Sendable, Equatable {
    public let mode: AIMode
    public let selection: AgentSelection?
    /// Set when a project asked for less than the user allows, so the reason
    /// can be shown rather than the difference being silent.
    public let restrictedByProject: Bool

    public init(mode: AIMode, selection: AgentSelection?, restrictedByProject: Bool = false) {
        self.mode = mode
        self.selection = selection
        self.restrictedByProject = restrictedByProject
    }

    public static func resolve(
        configuration: AIConfiguration,
        project: ProjectAIConfiguration? = nil
    ) -> AIPolicy {
        guard let requested = project?.mode else {
            return AIPolicy(mode: configuration.mode, selection: configuration.selection)
        }

        // The more restrictive wins, always.
        let effective = requested.permissiveness < configuration.mode.permissiveness
            ? requested
            : configuration.mode

        return AIPolicy(
            mode: effective,
            selection: configuration.selection,
            restrictedByProject: effective != configuration.mode
        )
    }
}
