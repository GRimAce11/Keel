import Foundation

/// Terminal output with colour, degrading to plain text when it is not wanted.
///
/// Colour is suppressed when stdout is not a TTY (piping to a file, running in
/// CI) and when `NO_COLOR` is set, per https://no-color.org.
public struct Console: Sendable {
    public static let shared = Console()

    let useColor: Bool

    /// Columns available for output.
    ///
    /// Clamped for prose rather than used raw: a sentence run to the full width
    /// of an ultrawide terminal is measurably harder to read than one wrapped
    /// at a book's line length, and the terminal being wide is not a request
    /// for it to be used.
    let width: Int

    static let maximumProseWidth = 100

    init() {
        let isTTY = isatty(fileno(stdout)) == 1
        let noColorRequested = ProcessInfo.processInfo.environment["NO_COLOR"] != nil
        self.useColor = isTTY && !noColorRequested
        self.width = Self.detectedWidth()
    }

    init(useColor: Bool, width: Int = 80) {
        self.useColor = useColor
        self.width = width
    }

    /// `COLUMNS` first, because a caller that set it means it — including a
    /// test that needs wrapping to be deterministic. Then ask the terminal.
    /// Then 80, which is wrong on no terminal badly enough to matter.
    private static func detectedWidth() -> Int {
        if let columns = ProcessInfo.processInfo.environment["COLUMNS"],
           let parsed = Int(columns), parsed > 20 {
            return parsed
        }

        var size = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size) == 0, size.ws_col > 20 {
            return Int(size.ws_col)
        }

