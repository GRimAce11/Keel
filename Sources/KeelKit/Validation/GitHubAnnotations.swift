import Foundation

/// Findings written as GitHub Actions workflow commands, so they land on the
/// changed lines of a pull request instead of in a log nobody opens.
///
/// A gate that can only be read by scrolling a build log is a gate people turn
/// off. Every `Diagnostic` already carries `file:line`, so this is a rephrasing
/// of what Keel has, not a new opinion about it — the same findings, the same
/// severities, addressed to the one reader who has not yet seen them.
///
/// The format is documented as `::error file=a.swift,line=1,title=t::message`.
public enum GitHubAnnotations {

    /// One annotation per finding, in the order they were given.
    public static func lines(for diagnostics: [Diagnostic]) -> [String] {
        diagnostics.map { diagnostic in
            line(
                severity: diagnostic.severity == .error ? "error" : "warning",
                location: diagnostic.location,
                title: diagnostic.rule,
                message: diagnostic.message
            )
        }
    }

    /// One annotation per delta entry.
    ///
    /// A regression is an error whatever severity the underlying rule carries:
    /// it is the thing that failed the command, and an annotation that called
    /// it a warning would disagree with the exit code. Fixes are not annotated
    /// — there is no line to put them on, and good news does not need marking
    /// on a diff.
    public static func lines(for delta: ArchitectureDelta) -> [String] {
        delta.entries.compactMap { entry in
            let severity: String
            switch entry.standing {
            case .regression: severity = "error"
            case .change: severity = "warning"
            case .fixed: return nil
            }
            return line(
                severity: severity,
                location: entry.locations.first,
                title: entry.headline,
                message: entry.subject.isEmpty ? entry.headline : entry.subject
            )
        }
    }

    // MARK: - Building

    /// `location` is Keel's own `path:line`, split back apart because GitHub
    /// wants them as separate properties. A finding with nowhere to point is
    /// still emitted, without a file: it annotates the run rather than a line,
    /// which is better than being dropped.
    private static func line(
        severity: String,
        location: String?,
        title: String,
        message: String
    ) -> String {
        var properties = ["title=\(escapedProperty(title))"]

        if let location, let split = split(location) {
            properties.insert("line=\(split.line)", at: 0)
            properties.insert("file=\(escapedProperty(split.file))", at: 0)
        }

        return "::\(severity) \(properties.joined(separator: ","))::\(escapedData(message))"
    }

    private static func split(_ location: String) -> (file: String, line: Int)? {
        guard let colon = location.lastIndex(of: ":"),
              let line = Int(location[location.index(after: colon)...])
        else { return nil }
        return (String(location[location.startIndex..<colon]), line)
    }

    /// Percent-escaped, per the workflow command format. A raw newline ends
    /// the command early and a raw `%` starts an escape, so a message carrying
    /// either would truncate the annotation or corrupt the one after it.
    private static func escapedData(_ text: String) -> String {
        text
            .replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
    }

    /// Property values escape two more characters, because the properties are
    /// themselves comma-separated `key=value` pairs.
    private static func escapedProperty(_ text: String) -> String {
        escapedData(text)
            .replacingOccurrences(of: ":", with: "%3A")
            .replacingOccurrences(of: ",", with: "%2C")
    }
}
