import Foundation

/// Resolves what the parser saw into a graph of the project's own types.
///
/// The parser reports that `ProfileView` mentions the name `ProfileViewModel`.
/// Only the project as a whole can say whether that name is something the
/// project declares — and if it is not, the mention is Apple's or a package's
/// and has no place in a graph of this codebase. So every mention is looked up,
/// and anything that does not match a declaration is dropped rather than
/// reported weakly. The same rule the import graph follows: what cannot be
/// placed is not asserted.
struct TypeGraphBuilder {

    /// Apple classes that iOS code subclasses, and what subclassing one makes a
    /// type.
    ///
    /// Short on purpose. It exists so that `class ProfileViewController:
    /// UIViewController` is known to be a view controller from the code rather
    /// than from its name, which is the difference between evidence and a
    /// guess. Anything not listed falls through to the naming rules and is
    /// marked as naming-derived — never silently treated as one of these.
    static let appleSuperclasses: [String: TypeRole] = [
        "UIViewController": .viewController,
        "UITableViewController": .viewController,
        "UICollectionViewController": .viewController,
        "UINavigationController": .viewController,
        "UITabBarController": .viewController,
        "UISplitViewController": .viewController,
        "UIPageViewController": .viewController,
        "UIHostingController": .viewController,
        "NSViewController": .viewController,
        "UIView": .view,
        "UIControl": .view,
        "UITableViewCell": .view,
        "UICollectionViewCell": .view,
        "UIStackView": .view,
        "UIScrollView": .view,
        "UILabel": .view,
        "UIButton": .view,
        "UIImageView": .view,
        "NSView": .view,
        "NSManagedObject": .persistence,
    ]

    /// Apple protocols whose conformance settles what a type is for.
    static let appleConformances: [String: TypeRole] = [
        "View": .view,
        "App": .view,
        "Scene": .view,
        "UIViewRepresentable": .view,
        "UIViewControllerRepresentable": .view,
        "PersistentModel": .persistence,
    ]

    /// Name endings that suggest a purpose, longest first so that
    /// `NetworkService` is weighed against `Service` and not against `work`.
    ///
    /// Every one of these is a convention. A type called `ArticleRepository`
    /// is a repository because somebody named it one, and the node says so.
    static let roleSuffixes: [(suffix: String, role: TypeRole)] = [
        ("ViewController", .viewController),
        ("ViewModel", .viewModel),
        ("Presenter", .viewModel),
        ("Repository", .repository),
        ("DataSource", .repository),
        ("Store", .repository),
        ("APIClient", .client),
        ("Client", .client),
        ("Endpoint", .client),
        ("API", .client),
        ("UseCase", .service),
        ("Interactor", .service),
        ("Service", .service),
        ("Manager", .service),
        ("Coordinator", .coordinator),
        ("Router", .coordinator),
        ("Container", .container),
        ("Resolver", .container),
        ("Assembly", .container),
        ("Screen", .view),
        ("View", .view),
        ("Cell", .view),
        ("Entity", .model),
        ("DTO", .model),
        ("Model", .model),
    ]

    let inputs: Inputs

    /// What the builder needs, before a `ProjectModel` exists to hold it.
    struct Inputs {
        let targets: [Target]
        let modules: [Module]
        let features: [Feature]
        /// Production sources only.
        ///
        /// Tests are left out for the same reason architecture detection
        /// leaves them out: a test double imitates the real thing on purpose.
        /// Counting one would let a stub named `StubAPIClient` become part of
        /// the architecture, and would turn every `ProfileViewTests` that
        /// builds an `APIClient` into a view reaching a networking client.
        let analysis: SourceAnalysis
    }

    func build() -> TypeGraph {
        let declarations = inputs.analysis.declaredTypes
        guard !declarations.isEmpty else { return .empty }

        let resolver = FileOwnershipResolver(
            targets: inputs.targets, modules: inputs.modules, features: inputs.features
        )

        // Two indexes, because a name is written both ways. `Outer.Inner` is
        // matched exactly; a bare `Inner` is matched on its last component.
        //
        // Both hold every declaration rather than the last one seen. Two files
        // can declare the same name — legally, in different scopes, or by
        // accident — and an index that keeps one of them would report a
        // resolved edge where there is really a choice nobody made.
        var byQualifiedName: [String: [TypeDeclaration]] = [:]
        var bySimpleName: [String: [TypeDeclaration]] = [:]
        for declaration in declarations {
            byQualifiedName[declaration.name, default: []].append(declaration)
            bySimpleName[TypeName.simple(of: declaration.name), default: []].append(declaration)
        }

        let nodes = declarations
            .map { declaration -> TypeNode in
                let (role, support) = Self.role(of: declaration)
                return TypeNode(
                    name: declaration.name,
                    kind: declaration.kind,
                    path: declaration.path,
                    line: declaration.line,
                    role: role,
                    roleSupport: support,
                    owner: resolver.ownership(of: declaration.path)
                )
            }
            .sorted { $0.name < $1.name }

        let references = resolve(
            byQualifiedName: byQualifiedName,
            bySimpleName: bySimpleName
        )

        return TypeGraph(
            nodes: nodes,
            references: references,
            findings: findings(in: references, nodes: nodes)
        )
    }

