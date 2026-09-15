import Foundation

/// How Keel reads a written type name.
///
/// One copy, because three had grown: the parser stripping generics off an
/// extended type, the type graph taking the last component of a qualified
/// name, and the detector stripping generics again to recognise a superclass.
/// They agreed, which is the dangerous kind of duplication — the next edit to
/// any one of them would have made a project's own analysis disagree with
/// itself, and nothing would have caught it.
enum TypeName {

    /// `Array<Int>` -> `Array`. `Outer.Inner` is left alone: the dot is part
    /// of the name, and dropping it would confuse a nested type with a
    /// top-level one.
    static func base(of written: String) -> String {
        guard let angle = written.firstIndex(of: "<") else { return written }
        return String(written[written.startIndex..<angle])
    }

    /// `Outer.Inner` -> `Inner`. The name as it would be written from inside
    /// the scope that declares it.
    static func simple(of qualified: String) -> String {
        qualified.split(separator: ".").last.map(String.init) ?? qualified
    }

    /// Whether one name nests inside the other, or they are the same.
    ///
    /// A type and the types nested inside it are one component, not two that
    /// depend on each other.
    static func areTheSameComponent(_ first: String, _ second: String) -> Bool {
        first == second
            || first.hasPrefix(second + ".")
            || second.hasPrefix(first + ".")
    }
}

/// Prose the reports share.
///
/// Evidence has to be countable to be arguable, and it has to read the same
/// way wherever it is printed — a finding that says "2 views" in one command
/// and "2 view's" in another is a finding nobody trusts.
enum Prose {

    /// "a, b and c" — no serial comma, matching the prose everywhere else.
    static func list(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        guard items.count > 1 else { return last }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }

    /// The same, with duplicates removed and sorted, for lists built from a
    /// graph where the same name can appear twice.
    static func list(unique items: [String]) -> String {
        list(Array(Set(items)).sorted())
    }

    /// "1 view" / "4 views". The plural is spelled out where adding an `s`
    /// would be wrong — "dependencys".
    static func count(_ number: Int, _ singular: String, plural: String? = nil) -> String {
        guard number != 1 else { return "\(number) \(singular)" }
        return "\(number) \(plural ?? singular + "s")"
    }
}
