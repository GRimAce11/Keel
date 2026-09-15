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
    /// The lines the finding was read from.
    ///
    /// A relationship-based finding is only arguable if it says where it came
    /// from. "This view depends on that client" is a claim; "at these four
    /// lines" is something a reader can open and disagree with.
    public let evidence: [Evidence]
    /// How one thing reaches another, when the finding is about a chain rather
    /// than a single reference — `Profile → Session → Profile`.
    public let path: [String]?

    public init(
        rule: String,
        severity: Severity,
        message: String,
        location: String? = nil,
        detail: String? = nil,
        evidence: [Evidence] = [],
        path: [String]? = nil
    ) {
        self.rule = rule
        self.severity = severity
        self.message = message
        self.location = location
        self.detail = detail
        self.evidence = Array(evidence.prefix(Self.evidenceLimit))
        self.path = path
    }

    /// One place the finding was read from.
    public struct Evidence: Codable, Sendable, Equatable {
        public let location: String
        /// What the line said, in the terms the finding is about:
        /// `property: APIClient`, `import SwiftData`.
        public let statement: String

        public init(location: String, statement: String) {
            self.location = location
            self.statement = statement
        }
    }

    /// Capped for the same reason architecture evidence is: a finding covering
    /// forty references should not print forty lines. The graphs hold them all
    /// for anything that wants the full set.
    static let evidenceLimit = 5
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