    // MARK: - Resolution

    private func resolve(
        byQualifiedName: [String: [TypeDeclaration]],
        bySimpleName: [String: [TypeDeclaration]]
    ) -> [TypeReference] {
        /// Every declaration a written name could mean, following Swift's own
        /// visibility rules closely enough not to invent edges.
        ///
        /// A bare name reaches top-level types, and reaches a nested type only
        /// from inside the type that nests it. Without that second half, a
        /// project with an `L10n.App` would have every `struct MyApp: App`
        /// reported as conforming to it — a bare `App` matching a nested
        /// declaration it cannot actually see.
        func candidates(for written: String, within subject: String?) -> [TypeDeclaration] {
            if let exact = byQualifiedName[written] { return exact }

            if let subject {
                // Innermost scope first, then outwards, which is the order the
                // compiler resolves in.
                var scope = subject
                while !scope.isEmpty {
                    if let nested = byQualifiedName[scope + "." + written] { return nested }
                    guard let dot = scope.lastIndex(of: ".") else { break }
                    scope = String(scope[scope.startIndex..<dot])
                }
            }

            return (bySimpleName[TypeName.simple(of: written)] ?? [])
                .filter { !$0.name.contains(".") }
        }

        var found: [TypeReference] = []
        var seen: Set<Key> = []

        for file in inputs.analysis.files {
            for usage in file.references {
                guard let subject = candidates(for: usage.owner, within: nil).first else { continue }

                let matches = candidates(for: usage.referenced, within: subject.name)
                guard let object = Self.preferred(matches, declaredIn: file.path) else { continue }
                // A type and the types nested inside it are one component, not
                // two that depend on each other. `AuthManager` naming its own
                // `AuthManager.StorageKey` is internal structure, and listing
                // it as a relationship would bury the real ones.
                guard !TypeName.areTheSameComponent(subject.name, object.name) else { continue }

                let key = Key(from: subject.name, to: object.name, kind: usage.kind, line: usage.line, file: file.path)
                guard seen.insert(key).inserted else { continue }

                found.append(
                    TypeReference(
                        from: subject.name,
                        to: object.name,
                        kind: Self.settled(usage.kind, against: object),
                        file: file.path,
                        line: usage.line,
                        // One declaration carries that name, so the match is
                        // the resolution. Several, and the edge is real but
                        // which same-named type it reaches is a name match —
                        // syntax alone cannot close that, so it is not claimed.
                        support: matches.count == 1 ? .observed : .conventional
                    )
                )
            }
        }

        return found.sorted {
            ($0.from, $0.to, $0.file, $0.line) < ($1.from, $1.to, $1.file, $1.line)
        }
    }

    /// Which of several same-named declarations a mention most likely means.
    ///
    /// A type declared in the same file wins, since that is the one in scope
    /// without qualification. Otherwise the first by position, so the answer is
    /// the same on every run and on every machine — the whole point of a
    /// deterministic tool is that two people reading the same code get the same
    /// report.
    static func preferred(_ matches: [TypeDeclaration], declaredIn path: String) -> TypeDeclaration? {
        if let local = matches.first(where: { $0.path == path }) { return local }
        return matches.min { ($0.path, $0.line) < ($1.path, $1.line) }
    }

    /// Closes the one question the grammar leaves open.
    ///
    /// A class's first inherited type may be a superclass or a protocol, and
    /// syntax cannot tell. Once the name is known to be a type this project
    /// declares, it can: a class there is a superclass, and anything else is a
    /// conformance, because only a class can be inherited from.
    static func settled(_ kind: ReferenceKind, against declaration: TypeDeclaration) -> ReferenceKind {
        guard kind == .inheritsOrConforms else { return kind }
        return declaration.kind == .classType ? .inheritance : .conformance
    }

    // MARK: - Roles

