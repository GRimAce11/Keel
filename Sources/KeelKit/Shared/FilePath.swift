import Foundation

/// Working out where a file sits relative to a root.
///
/// Sounds trivial and is not, for two reasons that bit at once.
///
/// macOS symlinks `/tmp` to `/private/tmp` and `/var` to `/private/var`, and
/// `standardizedFileURL` does not resolve symlinks — it only tidies `..` and
/// `.`. So a root recorded as `/tmp/x` and a file enumerated from it as
/// `/private/tmp/x/y` are the same place and do not look it.
///
/// And stripping a prefix is not a substring replacement. Replacing
/// `/tmp/x/` inside `/private/tmp/x/y` matches eight characters in, leaving
/// `/private` fused to whatever followed — which is how `keel new` once
/// produced `privateMyApp.xcodeproj` for anyone whose templates lived under a
/// symlinked path.
enum FilePath {

    /// `url` expressed relative to `root`, or its full path when it is not
    /// inside `root` at all.
    ///
    /// Both sides are resolved first, so two spellings of one directory agree.
    static func relative(of url: URL, from root: URL) -> String {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let prefix = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"

        // A prefix strip, not a replacement: only the front of the string may
        // match, and a miss returns the path untouched rather than a mangled
        // hybrid of the two.
        guard path.hasPrefix(prefix) else { return path }
        return String(path.dropFirst(prefix.count))
    }

    /// The same, for a root that may not be known.
    static func relative(of url: URL, from root: URL?) -> String {
        guard let root else { return url.path }
        return relative(of: url, from: root)
    }
}
