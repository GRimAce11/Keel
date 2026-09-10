import Foundation

/// Turns a bundled template file into a project file.
///
/// Two transformations happen, in this order:
///
/// 1. **Conditional blocks** are resolved, so one template can serve several
///    component combinations:
///
///        // keel:if networking
///        let client = APIClient()
///        // keel:else
///        let client = PreviewClient()
///        // keel:end
///
///    The directive lines never reach the output. Any comment marker works —
///    `//`, `#`, `<!--`, `/*` — because the same syntax has to be usable in
///    Swift, in an XML scheme, and in a pbxproj, which is an old-style plist
///    and rejects `//`.
///
/// 2. **Tokens** are substituted, in file contents and in path components
///    alike, so `__PROJECT_NAME__App.swift.tpl` becomes `MyAppApp.swift`.
///
/// Files that are not valid UTF-8 are reported as such so the caller can copy
/// them byte for byte, leaving images and other binary assets intact.
public struct TemplateRenderer {

    let tokens: [String: String]
    let enabledComponents: Set<Component>

    public init(configuration: ProjectConfiguration, date: Date = Date()) {
        self.enabledComponents = configuration.components

        let year = Calendar.current.component(.year, from: date)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy"

        self.tokens = [
            // Templates for dotfiles are named `__DOT__gitignore.tpl`, because
            // the file walker skips hidden files to avoid sweeping up .DS_Store.
            "__DOT__": ".",
            "__PROJECT_NAME__": configuration.name.raw,
            "__PROJECT_SLUG__": configuration.name.slug,
            "__BUNDLE_ID__": configuration.bundleIdentifier,
            "__DEPLOYMENT_TARGET__": configuration.minimumIOSVersion,
            "__KEEL_VERSION__": KeelVersion.current,
            "__YEAR__": String(year),
            "__DATE__": formatter.string(from: date),
        ]
    }

    // MARK: - Public

    /// Applies token substitution to a path component, and strips `.tpl`.
    public func renderPath(_ path: String) -> String {
        var result = substituteTokens(in: path)
        if result.hasSuffix(".tpl") {
            result.removeLast(4)
        }
        return result
    }

    /// Renders file contents. Returns `nil` for data that is not valid UTF-8,
    /// signalling the caller to copy the original bytes unchanged.
    public func renderContents(of data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let resolved = resolveConditionals(in: text)
        return Data(substituteTokens(in: resolved).utf8)
    }

    /// Whether rendering left nothing but whitespace — the signature of a file
    /// whose entire body sat inside a conditional that resolved to false.
    public func isEffectivelyEmpty(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Tokens

    private func substituteTokens(in text: String) -> String {
        var result = text
        for (token, value) in tokens {
            result = result.replacingOccurrences(of: token, with: value)
        }
        return result
    }

    // MARK: - Conditionals

    private enum Directive {
        case start(component: String, negated: Bool)
        case alternate
        case end
    }

    private func resolveConditionals(in text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var output: [String] = []
        output.reserveCapacity(lines.count)

        // One element per nesting level: whether its lines are being kept.
        var stack: [Bool] = []
        var keeping: Bool { !stack.contains(false) }

        for line in lines {
            switch directive(in: line) {
            case .start(let componentName, let negated):
                let isEnabled = enabledComponents.contains { $0.rawValue == componentName }
                stack.append(negated ? !isEnabled : isEnabled)

            case .alternate:
                if !stack.isEmpty {
                    stack[stack.count - 1].toggle()
                }

            case .end:
                if !stack.isEmpty { stack.removeLast() }

            case nil:
                if keeping { output.append(line) }
            }
        }

        return collapseBlankRuns(in: output).joined(separator: "\n")
    }

    /// Recognises `keel:if`, `keel:if !`, `keel:else` and `keel:end` behind any
    /// comment marker, returning `nil` for ordinary lines.
    private func directive(in line: String) -> Directive? {
        var trimmed = line.trimmingCharacters(in: .whitespaces)

        for marker in ["//", "#", "<!--", "/*"] where trimmed.hasPrefix(marker) {
            trimmed = String(trimmed.dropFirst(marker.count))
            break
        }
        trimmed = trimmed.trimmingCharacters(in: .whitespaces)

        for terminator in ["-->", "*/"] where trimmed.hasSuffix(terminator) {
            trimmed = String(trimmed.dropLast(terminator.count))
            break
        }
        trimmed = trimmed.trimmingCharacters(in: .whitespaces)

        guard trimmed.hasPrefix("keel:") else { return nil }
        let body = trimmed.dropFirst("keel:".count).trimmingCharacters(in: .whitespaces)

        if body == "else" { return .alternate }
        if body == "end" { return .end }

        guard body.hasPrefix("if") else { return nil }
        var argument = body.dropFirst(2).trimmingCharacters(in: .whitespaces)

        let negated = argument.hasPrefix("!")
        if negated {
            argument = String(argument.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        guard !argument.isEmpty else { return nil }
        return .start(component: argument, negated: negated)
    }

    /// Removing a conditional block usually strands two blank lines where one
    /// belongs. Generated code that reads as though it were written by hand
    /// matters more here than almost anywhere else — it is the first thing the
    /// developer opens.
    private func collapseBlankRuns(in lines: [String]) -> [String] {
        var result: [String] = []
        var blankRun = 0

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blankRun += 1
                if blankRun > 1 { continue }
            } else {
                blankRun = 0
            }
            result.append(line)
        }

        while let last = result.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            result.removeLast()
        }
        result.append("")
        return result
    }
}
