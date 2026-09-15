import Foundation
import Testing
@testable import KeelKit

/// An `AnswerProvider` that walks a fixed route through the explorer.
///
/// Choices are given as the option *labels* rather than indexes, so a test
/// says where it is going rather than which number happened to be there. A
/// label nobody offers is recorded and answered with the default, which is how
/// a screen that stops offering something gets caught.
final class ScriptedRoute: AnswerProvider, @unchecked Sendable {

    private var wanted: [String]
    private let searches: [String]
    private(set) var offered: [[String]] = []
    private(set) var unmatched: [String] = []
    private var searchIndex = 0

    var isInteractive: Bool { true }

    init(_ wanted: [String], searches: [String] = []) {
        self.wanted = wanted
        self.searches = searches
    }

    func choice(_ question: String, options: [String], default defaultIndex: Int) -> Int {
        offered.append(options)
        guard let next = wanted.first else { return defaultIndex }

        // Matched loosely: a menu label carries counts that a test should not
        // have to predict — "Articles" should find "Articles (4)".
        guard let index = options.firstIndex(where: { $0.contains(next) }) else {
            unmatched.append(next)
            wanted.removeFirst()
            return defaultIndex
        }
        wanted.removeFirst()
        return index
    }

    func text(_ question: String, default defaultValue: String) -> String {
        defer { searchIndex += 1 }
        return searchIndex < searches.count ? searches[searchIndex] : defaultValue
    }

    func confirm(_ question: String, detail: String?, default defaultValue: Bool) -> Bool {
        defaultValue
    }
}

/// The explorer is driven through scripted answers rather than a terminal, so
/// what it offers and where each choice leads is testable rather than only
/// demonstrable.
@Suite("Explorer")
struct ExplorerTests {

    private let console = Console(useColor: false)

    private func model(damage: (URL) throws -> Void = { _ in }) throws -> ProjectModel {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-explore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let outcome = try ProjectGenerator(
            configuration: ProjectConfiguration(
                name: try ProjectName("Probe"),
                bundleIdentifierPrefix: "com.acme",
                components: Set(Component.allCases)
            ),
            console: console
        ).generate(in: destination, initializeGit: false)
        try damage(outcome.projectDirectory)
        return try ProjectScanner(root: outcome.projectDirectory).scan()
    }

    private func write(_ source: String, to path: String, in root: URL) throws {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try source.write(to: file, atomically: true, encoding: .utf8)
    }

    @discardableResult
    private func explore(
        _ route: ScriptedRoute,
        damage: (URL) throws -> Void = { _ in }
    ) throws -> ScriptedRoute {
        Explorer(model: try model(damage: damage), answers: route, console: console).run()
        return route
    }

    // MARK: - Getting out

    @Test("With nobody answering, the explorer leaves rather than looping")
    func defaultsToLeaving() throws {
        // The property that makes this safe to run anywhere: every menu's
        // default is the way out, so a piped run ends instead of hanging.
        let route = try explore(ScriptedRoute([]))

        #expect(route.offered.count == 1)
        #expect(route.offered[0].last == "Exit")
    }

