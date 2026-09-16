import Foundation

/// Materialising a revision of the project so it can be scanned.
///
/// Every operation here is read-only with respect to the user's working tree.
/// `git worktree add --detach` builds a second checkout in a temporary
/// directory and leaves the index, HEAD and the files in front of you exactly
/// as they were — which `git checkout` and `git stash` do not. A tool that
/// moves somebody's working tree out from under them is one they stop running
/// in CI, and stop trusting locally.
public enum GitRevision {

    public enum Failure: Error, CustomStringConvertible, Equatable {
        case gitNotInstalled
        case notARepository(String)
        case unknownRevision(String)
        case shallowRepository(String)
        case noProject(revision: String)
        case worktreeFailed(String)

        public var description: String {
            switch self {
            case .gitNotInstalled:
                return "git is not installed, and `keel diff` compares revisions."
            case .notARepository(let path):
                return "\(path) is not inside a git repository."
            case .unknownRevision(let spec):
                return "No revision named \(spec)."
            case .shallowRepository(let spec):
                return """
                    This is a shallow clone, so \(spec) is not present to compare against.
                    """
            case .noProject(let revision):
                return "No Xcode project at \(revision), so there is nothing to compare."
            case .worktreeFailed(let message):
                return "Could not read that revision: \(message)"
            }
        }

        /// What to do about it, when there is something to do.
        public var remedy: String? {
            switch self {
            case .shallowRepository:
                // Worth spelling out: CI checkouts default to depth 1, and
                // this is the failure that produces.
                return "Check out with full history — `fetch-depth: 0` on actions/checkout."
            case .notARepository:
                return "`keel diff` needs history. `keel inspect` works without it."
            default:
                return nil
            }
        }
    }

    // MARK: - Revision specs

    /// What to compare, read from one argument.
    ///
    /// `main..HEAD` is two revisions. `main` is that revision against what is
    /// on disk now, because comparing your uncommitted work to a branch is the
    /// thing people want most often. Nothing at all means `HEAD`.
    public struct Comparison: Equatable {
        public let before: String
        /// `nil` means the working tree as it currently is.
        public let after: String?

        public var label: String { "\(before)..\(after ?? "working tree")" }

        public init(before: String, after: String?) {
            self.before = before
            self.after = after
        }

        public static func parse(_ spec: String?) -> Comparison {
            guard let spec, !spec.isEmpty else {
                return Comparison(before: "HEAD", after: nil)
            }
            guard let range = spec.range(of: "..") else {
                return Comparison(before: spec, after: nil)
            }
            let before = String(spec[spec.startIndex..<range.lowerBound])
            let after = String(spec[range.upperBound...])
            return Comparison(
                before: before.isEmpty ? "HEAD" : before,
                after: after.isEmpty ? nil : after
            )
        }
    }

    // MARK: - Repository

    /// The repository root containing `path`, and where `path` sits inside it.
    ///
    /// The second half matters: a worktree is a checkout of the whole
    /// repository, and the project may live in a subdirectory of it. Scanning
    /// the worktree root would scan the wrong directory for anyone whose
    /// `.xcodeproj` is not at the top.
    public static func locate(_ path: URL) throws -> (root: URL, relativePath: String) {
        guard Shell.isAvailable("git") else { throw Failure.gitNotInstalled }

        let result = Shell.run("git", ["rev-parse", "--show-toplevel"], in: path)
        guard result.succeeded else { throw Failure.notARepository(path.path) }

        let root = URL(
            fileURLWithPath: result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        ).resolvingSymlinksInPath()
        let full = path.resolvingSymlinksInPath().path
        let prefix = root.path + "/"

        return (root, full.hasPrefix(prefix) ? String(full.dropFirst(prefix.count)) : "")
    }

    public static func resolve(_ spec: String, in root: URL) throws -> String {
        let result = Shell.run("git", ["rev-parse", "--verify", "\(spec)^{commit}"], in: root)
        guard result.succeeded else {
            // A shallow clone has the ref but not the commit, and the plain
            // "unknown revision" would send somebody looking for a typo.
            if isShallow(root) { throw Failure.shallowRepository(spec) }
            throw Failure.unknownRevision(spec)
        }
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isShallow(_ root: URL) -> Bool {
        Shell.run("git", ["rev-parse", "--is-shallow-repository"], in: root)
            .standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    // MARK: - Worktrees

    /// Checks `revision` out into a temporary directory, hands its path to
    /// `body`, and removes it afterwards however `body` ends.
    public static func withWorktree<T>(
        _ revision: String,
        of root: URL,
        _ body: (URL) throws -> T
    ) throws -> T {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-diff-\(UUID().uuidString)")

        let added = Shell.run(
            "git",
            ["worktree", "add", "--detach", "--quiet", directory.path, revision],
            in: root
        )
        guard added.succeeded else {
            if isShallow(root) { throw Failure.shallowRepository(revision) }
            throw Failure.worktreeFailed(
                added.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        defer {
            Shell.run("git", ["worktree", "remove", "--force", directory.path], in: root)
            // `worktree remove` is enough when it works. When it does not —
            // a file mode git cannot change, most often — the directory would
            // otherwise be left in the user's temp space forever.
            try? FileManager.default.removeItem(at: directory)
        }

        return try body(directory)
    }
}
