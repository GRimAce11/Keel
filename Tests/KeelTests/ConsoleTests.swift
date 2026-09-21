import Foundation
import Testing
@testable import KeelKit

/// Output is a feature. A finding nobody can read is one nobody acts on, and
/// Keel's findings are long by design — they carry a sentence of reasoning and
/// a path, which is exactly the combination a terminal breaks badly.
@Suite("Console")
struct ConsoleTests {

    // MARK: - Wrapping

    @Test("Text is broken on spaces, never mid-word")
    func wrapsOnSpaces() {
        let lines = Console.wrap("the quick brown fox jumps over the lazy dog", to: 12)

        #expect(lines.allSatisfy { $0.count <= 12 })
        #expect(lines.joined(separator: " ") == "the quick brown fox jumps over the lazy dog")
    }

    @Test("A word longer than the line is left whole")
    func doesNotBreakLongWords() {
        // Nearly always a file path. A path split across two lines cannot be
        // copied, which is the one thing a reader wants to do with it.
        let path = "Probe/Features/Articles/Presentation/ArticleListViewModel.swift:13"
        let lines = Console.wrap("at \(path) here", to: 20)

        #expect(lines.contains(path))
        #expect(lines.joined(separator: " ") == "at \(path) here")
    }

    @Test("Wrapping is lossless")
    func losesNothing() {
        let text = String(repeating: "alpha beta gamma delta ", count: 20)
            .trimmingCharacters(in: .whitespaces)

        for limit in [10, 23, 40, 79, 200] {
            let joined = Console.wrap(text, to: limit).joined(separator: " ")
            #expect(joined == text, "text changed when wrapped to \(limit)")
        }
    }

    @Test("A limit no text could fit returns the text rather than nothing")
    func degradesRatherThanDisappearing() {
        #expect(Console.wrap("something", to: 0) == ["something"])
        #expect(Console.wrap("", to: 40) == [""])
    }

    // MARK: - Detail lines

    /// `detail` carries three different kinds of line, and the difference
    /// between them is the whole of the decision it makes.
    @Test("A detail line that fits keeps the spacing it was given")
    func preservesAlignmentWhenItFits() {
        // Several commands line two columns up by padding with spaces, and
        // wrapping collapses runs of spaces. A line that fits must not go
        // through it.
        #expect(Console.detailLines("Runs      claude -p", to: 78) == ["Runs      claude -p"])
    }

    @Test("A detail line longer than the terminal is wrapped")
    func wrapsOverlongDetail() {
        // `keel document` printed its architecture summary through this, and
        // at 80 columns it came out as one 143-character line.
        let summary = "SwiftUI MVVM, screens fed both ways, organised by feature, wired "
            + "through a composition root, built on @Observable, async/await and SwiftData."
        let lines = Console.detailLines(summary, to: 78)

        #expect(lines.count > 1)
        #expect(lines.allSatisfy { $0.count <= 78 })
        #expect(lines.joined(separator: " ") == summary)
    }

    @Test("A line built around one long word is left whole")
    func leavesUnwrappableLinesAlone() {
        // `cd <a very long path>` overflows however it is broken, and breaking
        // it strands `cd` on a line of its own, away from what it applies to.
        let path = "/Users/someone/Developer/" + String(repeating: "nested/", count: 12) + "App"
        #expect(Console.detailLines("cd \(path)", to: 78) == ["cd \(path)"])
    }

    // MARK: - Width

    @Test("Prose is capped below the terminal width")
    func capsProseWidth() {
        // A sentence run across a 200-column terminal is harder to read than
        // one held to a book's line length, so width is a ceiling and not a
        // target.
        let console = Console(useColor: false, width: 200)
        #expect(console.width == 200)
        #expect(Console.maximumProseWidth < 200)
    }
}