    @Test("Every menu ends in a way out, and that way out is the default")
    func everyMenuOffersAWayOut() throws {
        let route = try explore(ScriptedRoute(["Architecture", "Presentation", "Exit"]))

        // Home ends in Exit, every screen reached from it ends in Back. Either
        // way the last option is the escape, and `choice` is called with it as
        // the default — so nobody answering walks out rather than in.
        for options in route.offered {
            #expect(options.last == "Back" || options.last == "Exit",
                    "a menu offered no way out: \(options)")
        }
    }

    @Test("A route that names something nobody offers is caught, not silently defaulted")
    func unmatchedChoicesAreRecorded() throws {
        let route = try explore(ScriptedRoute(["Telemetry", "Exit"]))
        #expect(route.unmatched == ["Telemetry"])
    }

    // MARK: - The screens

    @Test("Home offers every screen the plan asks for")
    func homeOffersEveryScreen() throws {
        let route = try explore(ScriptedRoute([]))

        let home = try #require(route.offered.first)
        for expected in ["Architecture", "Features", "Dependencies", "Data flow",
                         "Types by role", "Architecture warnings", "Search", "Exit"] {
            #expect(home.contains(expected), "home does not offer \(expected)")
        }
    }

    @Test("Architecture offers its findings, and a finding offers its evidence")
    func architectureLeadsToEvidence() throws {
        let route = try explore(ScriptedRoute(["Architecture", "Presentation", "Exit"]))

        #expect(route.unmatched.isEmpty)
        #expect(route.offered.contains { $0.contains { $0.hasPrefix("Presentation:") } })
    }

    @Test("A feature leads to the feature, not to a menu of everything")
    func featuresLeadToOneFeature() throws {
        let route = try explore(ScriptedRoute(["Features", "Articles", "Exit"]))

        #expect(route.unmatched.isEmpty)
        #expect(route.offered.contains { $0.contains("Articles") })
    }

    @Test("Dependencies ask for a scope, then offer the edges at it")
    func dependenciesLeadToAnEdge() throws {
        let route = try explore(
            ScriptedRoute(["Dependencies", "Module", "Features → Core", "Exit"])
        )

        #expect(route.unmatched.isEmpty)
    }

    @Test("Types are browsed by role, then one at a time")
    func typesLeadToAType() throws {
        let route = try explore(ScriptedRoute(["Types by role", "ViewModel", "ArticleListViewModel", "Exit"]))

        #expect(route.unmatched.isEmpty)
    }

    @Test("A warning leads to its rule, evidence and explanation")
    func findingsLeadToARule() throws {
        let route = try explore(
            ScriptedRoute(["Architecture warnings", "Core depends on", "Exit"]),
            damage: { root in
                try write(
                    "import Foundation\n\nenum Telemetry { static var a: Article? }\n",
                    to: "Probe/Core/Telemetry.swift",
                    in: root
                )
            }
        )

        #expect(route.unmatched.isEmpty)
    }

    @Test("A clean project's warnings screen offers nothing to drill into")
    func cleanProjectHasNoWarnings() throws {
        let route = try explore(ScriptedRoute(["Architecture warnings", "Exit"]))

        // It reports and returns rather than offering an empty list to pick
        // from — being asked to choose from nothing is worse than being told.
        #expect(route.unmatched.isEmpty)
    }

    // MARK: - Search

    @Test("Search finds features, types, files and targets by substring")
    func searchFindsThings() throws {
        let model = try model()

        let matches = Explorer.matches(for: "article", in: model)
        #expect(matches.contains { $0.kind.contains("feature") && $0.name == "Articles" })
        #expect(matches.contains { $0.kind.contains("type") && $0.name == "ArticleListView" })
        #expect(matches.contains { $0.kind.contains("file") })

        // Case-insensitive, because somebody exploring is guessing at names.
        #expect(Explorer.matches(for: "ARTICLE", in: model).count == matches.count)
    }

    @Test("Search for something that is not there says so rather than guessing")
    func searchFindsNothing() throws {
        #expect(Explorer.matches(for: "PaymentGateway", in: try model()).isEmpty)
    }

    @Test("Search runs from the explorer without needing a menu entry per result")
    func searchRunsFromTheMenu() throws {
        let route = ScriptedRoute(["Search", "Exit"], searches: ["Article"])
        Explorer(model: try model(), answers: route, console: console).run()

        #expect(route.unmatched.isEmpty)
    }

    // MARK: - What it will not do

    @Test("Every screen can be opened, one at a time, without anything failing")
    func everyScreenOpens() throws {
        // Each in its own run, because screens differ in whether they ask a
        // follow-up question — a single long route would be asserting the
        // shape of the menus rather than that the screens work.
        let model = try model()

        for screen in ["Architecture", "Features", "Dependencies", "Data flow",
                       "Types by role", "Architecture warnings"] {
            let route = ScriptedRoute([screen])
            Explorer(model: model, answers: route, console: console).run()

            #expect(route.unmatched.isEmpty, "\(screen) was not offered")
            #expect(route.offered.count >= 1)
        }
    }

    @Test("A project with no features still explores, saying what is missing")
    func survivesAMinimalProject() throws {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-explore-min-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let outcome = try ProjectGenerator(
            configuration: ProjectConfiguration(
                name: try ProjectName("Bare"),
                bundleIdentifierPrefix: "com.acme",
                components: []
            ),
            console: console
        ).generate(in: destination, initializeGit: false)

        let model = try ProjectScanner(root: outcome.projectDirectory).scan()

        // A screen with nothing to show says so and returns, rather than
        // offering an empty list to choose from.
        for screen in ["Features", "Dependencies", "Data flow", "Types by role"] {
            let route = ScriptedRoute([screen])
            Explorer(model: model, answers: route, console: console).run()

            #expect(route.unmatched.isEmpty, "\(screen) was not offered")
            #expect(!route.offered.contains { $0 == ["Back"] },
                    "\(screen) offered an empty list")
        }
    }
}