    /// What a type is for, and whether the code or the name said so.
    static func role(of declaration: TypeDeclaration) -> (TypeRole, Support) {
        if declaration.hasAttribute("Model") { return (.persistence, .observed) }

        for inherited in declaration.inheritedTypes {
            let name = TypeName.simple(of: inherited)
            if let role = appleConformances[name] { return (role, .observed) }
            if declaration.kind == .classType, let role = appleSuperclasses[name] {
                return (role, .observed)
            }
        }

        // A class inheriting from the project's own `BaseViewController` is a
        // view controller, and syntax cannot follow that name back to UIKit.
        // The superclass's *name* is the evidence, so this is conventional —
        // but it is evidence, and leaving it out would mean a UIKit codebase
        // with one base class reported no controllers at all.
        for inherited in declaration.inheritedTypes
        where TypeName.simple(of: inherited).hasSuffix("ViewController") {
            return (.viewController, .conventional)
        }

        let name = Self.roleName(of: declaration.name)
        for entry in roleSuffixes where name.hasSuffix(entry.suffix) {
            return (entry.role, .conventional)
        }
        return (.other, .undetermined)
    }

    /// The part of a name the suffix rules should read.
    ///
    /// `ArticleRepositoryProtocol` is a repository; the `Protocol` on the end
    /// says how it is declared, not what it is for. Same for the `Protocols`
    /// and `Type` some codebases use.
    static func roleName(of qualifiedName: String) -> String {
        var name = TypeName.simple(of: qualifiedName)
        for ending in ["Protocol", "Protocols", "Type", "Providing", "Proto"]
        where name.count > ending.count && name.hasSuffix(ending) {
            name = String(name.dropLast(ending.count))
            break
        }
        return name
    }


    // MARK: - Findings

    /// Relationships that usually mean something is wrong, reported without
    /// being judged.
    private func findings(in references: [TypeReference], nodes: [TypeNode]) -> [RelationshipFinding] {
        let byName = Dictionary(nodes.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let moduleRoles = Dictionary(
            inputs.modules.map { ($0.name, $0.role) }, uniquingKeysWith: { first, _ in first }
        )

        var grouped: [Signature: [TypeReference]] = [:]

        for reference in references {
            guard let subject = byName[reference.from], let object = byName[reference.to] else {
                continue
            }
            for rule in Self.rules(from: subject, to: object, moduleRoles: moduleRoles) {
                grouped[
                    Signature(rule: rule, subject: subject.name, object: object.name), default: []
                ].append(reference)
            }
        }

        return grouped
            .map { signature, evidence in
                let subject = byName[signature.subject]
                let object = byName[signature.object]
                return RelationshipFinding(
                    rule: signature.rule,
                    subject: signature.subject,
                    object: signature.object,
                    support: Self.weaker(subject?.roleSupport, object?.roleSupport),
                    evidence: evidence
                )
            }
            .sorted { ($0.rule.rawValue, $0.subject, $0.object) < ($1.rule.rawValue, $1.subject, $1.object) }
    }

    /// Which rules one relationship trips. Usually none.
    static func rules(
        from subject: TypeNode,
        to object: TypeNode,
        moduleRoles: [String: Module.Role]
    ) -> [RelationshipFinding.Rule] {
        var rules: [RelationshipFinding.Rule] = []

        switch (subject.role, object.role) {
        case (.view, .client), (.viewController, .client):
            rules.append(.viewReachesClient)
        case (.view, .repository), (.viewController, .repository):
            rules.append(.viewReachesRepository)
        case (.viewModel, .view), (.viewModel, .viewController):
            rules.append(.viewModelReachesView)
        default:
            break
        }

        if let feature = object.owner.feature {
            if subject.owner.feature == nil,
               let module = subject.owner.module,
               moduleRoles[module] == .core || moduleRoles[module] == .shared
            {
                rules.append(.coreReachesFeature)
            }
            if let subjectFeature = subject.owner.feature, subjectFeature != feature {
                rules.append(.featureReachesFeature)
            }
        }

        return rules
    }

    /// The weaker of two supports, so a finding is only as strong as the
    /// shakier half of it.
    static func weaker(_ first: Support?, _ second: Support?) -> Support {
        let order: [Support] = [.undetermined, .conventional, .observed]
        let firstRank = order.firstIndex(of: first ?? .undetermined) ?? 0
        let secondRank = order.firstIndex(of: second ?? .undetermined) ?? 0
        return order[min(firstRank, secondRank)]
    }

    // MARK: - Keys

    private struct Key: Hashable {
        let from: String
        let to: String
        let kind: ReferenceKind
        let line: Int
        let file: String
    }

    private struct Signature: Hashable {
        let rule: RelationshipFinding.Rule
        let subject: String
        let object: String
    }
}
