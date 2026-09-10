import Foundation

/// Terminal output with colour, degrading to plain text when it is not wanted.
///
/// Colour is suppressed when stdout is not a TTY (piping to a file, running in
/// CI) and when `NO_COLOR` is set, per https://no-color.org.
public struct Console: Sendable {
    public static let shared = Console()

    let useColor: Bool

    init() {
        let isTTY = isatty(fileno(stdout)) == 1
        let noColorRequested = ProcessInfo.processInfo.environment["NO_COLOR"] != nil
        self.useColor = isTTY && !noColorRequested
    }

    init(useColor: Bool) {
        self.useColor = useColor
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
        print("\(styled("✓", .green)) \(text)")
    }

    /// Progress within a run of steps.
    public func step(_ text: String) {
        print("\(styled("›", .cyan)) \(text)")
    }

    /// Something the developer should notice but that is not fatal.
    public func warn(_ text: String) {
        print("\(styled("!", .yellow)) \(text)")
    }

    public func error(_ text: String) {
        FileHandle.standardError.write(Data("\(styled("✗", .red)) \(text)\n".utf8))
    }

    public func detail(_ text: String) {
        print(styled("  \(text)", .dim))
    }

    public func heading(_ text: String) {
        print()
        print(styled(text, .bold))
    }
}
