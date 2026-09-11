import ArgumentParser
import Foundation
import KeelKit

struct AI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ai",
        abstract: "Inspect and choose which local AI agent Keel may use.",
        discussion: """
            Keel detects agents that are already installed. It never runs one \
            because it happens to exist: an agent is invoked only by a command \
            you typed, and only after you have selected it. Every core command \
            works with no agent at all.
            """,
        subcommands: [Show.self, List.self, Use.self, Mode.self, Forget.self, Verify.self],
        defaultSubcommand: Show.self
    )
}

// MARK: - Show

extension AI {
    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "List detected agents and the current selection."
        )

        func run() throws {
            let console = Console.shared
            let store = AgentStore()
            let detected = AgentDetector().detect()

            console.heading("Agents")
            console.detail("Keel runs none of these unless you ask it to.")
            console.detail("")

            if detected.isEmpty {
                console.detail("None of the agents Keel recognises is installed.")
            } else {
                let verified = store.load().verified
                let nameWidth = detected.map(\.agent.name.count).max() ?? 0
                let idWidth = detected.map(\.agent.id.count).max() ?? 0
                for found in detected {
                    let name = found.agent.name.padding(
                        toLength: max(nameWidth, 1), withPad: " ", startingAt: 0
                    )
                    let id = found.agent.id.padding(
                        toLength: max(idWidth, 1), withPad: " ", startingAt: 0
                    )
                    // "installed" and "works" are different claims, and Keel
                    // only knows the second one if it has been shown.
                    let readiness = verified[found.agent.id] == nil
                        ? "not verified"
                        : "verified"
                    console.detail("\(name)  \(id)  \(readiness)")
                    console.detail("\(String(repeating: " ", count: nameWidth + idWidth + 4))\(found.path)")
                }
            }

            let missing = Agent.known.filter { known in
                !detected.contains { $0.agent.id == known.id }
            }
            if !missing.isEmpty {
                console.detail("")
                console.detail("Not installed: \(missing.map(\.id).joined(separator: ", "))")
            }

            renderSelection(store: store, detected: detected, console: console)
        }

        private func renderSelection(
            store: AgentStore,
            detected: [DetectedAgent],
            console: Console
        ) {
            let configuration = store.load()
            let policy = AIPolicy.resolve(
                configuration: configuration,
                project: ProjectAIConfiguration.load(
                    from: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                )
            )

            console.heading("Selection")

            guard let selection = configuration.selection else {
                console.detail("None. Keel works alone, which is the default.")
                console.detail("Choose one with `keel ai use <id>`.")
                console.detail("")
                console.detail("Config  \(store.url.path) (not written yet)")
                return
            }

            let name = Agent.known(id: selection.agentID)?.name ?? selection.agentID
            console.detail("Agent   \(name)")
            // Printed from the same field that is executed, so this cannot
            // describe one command while running another.
            console.detail("Runs    \(selection.displayCommand)")
            console.detail("When    \(policy.mode.displayName)")
            console.detail("Config  \(store.url.path)")

            if policy.restrictedByProject {
                console.detail("")
                console.detail(
                    "This project's \(ProjectAIConfiguration.fileName) asks for less than your "
                    + "setting, and a project may only ever restrict."
                )
            }

            if !detected.contains(where: { $0.agent.id == selection.agentID }) {
                console.warn(
                    "\(selection.command) is selected but not on your PATH. "
                    + "Reinstall it, or run `keel ai forget`."
                )
            }
        }
    }
}

// MARK: - List

extension AI {
    /// `keel ai list` is what the plan names; `show` is the default
    /// subcommand. They are the same report rather than two views that could
    /// drift.
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List detected agents and the current selection."
        )

        func run() throws { try Show().run() }
    }
}

// MARK: - Mode

