import Foundation

/// What one rule looks for, why it exists, and why it carries the severity it
/// does.
///
/// Kept apart from the diagnostics it produces so the text is written once. A
/// rule that fires forty times should not carry forty copies of its own
/// rationale, and `--explain` needs somewhere to read it from that is not a
/// finding.
public struct CheckRule: Sendable, Equatable {
    /// Stable identifier, so a rule can be discussed and suppressed by name.
    public let id: String
    /// One line: what the rule looks for.
    public let summary: String
    /// Why it exists, and when Keel may be wrong about it.
    public let explanation: String
    /// Why it is an error, a warning, or either depending on the evidence.
    ///
    /// Written down because the severity model is the command's whole
    /// credibility: a rule that fails a build on a naming convention makes
    /// every other finding easy to dismiss.
    public let severityPolicy: String

    public init(id: String, summary: String, explanation: String, severityPolicy: String) {
        self.id = id
        self.summary = summary
        self.explanation = explanation
        self.severityPolicy = severityPolicy
    }
}

/// Every rule `keel check` knows, in one place.
public enum CheckRules {

    public static func rule(_ id: String) -> CheckRule? {
        all.first { $0.id == id }
    }

    public static var count: Int { all.count }

    public static let all: [CheckRule] = [
        // MARK: Structural

        CheckRule(
            id: "missing-import",
            summary: "An attribute is used without the framework that defines it.",
            explanation: """
                The file says @Model and does not say import SwiftData, so it \
                cannot build. This is the kind of thing a compiler would catch — \
                on a project that compiles. Keel catches it on one that does not.
                """,
            severityPolicy: """
                Error. Structural and certain: the attribute is there, the import \
                is not, and the consequence is a build failure.
                """
        ),
        CheckRule(
            id: "scheme-not-shared",
            summary: "A scheme lives under xcuserdata and is gitignored.",
            explanation: """
                CI and a fresh clone cannot see it, so the project builds on your \
                machine and nowhere else. Xcode: Product › Scheme › Manage \
                Schemes, then tick Shared.
                """,
            severityPolicy: """
                Error. A file either is or is not inside xcuserdata; nothing is \
                being inferred.
                """
        ),

        // MARK: Relationships

        CheckRule(
            id: "view-reaches-networking",
            summary: "A screen refers to a networking client directly.",
            explanation: """
                A screen that holds the network is the hardest kind to test: there \
                is nowhere to put a stub, and the view cannot be rendered without \
                the client existing. The usual shape is a view model or a \
                repository in between.
                """,
            severityPolicy: """
                Error only when both ends are established by the code — the view by \
                its SwiftUI View conformance or UIKit superclass, the client by \
                something other than its name. Otherwise a warning, because \
                "this type is a networking client" is then a guess from a suffix.
                """
        ),
        CheckRule(
            id: "view-reaches-persistence",
            summary: "A screen refers to a persistence type directly.",
            explanation: """
                A view holding a stored model is pinned to the store: it cannot be \
                previewed, tested or reused without one. SwiftData's @Query is the \
                deliberate exception and is not this — that is a property wrapper, \
                not a reference to a repository or a controller.
                """,
            severityPolicy: """
                Error only when both ends are established by the code — a @Model \
                attribute or an NSManagedObject superclass on one side, a View \
                conformance on the other. Otherwise a warning.
                """
        ),
        CheckRule(
            id: "view-constructs-infrastructure",
            summary: "A screen builds infrastructure the project injects elsewhere.",
            explanation: """
                The project already hands this type to others through an \
                initializer, so something has decided it is a dependency. A view \
                constructing its own copy opts out of that decision, and out of \
                every test that would have replaced it.
                """,
            severityPolicy: """
                Error only when the view's role and the construction are both \
                established by the code. Otherwise a warning.
                """
        ),
        CheckRule(
            id: "concrete-repository-dependency",
            summary: "Something depends on a repository's concrete type, not its protocol.",
            explanation: """
                This project puts protocols in front of its repositories — most of \
                them, anyway, which is what makes it a convention here rather than \
                an opinion of Keel's. Depending on the concrete type walks around \
                that boundary and cannot be given a stub. The composition root is \
                exempt: knowing the concrete types is its job.
                """,
            severityPolicy: """
                Warning. The boundary is established by what the project mostly \
                does, and "mostly" is not certainty.
                """
        ),
        CheckRule(
            id: "shared-code-depends-on-feature",
            summary: "Code in a shared folder depends on a feature.",
            explanation: """
                Core and Shared exist to be used by features. A dependency running \
                the other way means the shared code cannot be used without that \
                feature, and the next feature to need it drags the first one along.
                """,
            severityPolicy: """
                Warning. The relationship is read from the code, but which folders \
                count as shared comes from their names — so the direction being \
                wrong rests on a convention.
                """
        ),
        CheckRule(
            id: "feature-dependency-cycle",
            summary: "Two or more features depend on each other in a loop.",
            explanation: """
                Neither feature can be understood, moved or extracted without the \
                other. This is the relationship an import graph cannot show: in a \
                single-target app both features compile into the same module, so \
                no import ever crosses between them and nothing else would report \
                it.
                """,
            severityPolicy: """
                Warning. A cycle needs no rule to be wrong, but what counts as a \
                feature comes from folder names, so the grouping is conventional.
                """
        ),
        CheckRule(
            id: "layer-inversion",
            summary: "A dependency points back out through the project's own layers.",
            explanation: """
                Domain is the innermost layer: Presentation and Data both depend on \
                it, and it depends on neither. A reference running the other way \
                inverts that. Presentation reaching Data is not this — that is a \
                shortcut rather than an inversion, and it is reported as screen \
                data instead.
                """,
            severityPolicy: """
                Warning. The references are read from the code; the layers are \
                folder names.
                """
        ),

        // MARK: Conventions

        CheckRule(
            id: "view-model-not-main-actor",
            summary: "A view model is not marked @MainActor.",
            explanation: """
                A type driving a view should be isolated to the main actor. Keel \
                may be wrong: isolation inherited from a protocol, an enclosing \
                type or a module-wide default is not visible to syntax.
                """,
            severityPolicy: "Warning, always. Syntax cannot see every source of isolation."
        ),
        CheckRule(
            id: "view-model-not-observable",
            summary: "A view model is neither @Observable nor an ObservableObject.",
            explanation: """
                A view reading this will not redraw when it changes. If the state \
                lives somewhere else entirely, the name is what is misleading.
                """,
            severityPolicy: "Warning, always. It rests on the type's name meaning what it says."
        ),
        CheckRule(
            id: "view-model-observation-inconsistent",
            summary: "A view model observes differently from the rest of the project.",
            explanation: """
                The project has settled on one mechanism and this type uses the \
                other. Both work; mixing them means every reader has to check \
                which one they are looking at. Reported only where the project \
                actually has a settled convention to depart from.
                """,
            severityPolicy: "Warning, always. Keel has no opinion about which mechanism is right."
        ),
        CheckRule(
            id: "view-imports-infrastructure",
            summary: "A file declaring a screen imports storage or the network.",
            explanation: """
                Judged per file rather than per type: the import is a property of \
                the file, and Keel cannot see which declaration uses it. Both are \
                here, which is worth knowing and is not proof.
                """,
            severityPolicy: "Warning, always. The import and the view merely share a file."
        ),
        CheckRule(
            id: "repository-without-protocol",
            summary: "A repository has no abstraction in front of it.",
            explanation: """
                Everything depending on this is pinned to the concrete type and \
                cannot be given a stub in a test.
                """,
            severityPolicy: "Warning, always. It rests on the Repository suffix meaning what it says."
        ),
        CheckRule(
            id: "inconsistent-feature-layers",
            summary: "Feature folders are not divided the same way as each other.",
            explanation: """
                Keel has no opinion about whether a feature should have a Domain \
                folder — only about four features disagreeing with each other.
                """,
            severityPolicy: "Warning, always. Folder layout is a convention."
        ),
        CheckRule(
            id: "no-test-target",
            summary: "The project has no test target.",
            explanation: "Nothing here can be verified automatically.",
            severityPolicy: "Warning. A project may be tested somewhere Keel cannot see."
        ),
        CheckRule(
            id: "test-target-without-framework",
            summary: "There is a test target, but nothing imports a testing framework.",
            explanation: """
                The target may be empty, or its tests may live somewhere Keel did \
                not look.
                """,
            severityPolicy: "Warning. An empty test target is a contradiction, not a failure."
        ),
    ]
}
