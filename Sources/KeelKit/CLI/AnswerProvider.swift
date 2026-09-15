import Foundation

/// Supplies answers to the questions `keel new` asks.
///
/// The interview depends on this rather than on stdin directly, which is what
/// lets configuration be tested without a terminal. Three implementations
/// exist: one that asks a human, one that takes every default, and a scripted
/// one in the test target.
public protocol AnswerProvider: Sendable {
    func text(_ question: String, default defaultValue: String) -> String
    func confirm(_ question: String, detail: String?, default defaultValue: Bool) -> Bool
    /// Picks one of several options, returning its index.
    ///
    /// Defaulted below, so an existing provider that only answers yes-or-no
    /// questions keeps working. A non-interactive run takes the default, which
    /// for the checker means "continue" — so piping `keel check` into a log
    /// never waits for somebody who is not there.
    func choice(_ question: String, options: [String], default defaultIndex: Int) -> Int

    /// Whether questions are actually being put to someone. When false the
    /// interview skips its section headings — printing "Include" above nothing
    /// is noise in a CI log.
    var isInteractive: Bool { get }
}

public extension AnswerProvider {
    var isInteractive: Bool { false }

    func choice(_ question: String, options: [String], default defaultIndex: Int) -> Int {
        defaultIndex
    }
}

// MARK: - Defaults

/// Answers every question with its default.
///
/// Used for `--yes`, and whenever stdin is not a terminal — a piped or CI
/// invocation has nobody to answer, and blocking on `readLine` there would
/// hang the build rather than fail it.
public struct DefaultAnswers: AnswerProvider {
    public init() {}

    public func text(_ question: String, default defaultValue: String) -> String {
        defaultValue
    }

    public func confirm(_ question: String, detail: String?, default defaultValue: Bool) -> Bool {
        defaultValue
    }
}

// MARK: - Interactive

/// Asks the developer, on the terminal.
public struct InteractivePrompt: AnswerProvider {
    let console: Console

    public var isInteractive: Bool { true }

    public init(console: Console = .shared) {
        self.console = console
    }

    /// Whether a human is actually there to answer.
    public static var isAvailable: Bool {
        isatty(fileno(stdin)) == 1
    }

    public func text(_ question: String, default defaultValue: String) -> String {
        print("\(console.styled("?", .cyan)) \(question) \(console.styled("(\(defaultValue))", .dim)) ", terminator: "")

        guard let line = readLine(strippingNewline: true) else {
            // stdin closed mid-run. Take the default rather than failing.
            print()
            return defaultValue
        }

        let answer = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return answer.isEmpty ? defaultValue : answer
    }

    public func confirm(_ question: String, detail: String?, default defaultValue: Bool) -> Bool {
        let hint = defaultValue ? "Y/n" : "y/N"
        // Detail sits inline so the cursor stays on the question being answered.
        let described = detail.map { "\(question) \(console.styled("— \($0)", .dim))" } ?? question

        while true {
            print("\(console.styled("?", .cyan)) \(described) \(console.styled("[\(hint)]", .dim)) ", terminator: "")

            guard let line = readLine(strippingNewline: true) else {
                print()
                return defaultValue
            }

            switch line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "": return defaultValue
            case "y", "yes": return true
            case "n", "no": return false
            default:
                // Guessing at an unrecognised answer would silently generate
                // something the developer did not ask for.
                console.warn("Answer y or n.")
            }
        }
    }

    public func choice(_ question: String, options: [String], default defaultIndex: Int) -> Int {
        guard !options.isEmpty else { return defaultIndex }
        let fallback = min(max(defaultIndex, 0), options.count - 1)

        while true {
            console.write()
            for (index, option) in options.enumerated() {
                let marker = index == fallback ? console.styled("*", .cyan) : " "
                print("  \(marker) \(index + 1). \(option)")
            }
            print(
                "\(console.styled("?", .cyan)) \(question) "
                + "\(console.styled("[1-\(options.count)]", .dim)) ",
                terminator: ""
            )

            guard let line = readLine(strippingNewline: true) else {
                print()
                return fallback
            }

            let answer = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if answer.isEmpty { return fallback }
            if let number = Int(answer), (1...options.count).contains(number) { return number - 1 }

            console.warn("Answer with a number between 1 and \(options.count).")
        }
    }
}
