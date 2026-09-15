import Foundation

/// Places a file in the project's layout.
///
/// Shared by both graphs on purpose. The import graph says "the Profile feature
/// imports SwiftData" and the type graph says "a type in the Profile feature
/// refers to one in Settings"; if each worked out what "the Profile feature"
/// meant for itself, the two could disagree about the same file and nothing
/// would catch it.
///
/// Everything here is read from the directory layout, because with synchronized
/// folder groups the project file says nothing about it. That makes ownership a
/// naming-based fact, and both graphs record it as one.
struct FileOwnershipResolver {

    let targets: [Target]
    let modules: [Module]
    let features: [Feature]

    /// Longest match wins, so a file inside a feature is attributed to the
    /// feature rather than to the `Features` folder above it.
    func ownership(of path: String) -> FileOwnership {
        let target = targets
            .map(\.name)
            .filter { path == $0 || path.hasPrefix($0 + "/") }
            .max(by: { $0.count < $1.count })

        if let feature = features
            .filter({ path.hasPrefix($0.path + "/") })
            .max(by: { $0.path.count < $1.path.count })
        {
            return FileOwnership(
                target: target,
                module: modules.first { path.hasPrefix($0.path + "/") }?.name,
                feature: feature.name,
                layer: layer(of: path, within: feature)
            )
        }

        let module = modules
            .filter { path.hasPrefix($0.path + "/") }
            .max(by: { $0.path.count < $1.path.count })

        return FileOwnership(target: target, module: module?.name, feature: nil, layer: nil)
    }

    /// The feature subfolder a file sits in, when the feature has any.
    private func layer(of path: String, within feature: Feature) -> String? {
        let remainder = path.dropFirst(feature.path.count + 1)
        guard let first = remainder.split(separator: "/").first.map(String.init),
              feature.layers.contains(first)
        else { return nil }
        return first
    }
}
