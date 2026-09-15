import Foundation
import Testing
@testable import KeelKit

/// Budgets, not benchmarks.
///
/// The numbers here are deliberately loose — a test that fails when a laptop is
/// busy teaches people to ignore it. What they catch is the change of *shape*:
/// an accidental quadratic, or a graph rebuilt once per question instead of
/// once per run. Those show up as multiples, not percentages.
@Suite("Performance")
struct PerformanceTests {

    private let console = Console(useColor: false)

    /// A project with `features` features, each with a model, a view model and
    /// a view, and each model naming the previous one — so the type graph has
    /// real work to do rather than a pile of unrelated declarations.
    private func project(features: Int) throws -> URL {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-perf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let outcome = try ProjectGenerator(
            configuration: ProjectConfiguration(
                name: try ProjectName("Scale"),
                bundleIdentifierPrefix: "com.acme",
                components: Set(Component.allCases)
            ),
            console: console
        ).generate(in: destination, initializeGit: false)

        let root = outcome.projectDirectory.appendingPathComponent("Scale/Features")
        for index in 1...features {
            let name = String(format: "F%04d", index)
            let previous = index > 1 ? String(format: "F%04d", index - 1) : nil
            let upstream = previous.map { "\n    let upstream: \($0)Model?" } ?? ""

            try write(
                "import Foundation\n\nstruct \(name)Model {\n    let id: String\(upstream)\n}\n",
                to: root.appendingPathComponent("\(name)/Domain/\(name)Model.swift")
            )
            try write(
                "import Observation\n\n@Observable\nfinal class \(name)ViewModel {\n"
                + "    var item: \(name)Model?\n}\n",
                to: root.appendingPathComponent("\(name)/Presentation/\(name)ViewModel.swift")
            )
            try write(
                "import SwiftUI\n\nstruct \(name)View: View {\n    let model: \(name)ViewModel\n"
                + "    var body: some View { Text(\"x\") }\n}\n",
                to: root.appendingPathComponent("\(name)/Presentation/\(name)View.swift")
            )
        }
        return outcome.projectDirectory
    }

    private func write(_ source: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try source.write(to: url, atomically: true, encoding: .utf8)
    }

    private func seconds(_ work: () throws -> Void) rethrows -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        try work()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
    }

    // MARK: - Shape

    @Test("Analysis scales with the project, not with the square of it", .timeLimit(.minutes(2)))
    func scalesLinearly() throws {
        // The property worth pinning. Absolute times move with the machine;
        // the ratio between two sizes does not, and an accidental quadratic
        // shows up here as a multiple rather than a slowdown nobody notices.
        let small = try project(features: 50)
        let large = try project(features: 200)
        defer {
            try? FileManager.default.removeItem(at: small.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: large.deletingLastPathComponent())
        }

        _ = try ProjectScanner(root: small).scan()  // warm the caches and the parser

        let smallTime = try seconds { _ = try ProjectScanner(root: small).scan() }
        let largeTime = try seconds { _ = try ProjectScanner(root: large).scan() }

        // Four times the features. Linear would be 4x; quadratic would be 16x.
        // Eight leaves room for a slow machine and still fails a quadratic.
        let ratio = largeTime / max(smallTime, 0.001)
        #expect(ratio < 8, "scaling looks worse than linear: \(ratio)x for 4x the work")
    }

    @Test("A large project stays usable from the command line", .timeLimit(.minutes(2)))
    func staysUsable() throws {
        let root = try project(features: 200)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let elapsed = try seconds { _ = try ProjectScanner(root: root).scan() }

        // ~640 files. Ten seconds is far above what it takes and far below
        // what anybody would tolerate, which is the right place for a budget.
        #expect(elapsed < 10, "a 640-file project took \(elapsed)s to scan")
    }

    @Test("Asking the dependency graph a question does not rebuild it", .timeLimit(.minutes(2)))
    func graphQueriesAreCheap() throws {
        let root = try project(features: 100)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let model = try ProjectScanner(root: root).scan()

        let build = try seconds { _ = model.dependencyGraph() }
        let graph = model.dependencyGraph()
        let queries = try seconds {
            for scope in DependencyScope.structural {
                _ = graph.edges(at: scope)
                _ = graph.cycles(at: scope)
            }
        }

        // Twelve queries against one graph must not cost more than building it
        // a second time, or callers will start hoarding their own copies.
        #expect(queries < build * 12, "queries cost \(queries)s against a \(build)s build")
    }

    @Test("Checking costs about what scanning costs, not a multiple of it", .timeLimit(.minutes(2)))
    func checkingDoesNotRedoTheWork() throws {
        let root = try project(features: 100)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let model = try ProjectScanner(root: root).scan()
        let scan = try seconds { _ = try ProjectScanner(root: root).scan() }
        let check = try seconds { _ = ProjectChecker(model: model).check() }

        // Every rule reads the graphs the scan already built. If one started
        // re-parsing, this is where it would show.
        #expect(check < scan, "checking (\(check)s) cost more than scanning (\(scan)s)")
    }
}
