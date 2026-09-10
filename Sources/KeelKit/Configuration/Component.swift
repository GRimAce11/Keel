import Foundation

/// An optional part of a generated project.
///
/// Each case is chosen independently. Switching one off means its files are
/// never written — not stubbed, not commented out — so a project generated
/// without networking contains no `APIClient.swift` to delete.
public enum Component: String, CaseIterable, Codable, Sendable {
    case networking
    case dependencyInjection
    case persistence
    case authentication
    case keychain
    case localization
    case testing
    case designSystem
    case exampleFeature

    /// Shown in the interactive prompt.
    public var title: String {
        switch self {
        case .networking: return "Networking"
        case .dependencyInjection: return "Dependency injection"
        case .persistence: return "Persistence"
        case .authentication: return "Authentication"
        case .keychain: return "Keychain storage"
        case .localization: return "Localization"
        case .testing: return "Unit tests"
        case .designSystem: return "Design system"
        case .exampleFeature: return "Example feature"
        }
    }

    /// One line of detail under the title, so the choice is informed.
    public var summary: String {
        switch self {
        case .networking:
            return "APIClient, endpoints, typed errors, retry and auth headers"
        case .dependencyInjection:
            return "AppContainer composition root with constructor injection"
        case .persistence:
            return "SwiftData model container and a store protocol"
        case .authentication:
            return "Token storage, refresh, and sign-out on 401"
        case .keychain:
            return "Secure storage wrapping the Keychain API"
        case .localization:
            return "String Catalog and typed accessors"
        case .testing:
            return "Test target with stubs and ViewModel tests"
        case .designSystem:
            return "Spacing, colour and typography tokens"
        case .exampleFeature:
            return "A working list + detail screen you can copy"
        }
    }

    /// Everything is on by default: pressing return through the prompts should
    /// produce the complete project.
    public var isEnabledByDefault: Bool { true }

    /// Components that must also be present for this one to compile.
    public var requires: [Component] {
        switch self {
        case .exampleFeature:
            // Its screens call the API client directly.
            return [.networking]
        case .authentication:
            // Auth needs somewhere to send credentials and somewhere safe to
            // keep the token it gets back.
            return [.networking, .keychain]
        case .networking, .dependencyInjection, .persistence,
             .keychain, .localization, .testing, .designSystem:
            return []
        }
    }

    /// The flag that turns this off from the command line: `--no-networking`.
    public var disableFlag: String {
        "--no-" + rawValue.kebabCased()
    }
}

extension String {
    /// `dependencyInjection` -> `dependency-injection`
    func kebabCased() -> String {
        var result = ""
        for character in self {
            if character.isUppercase {
                if !result.isEmpty { result.append("-") }
                result.append(character.lowercased())
            } else {
                result.append(character)
            }
        }
        return result
    }
}
