import Foundation

/// Checks that the machine can actually build what Keel generates.
///
/// Unlike every other analysis in Keel, this one runs things — `swift`,
/// `xcodebuild`, `git`. That is the whole point: the question is not what the
/// project says, it is what this machine will do. It still runs no agent and
/// touches no network.
public struct Doctor {

    /// What Keel generates targets, so this is the floor worth checking for.
    static let minimumSwift = "6.0"

    /// The project to inspect alongside the toolchain, when there is one.
    public let model: ProjectModel?

    public init(model: ProjectModel? = nil) {
        self.model = model
    }

    public func diagnose() -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        diagnostics += swiftToolchain()
        diagnostics += xcode()
        diagnostics += git()
        diagnostics += project()
        return diagnostics
    }

    // MARK: - Toolchain

    private func swiftToolchain() -> [Diagnostic] {
        guard let version = Self.swiftVersion() else {
            return [
                Diagnostic(
                    rule: "swift-missing",
                    severity: .error,
                    message: "swift is not on your PATH.",
                    detail: "Install Xcode, or the Swift toolchain from swift.org."
                )
            ]
        }

        guard VersionNumber(version) >= VersionNumber(Self.minimumSwift) else {
            return [
                Diagnostic(
                    rule: "swift-too-old",
                    severity: .error,
                    message: "Swift \(version) is older than \(Self.minimumSwift).",
                    detail: "Generated projects use Swift \(Self.minimumSwift) features and will not build."
                )
            ]
        }

        return []
    }

    private func xcode() -> [Diagnostic] {
        let selected = Shell.run("xcode-select", ["-p"])
        guard selected.succeeded else {
            return [
                Diagnostic(
                    rule: "xcode-not-selected",
                    severity: .error,
                    message: "No Xcode is selected.",
                    detail: "Run `sudo xcode-select -s /Applications/Xcode.app`."
                )
            ]
        }

        let path = selected.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasSuffix("CommandLineTools") {
            return [
                Diagnostic(
                    rule: "command-line-tools-only",
                    severity: .error,
                    message: "Only the Command Line Tools are selected, not a full Xcode.",
                    detail: """
                        Generated projects are Xcode projects and need a simulator to run. \
                        Run `sudo xcode-select -s /Applications/Xcode.app`.
                        """
                )
            ]
        }

        return []
    }

    private func git() -> [Diagnostic] {
        guard !Shell.isAvailable("git") else { return [] }
        return [
            Diagnostic(
                rule: "git-missing",
                severity: .warning,
                message: "git is not on your PATH.",
                detail: "`keel new` will still generate a project; it just will not initialise a repository."
            )
        ]
    }

    // MARK: - Project

    /// Toolchain problems that only matter because of this project.
    private func project() -> [Diagnostic] {
        guard let model else { return [] }
        var diagnostics: [Diagnostic] = []

        if let required = model.swiftVersion,
           let installed = Self.swiftVersion(),
           VersionNumber(installed) < VersionNumber(required) {
            diagnostics.append(
                Diagnostic(
                    rule: "swift-older-than-project",
                    severity: .error,
                    message: "The project targets Swift \(required) but this machine has \(installed).",
                    detail: "Update Xcode, or lower SWIFT_VERSION in the project."
                )
            )
        }

        if model.appTargets.isEmpty {
            diagnostics.append(
                Diagnostic(
                    rule: "no-app-target",
                    severity: .warning,
                    message: "No application target found.",
                    detail: "This may be a framework or a package rather than an app."
                )
            )
        }

        return diagnostics
    }

    // MARK: - Helpers

    /// The compiler's version, from the first line of `swift --version`.
    ///
    /// Parsed rather than assumed: the line's wording differs between Apple
    /// and swift.org toolchains, but a dotted version always appears in it.
    public static func swiftVersion() -> String? {
        let result = Shell.run("swift", ["--version"])
        guard result.succeeded else { return nil }
        return version(in: result.standardOutput + result.standardError)
    }

    static func version(in text: String) -> String? {
        // "Apple Swift version 6.1.2 (...)" and "Swift version 6.1 (...)" both
        // yield 6.1.x; the first dotted number after "version" is the one.
        guard let range = text.range(of: #"version (\d+(\.\d+)+)"#, options: .regularExpression)
        else { return nil }
        return String(text[range].dropFirst("version ".count))
    }
}

extension VersionNumber {
    static func >= (lhs: VersionNumber, rhs: VersionNumber) -> Bool {
        !(lhs < rhs)
    }
}
