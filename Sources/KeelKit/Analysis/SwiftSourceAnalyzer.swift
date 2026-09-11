import Foundation
import SwiftParser
import SwiftSyntax

/// Reads Swift source with a real parser.
///
/// The earlier scan matched substrings, which is fine for "does this project
/// import SwiftUI" and useless for anything structural: a regex cannot tell a
/// conformance from the same words in a comment, an `actor` declaration from a
/// variable called `actor`, or a nested type from a top-level one.
///
/// Parsing is source-only — no compiler, no build, no index. That keeps
/// analysis working on a project that does not currently compile, and keeps it
/// fast enough to run over a few hundred files on every invocation.
/// Stateless, and marked `Sendable` so the parallel parse in `ProjectScanner`
/// can share one instance across threads without copying it per file.
public struct SwiftSourceAnalyzer: Sendable {

    public init() {}

    /// Parses one file. Returns `nil` if it cannot be read.
    ///
    /// A file that fails to *parse* still returns results: SwiftParser recovers
    /// from syntax errors and produces a tree for everything it did understand,
    /// which is the right behaviour for a tool that must work on broken code.
    public func analyze(fileAt url: URL, relativeTo root: URL? = nil) -> FileAnalysis? {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return analyze(
            source: source,
            path: Self.relativePath(of: url, from: root)
        )
    }

    public func analyze(source: String, path: String) -> FileAnalysis {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: path, tree: tree)

        let visitor = DeclarationVisitor(path: path, converter: converter)
        visitor.walk(tree)

        return FileAnalysis(
            path: path,
            imports: visitor.imports,
            types: visitor.types,
            functionCount: visitor.functionCount,
            asyncFunctionCount: visitor.asyncFunctionCount,
            throwingFunctionCount: visitor.throwingFunctionCount
        )
    }

    static func relativePath(of url: URL, from root: URL?) -> String {
        guard let root else { return url.path }
        let prefix = root.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }
}

// MARK: - Visitor

/// Collects declarations from one file.
///
/// A class rather than a struct because `SyntaxVisitor` requires it, and
/// because accumulating into reference state avoids threading a result through
/// every visit method.
private final class DeclarationVisitor: SyntaxVisitor {

    let path: String
    let converter: SourceLocationConverter

    private(set) var imports: [ImportDeclaration] = []
    private(set) var types: [TypeDeclaration] = []
    private(set) var functionCount = 0
    private(set) var asyncFunctionCount = 0
    private(set) var throwingFunctionCount = 0

    /// Names of the types currently being walked into, so a nested type can be
    /// reported as `Outer.Inner` rather than as a second top-level type.
    private var enclosingTypeNames: [String] = []

    init(path: String, converter: SourceLocationConverter) {
        self.path = path
        self.converter = converter
        // Skipping bodies would also skip nested types, and the async/throws
        // counts come from signatures rather than bodies anyway.
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: Imports

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.path.map(\.name.text).joined(separator: ".")
        guard !name.isEmpty else { return .skipChildren }

        let line = converter.location(for: node.positionAfterSkippingLeadingTrivia).line
        imports.append(ImportDeclaration(module: name, line: line))
        return .skipChildren
    }

    // MARK: Types

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node, name: node.name.text, kind: .structure,
               inheritance: node.inheritanceClause, modifiers: node.modifiers,
               attributes: node.attributes, members: node.memberBlock)
        return enter(node.name.text)
    }

    override func visitPost(_ node: StructDeclSyntax) { leave() }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node, name: node.name.text, kind: .classType,
               inheritance: node.inheritanceClause, modifiers: node.modifiers,
               attributes: node.attributes, members: node.memberBlock)
        return enter(node.name.text)
    }

    override func visitPost(_ node: ClassDeclSyntax) { leave() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node, name: node.name.text, kind: .enumeration,
               inheritance: node.inheritanceClause, modifiers: node.modifiers,
               attributes: node.attributes, members: node.memberBlock)
        return enter(node.name.text)
    }

    override func visitPost(_ node: EnumDeclSyntax) { leave() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node, name: node.name.text, kind: .actorType,
               inheritance: node.inheritanceClause, modifiers: node.modifiers,
               attributes: node.attributes, members: node.memberBlock)
        return enter(node.name.text)
    }

    override func visitPost(_ node: ActorDeclSyntax) { leave() }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node, name: node.name.text, kind: .protocolType,
               inheritance: node.inheritanceClause, modifiers: node.modifiers,
               attributes: node.attributes, members: node.memberBlock)
        return enter(node.name.text)
    }

    override func visitPost(_ node: ProtocolDeclSyntax) { leave() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        // An extension adding a conformance is how a great deal of Swift is
        // organised — `extension APIError: AppErrorConvertible` is the fact
        // that matters, and it is invisible if extensions are skipped.
        let name = node.extendedType.trimmedDescription
        record(node, name: name, kind: .extensionOf,
               inheritance: node.inheritanceClause, modifiers: node.modifiers,
               attributes: node.attributes, members: node.memberBlock)
        return .visitChildren
    }

    // MARK: Functions

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        functionCount += 1
        let effects = node.signature.effectSpecifiers
        if effects?.asyncSpecifier != nil { asyncFunctionCount += 1 }
        if effects?.throwsClause != nil { throwingFunctionCount += 1 }
        return .visitChildren
    }

    // MARK: Recording

    private func record(
        _ node: some SyntaxProtocol,
        name: String,
        kind: TypeDeclaration.Kind,
        inheritance: InheritanceClauseSyntax?,
        modifiers: DeclModifierListSyntax,
        attributes: AttributeListSyntax,
        members: MemberBlockSyntax
    ) {
        let qualifiedName = (enclosingTypeNames + [name]).joined(separator: ".")

        types.append(
            TypeDeclaration(
                name: qualifiedName,
                kind: kind,
                path: path,
                line: converter.location(for: node.positionAfterSkippingLeadingTrivia).line,
                // Syntax alone cannot tell a superclass from a protocol: both
                // appear in the same clause and only the compiler knows which
                // is which. They are reported together, named for what they
                // are — inherited types.
                inheritedTypes: inheritance?.inheritedTypes.map {
                    $0.type.trimmedDescription
                } ?? [],
                attributes: Self.names(of: attributes),
                accessLevel: Self.accessLevel(from: modifiers),
                isFinal: modifiers.contains { $0.name.text == "final" },
                memberCount: members.members.count
            )
        )
    }

    private func enter(_ name: String) -> SyntaxVisitorContinueKind {
        enclosingTypeNames.append(name)
        return .visitChildren
    }

    private func leave() {
        if !enclosingTypeNames.isEmpty { enclosingTypeNames.removeLast() }
    }

    // MARK: Helpers

    /// `@Observable`, `@MainActor`, `@Model` — the attribute name without its
    /// arguments, so `@available(iOS 17, *)` records as `available`.
    private static func names(of attributes: AttributeListSyntax) -> [String] {
        attributes.compactMap { element in
            guard case .attribute(let attribute) = element else { return nil }
            return attribute.attributeName.trimmedDescription
        }
    }

    private static func accessLevel(from modifiers: DeclModifierListSyntax) -> String? {
        let levels: Set<String> = ["open", "public", "package", "internal", "fileprivate", "private"]
        return modifiers.map(\.name.text).first { levels.contains($0) }
    }
}
