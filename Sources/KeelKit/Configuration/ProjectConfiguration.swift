import Foundation

/// Everything needed to generate a project, validated and resolved.
///
/// Built once from either the interactive prompts or command line flags, so
/// generation never has to care which one the developer used. Codable so a
/// configuration can be recorded alongside the project it produced.
public struct ProjectConfiguration: Codable, Equatable, Sendable {

    public let name: ProjectName
    public let bundleIdentifier: String
    public let minimumIOSVersion: String
    public let components: Set<Component>

    /// Components dropped because something they depend on is absent.
    ///
    /// Reported rather than applied silently — a project that quietly differs
    /// from what was asked for is worse than one that explains itself.
    public let adjustments: [Adjustment]

    public struct Adjustment: Codable, Equatable, Sendable {
        public let component: Component
        public let reason: String
    }

    // MARK: - Defaults

    public enum Defaults {
        /// `@Observable` requires iOS 17, and Xcode 16's synchronized folder
        /// groups are what keep the project file out of the way. Both floors
        /// land in the same place.
        public static let minimumIOSVersion = "17.0"
        public static let bundleIdentifierPrefix = "com.example"
    }

    // MARK: - Init

    public init(
        name: ProjectName,
        bundleIdentifierPrefix: String = Defaults.bundleIdentifierPrefix,
        minimumIOSVersion: String = Defaults.minimumIOSVersion,
        components: Set<Component> = Set(Component.allCases)
    ) {
        self.name = name
        self.bundleIdentifier = "\(bundleIdentifierPrefix).\(name.slug)"
        self.minimumIOSVersion = minimumIOSVersion

        let resolution = Self.resolve(components)
        self.components = resolution.components
        self.adjustments = resolution.adjustments
    }

    // MARK: - Dependency resolution

    /// Drops any component whose requirements are not met, iterating to a fixed
    /// point so a chain of dependencies settles in one pass.
    private static func resolve(
        _ requested: Set<Component>
    ) -> (components: Set<Component>, adjustments: [Adjustment]) {
        var resolved = requested
        var adjustments: [Adjustment] = []
        var didChange = true

        while didChange {
            didChange = false
            for component in resolved.sorted(by: { $0.rawValue < $1.rawValue }) {
                let missing = component.requires.filter { !resolved.contains($0) }
                guard !missing.isEmpty else { continue }

                resolved.remove(component)
                adjustments.append(
                    Adjustment(
                        component: component,
                        reason: "needs \(missing.map(\.title).joined(separator: " and "))"
                    )
                )
                didChange = true
            }
        }

        return (resolved, adjustments)
    }

    // MARK: - Queries

    public func includes(_ component: Component) -> Bool {
        components.contains(component)
    }
}
