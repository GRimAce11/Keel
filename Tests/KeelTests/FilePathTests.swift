import Foundation
import Testing
@testable import KeelKit

/// Where a file sits relative to a root.
///
/// It looks like string arithmetic and is not. These are the two mistakes that
/// produced `privateMyApp.xcodeproj` from `keel new` — worth pinning, because
/// both of them read as correct.
@Suite("FilePath")
struct FilePathTests {

    @Test("A path inside the root comes back relative")
    func stripsTheRoot() {
        let root = URL(fileURLWithPath: "/Users/x/Project")
        let file = URL(fileURLWithPath: "/Users/x/Project/Sources/App.swift")

        #expect(FilePath.relative(of: file, from: root) == "Sources/App.swift")
    }

    @Test("A path outside the root comes back whole, not half-eaten")
    func leavesOutsidePathsAlone() {
        let root = URL(fileURLWithPath: "/Users/x/Project")
        let file = URL(fileURLWithPath: "/Users/y/Other/App.swift")

        #expect(FilePath.relative(of: file, from: root) == "/Users/y/Other/App.swift")
    }

    @Test("The root is stripped from the front only, never matched in the middle")
    func stripsAPrefixRatherThanReplacingASubstring() {
        // The first half of the bug. `replacingOccurrences(of: "/tmp/x/")`
        // against "/private/tmp/x/App.swift" matches eight characters in and
        // leaves "/private" fused to what follows — which became
        // "privateMyApp.xcodeproj" once the result was split and rendered.
        let root = URL(fileURLWithPath: "/tmp/x")
        let file = URL(fileURLWithPath: "/somewhere/tmp/x/App.swift")

        let relative = FilePath.relative(of: file, from: root)
        #expect(!relative.hasPrefix("private"))
        #expect(!relative.contains("somewhere/tmp/x/App.swift".replacingOccurrences(of: "/tmp/x/", with: "")))
        #expect(relative == "/somewhere/tmp/x/App.swift")
    }

    @Test("Two spellings of the same directory agree")
    func resolvesSymlinks() throws {
        // The second half. macOS symlinks /tmp to /private/tmp, and
        // `standardizedFileURL` does not resolve symlinks — so a root recorded
        // one way and a file enumerated the other are the same place and do
        // not look it.
        //
        // Real directories, because Foundation only resolves a path that
        // exists: `/private/tmp` becomes `/tmp`, while `/private/tmp/nope`
        // stays as written. Asserting against invented paths would be
        // asserting against a fiction.
        let name = "keel-symlink-\(UUID().uuidString)"
        let viaTmp = URL(fileURLWithPath: "/tmp").appendingPathComponent(name)
        let viaPrivate = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(name)

        try FileManager.default.createDirectory(
            at: viaTmp.appendingPathComponent("Sources"), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: viaTmp) }

        let file = viaPrivate.appendingPathComponent("Sources/App.swift")
        FileManager.default.createFile(atPath: file.path, contents: Data("//\n".utf8))

        // Same place, spelled both ways, on either side of the comparison.
        #expect(FilePath.relative(of: file, from: viaTmp) == "Sources/App.swift")
        #expect(FilePath.relative(of: file, from: viaPrivate) == "Sources/App.swift")
        #expect(
            FilePath.relative(of: viaTmp.appendingPathComponent("Sources/App.swift"), from: viaPrivate)
                == "Sources/App.swift"
        )
    }

    @Test("No root means the whole path")
    func toleratesNoRoot() {
        let file = URL(fileURLWithPath: "/Users/x/App.swift")
        #expect(FilePath.relative(of: file, from: nil) == "/Users/x/App.swift")
    }

    // MARK: - What it cost

    @Test("Templates reached through a symlinked path still produce correct file names")
    func generationSurvivesSymlinkedTemplates() throws {
        // The failure this came from, reproduced at its actual trigger: it is
        // where the *templates* resolve from that matters, not where the
        // project is written. A Homebrew bottle unpacked under /private is
        // exactly such a path, and it produced privateMyApp.xcodeproj,
        // privateREADME.md and private.gitignore — every leading path
        // component fused to the word "private".
        let id = UUID().uuidString

        // Build a small template tree under /tmp, then hand the generator the
        // /private spelling of the same directory. Both are real, so they
        // genuinely name one place while looking like two.
        let viaTmp = URL(fileURLWithPath: "/tmp").appendingPathComponent("keel-tpl-\(id)")
        let base = viaTmp.appendingPathComponent("Base/__PROJECT_NAME__")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: viaTmp) }

        try "// __PROJECT_NAME__\n".write(
            to: base.appendingPathComponent("__PROJECT_NAME__App.swift.tpl"),
            atomically: true, encoding: .utf8
        )

        // The /tmp spelling, deliberately. `FileManager.enumerator` resolves
        // symlinks in what it yields, and a URL built by hand does not — so a
        // root given as /tmp enumerates as /private/tmp, and only that way
        // round produces the mismatch. Measured, not assumed: given the
        // /private spelling both sides already agree and nothing goes wrong.
        let templateRoot = viaTmp

        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-out-\(id)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let outcome = try ProjectGenerator(
            configuration: ProjectConfiguration(
                name: try ProjectName("MyApp"),
                bundleIdentifierPrefix: "com.acme",
                components: []
            ),
            catalog: try TemplateCatalog(root: templateRoot),
            console: Console(useColor: false)
        ).generate(in: destination, initializeGit: false)

        let produced = try FileManager.default
            .subpathsOfDirectory(atPath: outcome.projectDirectory.path)
            .sorted()

        #expect(produced.contains("MyApp/MyAppApp.swift"), "produced: \(produced)")
        #expect(!produced.contains { $0.contains("private") },
                "path components leaked into file names: \(produced)")
    }
}
