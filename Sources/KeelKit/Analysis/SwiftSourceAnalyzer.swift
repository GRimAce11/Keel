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
            references: visitor.references,
            functionCount: visitor.functionCount,
            asyncFunctionCount: visitor.asyncFunctionCount,
            throwingFunctionCount: visitor.throwingFunctionCount
        )
    }

    static func relativePath(of url: URL, from root: URL?) -> String {
        FilePath.relative(of: url, from: root)
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
    private(set) var references: [TypeUsage] = []
    /// Mirrors `references`, so recognising a repeat stays constant-time. A
    /// single generated file can hold thousands of mentions, and scanning the
    /// list for each one turns a linear parse into a quadratic one.
    private var recorded: Set<TypeUsage> = []
    private(set) var functionCount = 0
    private(set) var asyncFunctionCount = 0
    private(set) var throwingFunctionCount = 0

    /// Names of the types currently being walked into, so a nested type can be
    /// reported as `Outer.Inner` rather than as a second top-level type.
    private var enclosingTypeNames: [String] = []

    /// Who a mention belongs to, innermost first.
    ///
    /// Kept apart from `enclosingTypeNames` because extensions belong on this
    /// stack and not on that one: `extension Profile { }` is where a reference
    /// is written, but it is not a namespace that renames the types declared
    /// inside it.
    private var referenceOwners: [String] = []

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
        let owner = record(node, name: node.name.text, kind: .structure,
                           inheritance: node.inheritanceClause, modifiers: node.modifiers,
                           attributes: node.attributes, members: node.memberBlock)
        recordGenerics(node.genericParameterClause, node.genericWhereClause, owner: owner)
        return enter(node.name.text)
    }

    override func visitPost(_ node: StructDeclSyntax) { leave() }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let owner = record(node, name: node.name.text, kind: .classType,
                           inheritance: node.inheritanceClause, modifiers: node.modifiers,
                           attributes: node.attributes, members: node.memberBlock)
        recordGenerics(node.genericParameterClause, node.genericWhereClause, owner: owner)
        return enter(node.name.text)
    }

    override func visitPost(_ node: ClassDeclSyntax) { leave() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let owner = record(node, name: node.name.text, kind: .enumeration,
                           inheritance: node.inheritanceClause, modifiers: node.modifiers,
                           attributes: node.attributes, members: node.memberBlock)
        recordGenerics(node.genericParameterClause, node.genericWhereClause, owner: owner)
        return enter(node.name.text)
    }

    override func visitPost(_ node: EnumDeclSyntax) { leave() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        let owner = record(node, name: node.name.text, kind: .actorType,
                           inheritance: node.inheritanceClause, modifiers: node.modifiers,
                           attributes: node.attributes, members: node.memberBlock)
        recordGenerics(node.genericParameterClause, node.genericWhereClause, owner: owner)
        return enter(node.name.text)
    }

    override func visitPost(_ node: ActorDeclSyntax) { leave() }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let owner = record(node, name: node.name.text, kind: .protocolType,
                           inheritance: node.inheritanceClause, modifiers: node.modifiers,
                           attributes: node.attributes, members: node.memberBlock)
        recordGenerics(nil, node.genericWhereClause, owner: owner)
        return enter(node.name.text)
    }

    override func visitPost(_ node: ProtocolDeclSyntax) { leave() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        // An extension adding a conformance is how a great deal of Swift is
        // organised — `extension APIError: AppErrorConvertible` is the fact
        // that matters, and it is invisible if extensions are skipped.
        let name = node.extendedType.trimmedDescription
        // What the extension extends, without its generic arguments, since
        // that is the name the declaration itself was written under.
        let extended = TypeName.base(of: name)
        _ = record(node, name: name, kind: .extensionOf,
                   inheritance: node.inheritanceClause, modifiers: node.modifiers,
                   attributes: node.attributes, members: node.memberBlock,
                   referenceOwner: extended)
        recordGenerics(nil, node.genericWhereClause, owner: extended)
        referenceOwners.append(extended)
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        if !referenceOwners.isEmpty { referenceOwners.removeLast() }
    }

    // MARK: Functions

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        functionCount += 1
        let effects = node.signature.effectSpecifiers
        if effects?.asyncSpecifier != nil { asyncFunctionCount += 1 }
        if effects?.throwsClause != nil { throwingFunctionCount += 1 }

        for parameter in node.signature.parameterClause.parameters {
            record(parameter.type, as: .parameterType)
        }
        if let returnClause = node.signature.returnClause {
            record(returnClause.type, as: .returnType)
        }
        recordGenerics(node.genericParameterClause, node.genericWhereClause)
        return .visitChildren
    }

    /// An initializer's parameters are singled out because that is where most
    /// Swift dependency injection is written. "This type cannot be built
    /// without that one" is a stronger statement than "some method takes one".
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        for parameter in node.signature.parameterClause.parameters {
            record(parameter.type, as: .initializerDependency)
        }
        recordGenerics(node.genericParameterClause, node.genericWhereClause)
        return .visitChildren
    }

    // MARK: Properties and other type positions

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // A `let` inside a method body is a mention, not a property. Only a
        // declaration sitting directly in a member block is part of the type's
        // shape, and the parent says which this is.
        let kind: ReferenceKind = node.parent?.is(MemberBlockItemSyntax.self) == true
            ? .propertyType
            : .typeReference

        for binding in node.bindings {
            guard let annotation = binding.typeAnnotation else { continue }
            record(annotation.type, as: kind)
        }
        // Children still matter: `@StateObject private var model = ProfileViewModel()`
        // has no annotation at all, and the relationship is in the initializer.
        return .visitChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.initializer.value, as: .typeReference)
        return .visitChildren
    }

    override func visit(_ node: AsExprSyntax) -> SyntaxVisitorContinueKind {
        record(node.type, as: .typeReference)
        return .visitChildren
    }

    override func visit(_ node: IsExprSyntax) -> SyntaxVisitorContinueKind {
        record(node.type, as: .typeReference)
        return .visitChildren
    }

    // MARK: Expressions

    /// `ProfileViewModel()` — the type is built here.
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let callee = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            record(name: callee.baseName.text, as: .constructorReference, at: callee)
        }
        return .visitChildren
    }

    /// `APIClient.shared` — something is reached through the type's own name.
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        if let base = node.base?.as(DeclReferenceExprSyntax.self) {
            record(name: base.baseName.text, as: .memberReference, at: base)
        }
        return .visitChildren
    }

    // MARK: Recording

    /// Records a declaration and returns the qualified name it was filed under.
    @discardableResult
    private func record(
        _ node: some SyntaxProtocol,
        name: String,
        kind: TypeDeclaration.Kind,
        inheritance: InheritanceClauseSyntax?,
        modifiers: DeclModifierListSyntax,
        attributes: AttributeListSyntax,
        members: MemberBlockSyntax,
        referenceOwner: String? = nil
    ) -> String {
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

        recordInheritance(inheritance, of: kind, owner: referenceOwner ?? qualifiedName)
        return referenceOwner ?? qualifiedName
    }

    /// Turns an inheritance clause into references, using what the grammar
    /// already settles.
    ///
    /// Only a class can name a superclass, and Swift requires it to come
    /// first — so on a class every entry after the first is a conformance, and
    /// on anything else every entry is. The first entry of a class is the one
    /// genuinely open question, and it is left open here for
    /// `TypeGraphBuilder` to close by looking the name up.
    private func recordInheritance(
        _ inheritance: InheritanceClauseSyntax?,
        of kind: TypeDeclaration.Kind,
        owner: String
    ) {
        guard let inheritance else { return }

        for (index, inherited) in inheritance.inheritedTypes.enumerated() {
            let ambiguous = kind == .classType && index == 0
            record(
                inherited.type,
                as: ambiguous ? .inheritsOrConforms : .conformance,
                owner: owner
            )
        }
    }

    private func recordGenerics(
        _ parameters: GenericParameterClauseSyntax?,
        _ whereClause: GenericWhereClauseSyntax?,
        owner: String? = nil
    ) {
        // Walked whole rather than field by field. A generic clause holds
        // nothing but type positions and the parameter names, and the names
        // are tokens rather than types, so a blanket walk picks up exactly the
        // constraints and nothing else.
        if let parameters {
            record(Syntax(parameters), as: .genericConstraint, owner: owner)
        }
        if let whereClause {
            record(Syntax(whereClause), as: .genericConstraint, owner: owner)
        }
    }

    /// Records every type name written inside a piece of syntax.
    private func record(_ node: some SyntaxProtocol, as kind: ReferenceKind, owner: String? = nil) {
        guard let owner = owner ?? referenceOwners.last else { return }

        let line = converter.location(for: node.positionAfterSkippingLeadingTrivia).line
        for name in ReferencedTypeNames.names(in: Syntax(node)) {
            append(TypeUsage(owner: owner, referenced: name, kind: kind, line: line))
        }
    }

    /// Records one bare name from an expression.
    ///
    /// Only names that begin with a capital are collected. That is a
    /// convention rather than a fact, and it is used only to decide what is
    /// worth carrying: every name still has to match a declaration the project
    /// makes before it becomes an edge, so the convention narrows the input
    /// and never widens the output.
    private func record(name: String, as kind: ReferenceKind, at node: some SyntaxProtocol) {
        guard let owner = referenceOwners.last, name.first?.isUppercase == true else { return }

        let line = converter.location(for: node.positionAfterSkippingLeadingTrivia).line
        append(TypeUsage(owner: owner, referenced: name, kind: kind, line: line))
    }

    /// The same mention written twice on one line — `Article(Article.empty)` —
    /// is one fact about the code, so it is stored once.
    private func append(_ usage: TypeUsage) {
        guard usage.owner != usage.referenced, recorded.insert(usage).inserted else { return }
        references.append(usage)
    }

    private func enter(_ name: String) -> SyntaxVisitorContinueKind {
        referenceOwners.append((enclosingTypeNames + [name]).joined(separator: "."))
        enclosingTypeNames.append(name)
        return .visitChildren
    }

    private func leave() {
        if !enclosingTypeNames.isEmpty { enclosingTypeNames.removeLast() }
        if !referenceOwners.isEmpty { referenceOwners.removeLast() }
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

// MARK: - Type names

/// Pulls the names out of a written type.
///
/// A type annotation is rarely one name. `[Article]?` mentions `Article`,
/// `Result<Article, APIError>` mentions three, and `any ArticleRepository`
/// mentions one behind a keyword. Every name in the position is collected,
/// because a dependency wrapped in an array is still a dependency.
enum ReferencedTypeNames {

    static func names(in node: Syntax) -> [String] {
        var found: [String] = []
        collect(node, into: &found)
        return found
    }

    private static func collect(_ node: Syntax, into found: inout [String]) {
        if let identifier = node.as(IdentifierTypeSyntax.self) {
            found.append(identifier.name.text)
            if let generics = identifier.genericArgumentClause {
                collect(Syntax(generics), into: &found)
            }
            return
        }

        if let member = node.as(MemberTypeSyntax.self) {
            // Both spellings. The project may declare the type nested, in
            // which case `Outer.Inner` is its qualified name; or it may be a
            // top-level type that this file happened to qualify by module.
            found.append("\(member.baseType.trimmedDescription).\(member.name.text)")
            found.append(member.name.text)
            if let generics = member.genericArgumentClause {
                collect(Syntax(generics), into: &found)
            }
            return
        }

        for child in node.children(viewMode: .sourceAccurate) {
            collect(child, into: &found)
        }
    }
}
