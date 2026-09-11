import Foundation

/// The tool's version, reported by `keel --version`.
///
/// Generated projects record the version that produced them, so a project can
/// be traced back to the templates it came from.
public enum KeelVersion {
    public static let current = "1.0.1"
}