extension AI {
    struct Mode: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "mode",
            abstract: "Set when Keel may use the selected agent.",
            discussion: """
                never (the default) keeps Keel alone unless --ai is passed on a \
                run. ask means Keel asks first, when there is someone there to \
                ask. always means it goes ahead. A project may lower this, never \
                raise it.
                """
        )

        @Argument(help: "never, ask, or always.")
        var mode: String

        func run() throws {
            let console = Console.shared

            guard let value = AIMode(rawValue: mode.lowercased()) else {
                console.error("`\(mode)` is not a mode.")
                console.detail("Known: \(AIMode.allCases.map(\.rawValue).joined(separator: ", "))")
                throw ExitCode.failure
            }

            let store = AgentStore()
            var configuration = store.load()
            configuration.mode = value
            do {
                try store.save(configuration)
            } catch {
                console.error("Could not write \(store.url.path): \(error.localizedDescription)")
                throw ExitCode.failure
            }

            console.success("AI mode: \(value.displayName)")
            if value != .never && configuration.selection == nil {
                console.warn("No agent is selected yet, so nothing will run. Use `keel ai use <id>`.")
            }
        }
    }
}

// MARK: - Use

extension AI {
    struct Use: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "use",
            abstract: "Select the agent Keel may use.",
            discussion: """
                Writes the choice, and the exact command line, to Keel's config \
                file. Selecting an agent permits it; it does not run it.
                """
        )

        @Argument(help: "Agent id, as listed by `keel ai`.")
        var id: String

        func run() throws {
            let console = Console.shared

            guard let agent = Agent.known(id: id) else {
                console.error("Keel does not recognise an agent called `\(id)`.")
                console.detail("Known: \(Agent.known.map(\.id).joined(separator: ", "))")
                throw ExitCode.failure
            }

            let store = AgentStore()
            let selection = AgentSelection(agent: agent)
            var configuration = store.load()
            configuration.selection = selection
            do {
                try store.save(configuration)
            } catch {
                console.error("Could not write \(store.url.path): \(error.localizedDescription)")
                throw ExitCode.failure
            }

            console.success("Selected \(agent.name).")
            console.detail("Runs    \(selection.displayCommand)")
            console.detail("Config  \(store.url.path)")

            if AgentDetector().locate(agent.command) == nil {
                console.warn("`\(agent.command)` is not on your PATH, so nothing can run it yet.")
            }

            // The shipped invocation is a best guess at another tool's CLI, and
            // saying so is cheaper than a confusing failure later.
            console.detail("")
            console.detail("Edit the config if this agent's flags differ from the ones above.")
        }
    }
}

// MARK: - Forget

extension AI {
    struct Forget: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "forget",
            abstract: "Clear the selection, so Keel uses no agent."
        )

        func run() throws {
            let console = Console.shared
            let store = AgentStore()

            guard store.load().selection != nil else {
                console.detail("No agent was selected.")
                return
            }

            do {
                try store.clear()
            } catch {
                console.error("Could not remove \(store.url.path): \(error.localizedDescription)")
                throw ExitCode.failure
            }
            console.success("Cleared. Keel will use no agent.")
        }
    }
}

// MARK: - Verify

extension AI {
    struct Verify: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "verify",
            abstract: "Run the selected agent once, to prove Keel can reach it.",
            discussion: """
                Sends one fixed, trivial prompt and reports what came back. This \
                is the only command in Keel that invokes an agent, and it does \
                nothing else — it reads no project and sends no code.
                """
        )

        /// Answerable by any model, and checkable without parsing prose.
        private static let prompt = "Reply with exactly one word: keel"

        func run() throws {
            let console = Console.shared

            let provider: CommandLineAgent
            do {
                provider = try CommandLineAgent.resolve()
            } catch let error as AIError {
                console.error(error.description)
                throw ExitCode.failure
            }

            // Said before it happens, not after.
            console.step("Running \(provider.invocation)")
            console.detail("Prompt  \(Self.prompt)")

            let answer: String
            do {
                answer = try provider.complete(prompt: Self.prompt)
            } catch let error as AIError {
                console.error(error.description)
                throw ExitCode.failure
            }

            let firstLine = answer.split(separator: "\n").first.map(String.init) ?? answer
            console.detail("Reply   \(firstLine)")

            // Recording it is what makes `keel ai list` able to say anything
            // about readiness at all.
            let store = AgentStore()
            var configuration = store.load()
            configuration.verified[provider.selection.agentID] = Date()
            try? store.save(configuration)

            if answer.lowercased().contains("keel") {
                console.success("The agent answered. Keel can reach it.")
            } else {
                // It ran, which is what was being tested. What it said is its
                // own business, and Keel does not get to call that a failure.
                console.warn("The agent answered, but not as asked. The connection works.")
            }
        }
    }
}