        return 80
    }

    // MARK: - Styling

    enum Style: String {
        case dim = "\u{001B}[2m"
        case bold = "\u{001B}[1m"
        case red = "\u{001B}[31m"
        case green = "\u{001B}[32m"
        case yellow = "\u{001B}[33m"
        case cyan = "\u{001B}[36m"
        case reset = "\u{001B}[0m"
    }

    func styled(_ text: String, _ style: Style) -> String {
        guard useColor else { return text }
        return style.rawValue + text + Style.reset.rawValue
    }

    // MARK: - Output

    public func write(_ text: String = "") {
        print(text)
    }

    /// A step that completed.
    public func success(_ text: String) {
        emit(styled("✓", .green), text)
    }

    /// Progress within a run of steps.
    public func step(_ text: String) {
        emit(styled("›", .cyan), text)
    }

    /// Something the developer should notice but that is not fatal.
    public func warn(_ text: String) {
        emit(styled("!", .yellow), text)
    }

    /// A glyph and its message, wrapped with the continuation lined up under
    /// the message rather than under the glyph.
    ///
    /// Finding headlines carry a path *and* a sentence, which makes them the
    /// longest lines Keel prints. Wrapping here rather than at each call site
    /// means every command gets it without knowing about it.
    private func emit(_ glyph: String, _ text: String) {
        let lines = Self.wrap(text, to: min(width, Self.maximumProseWidth) - 2)
        print("\(glyph) \(lines[0])")
        for continuation in lines.dropFirst() {
            print("  \(continuation)")
        }
    }

    /// The command itself failed. Goes to stderr, so a caller redirecting
    /// output still sees it.
    public func error(_ text: String) {
        FileHandle.standardError.write(Data("\(styled("✗", .red)) \(text)\n".utf8))
    }

    /// Something Keel found wrong with the project, as opposed to something
    /// wrong with the run.
    ///
    /// Goes to stdout, because for a command whose output *is* its findings,
    /// splitting them across two streams scrambles their order the moment
    /// anything is piped.
    public func failure(_ text: String) {
        emit(styled("✗", .red), text)
    }

    /// A subordinate line: a command to copy, an aligned key and value, a
    /// sentence under a headline.
    ///
    /// Wrapped only when wrapping helps. A line that fits is printed exactly
    /// as it was given, so runs of spaces holding two columns apart survive;
    /// a line whose longest word already exceeds the width would overflow
    /// either way, and breaking it only strands the short words on a line of
    /// their own — `cd` above the path it belongs to. Everything else is
    /// prose, and prose wraps.
    public func detail(_ text: String) {
        for line in Self.detailLines(text, to: min(width, Self.maximumProseWidth) - 2) {
            print(styled("  " + line, .dim))
        }
    }

    /// The decision `detail` makes, kept separate from printing it so it can be
    /// tested without holding the process's stdout.
    static func detailLines(_ text: String, to limit: Int) -> [String] {
        let longestWord = text.split(separator: " ").map(\.count).max() ?? 0
        guard text.count > limit, longestWord <= limit else { return [text] }
        return wrap(text, to: limit)
    }

    public func heading(_ text: String) {
        print()
        print(styled(text, .bold))
    }

    // MARK: - Prose

    /// A sentence or paragraph, wrapped to the terminal and indented.
    ///
    /// Keel's findings explain themselves, and an explanation emitted as one
    /// 300-character line is one the reader's terminal breaks at an arbitrary
    /// column — mid-word, mid-path, with no indent to show it continued. This
    /// breaks it on spaces instead and keeps the continuation lined up under
    /// the first line, so a wrapped explanation still reads as one block.
    public func paragraph(_ text: String, indent: Int = 2) {
        let margin = String(repeating: " ", count: indent)
        for line in Self.wrap(text, to: min(width, Self.maximumProseWidth) - indent) {
            print(styled(margin + line, .dim))
        }
    }

    /// Greedy wrap. A word longer than the line — a long path, usually — is
    /// left whole rather than broken, because a path split across two lines
    /// cannot be copied.
    static func wrap(_ text: String, to limit: Int) -> [String] {
        guard limit > 0 else { return [text] }

        var lines: [String] = []
        var current = ""

        for word in text.split(separator: " ", omittingEmptySubsequences: true) {
            if current.isEmpty {
                current = String(word)
            } else if current.count + 1 + word.count <= limit {
                current += " " + word
            } else {
                lines.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines.isEmpty ? [""] : lines
    }

    // MARK: - Tables

    public enum Alignment: Sendable {
        case left
        case right
    }

    /// Rows with their columns lined up.
    ///
    /// Every command that prints a table used to compute its own widths, which
    /// meant none of them could drift into agreement because nothing made them.
    /// Widths are measured once here, so `inspect`, `check` and `doctor` line
    /// up the same way without each one knowing how.
    public func table(
        _ rows: [[String]],
        alignment: [Alignment] = [],
        indent: Int = 2,
        gap: Int = 2
    ) {
        guard !rows.isEmpty else { return }

        let columns = rows.map(\.count).max() ?? 0
        var widths = [Int](repeating: 0, count: columns)
        for row in rows {
            for (index, cell) in row.enumerated() {
                widths[index] = max(widths[index], cell.count)
            }
        }

        let margin = String(repeating: " ", count: indent)
        let spacer = String(repeating: " ", count: gap)

        // Columns that do not fit are not columns. Rather than let the
        // terminal break them at an arbitrary place, stack each row: first
        // cell on its own line, the rest indented under it.
        // The full terminal, not the prose cap: a column of paths is not a
        // sentence, and the reason to hold prose to a book's line length does
        // not apply to something the eye scans down rather than reads across.
        let needed = indent + widths.reduce(0, +) + gap * max(columns - 1, 0)
        guard needed <= width else {
            for row in rows {
                guard let first = row.first else { continue }
                print(margin + first)
                for cell in row.dropFirst() {
                    print(margin + "  " + cell)
                }
            }
            return
        }

        for row in rows {
            var cells: [String] = []
            for (index, cell) in row.enumerated() {
                let pad = String(repeating: " ", count: widths[index] - cell.count)
                // The last column is never padded — trailing spaces are
                // invisible until somebody copies the line.
                let isLast = index == row.count - 1
                let align = index < alignment.count ? alignment[index] : .left
                cells.append(isLast ? cell : (align == .right ? pad + cell : cell + pad))
            }
            print(margin + cells.joined(separator: spacer))
        }
    }

    // MARK: - Separators

    /// A dim rule, for putting air between findings that each run to several
    /// lines. A blank line alone stops separating them once they are long.
    public func rule() {
        print(styled(String(repeating: "─", count: min(width, Self.maximumProseWidth)), .dim))
    }
}
