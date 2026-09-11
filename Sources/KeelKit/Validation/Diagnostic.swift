import Foundation

/// One thing worth telling someone about their project or their toolchain.
///
/// Shared by `check` and `doctor` so both read the same way. A diagnostic
/// always carries what Keel saw, not only what it concluded: a reader who
/// disagrees with the rule can still act on the location.
public struct Diagnostic: Codable, Sendable, Equatable {

    /// How sure Keel is, which is a different question from how much it
    /// matters.
    ///
    /// `error` is reserved for things Keel established structurally and whose
    /// consequence is definite. Everything resting on a naming convention, or
    /// on something syntax cannot fully see, is a `warning` however strongly
    /// Keel suspects it — overstating confidence is the one failure mode that
    /// would make the whole command ignorable.
    public enum Severity: String, Codable, Sendable, Equatable, CaseIterable {
        case error
        case warning

        public var displayName: String {
            switch self {
            case .error: return "error"
            case .warning: return "warning"
            }
        }
    }

    /// Stable identifier, so a rule can be discussed and suppressed by name.
    public let rule: String
    public let severity: Severity
    public let message: String
    /// `Probe/Features/Articles/ArticleListViewModel.swift:12`, when the
    /// finding is about one place.
    public let location: String?
    /// Why it matters, or why Keel might be wrong about it.
    public let detail: String?

    public init(
        rule: String,
        severity: Severity,
        message: String,
        location: String? = nil,
        detail: String? = nil
    ) {
        self.rule = rule
        self.severity = severity
        self.message = message
        self.location = location
        self.detail = detail
    }
}

extension Array where Element == Diagnostic {
    public var errors: [Diagnostic] { filter { $0.severity == .error } }
    public var warnings: [Diagnostic] { filter { $0.severity == .warning } }

    /// Sorted for stable output: severity first, then rule, then location.
    public func ordered() -> [Diagnostic] {
        sorted { left, right in
            if left.severity != right.severity { return left.severity == .error }
            if left.rule != right.rule { return left.rule < right.rule }
            return (left.location ?? "") < (right.location ?? "")
        }
    }
}
