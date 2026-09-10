//
//  AppContainer.swift
//  __PROJECT_NAME__
//

import SwiftUI

/// Everything the app depends on, constructed once at launch.
///
/// Add a service by declaring a `let` and assigning it in `init`. Because each
/// type receives its dependencies through its initialiser, any of them can be
/// swapped for a stub in a test without touching this file.
@Observable
@MainActor
final class AppContainer {

// keel:if networking
    let apiClient: APIClient
// keel:end
// keel:if keychain
    let keychain: KeychainService
// keel:end
// keel:if persistence
    let persistence: PersistenceController
// keel:end
// keel:if authentication
    let authManager: AuthManager
// keel:end
// keel:if exampleFeature

    // MARK: Feature repositories
    let articleRepository: ArticleRepository
// keel:end

    init() {
// keel:if keychain
        let keychain = KeychainService()
        self.keychain = keychain
// keel:end
// keel:if networking
        let apiClient = APIClient()
        self.apiClient = apiClient
// keel:end
// keel:if persistence
        self.persistence = PersistenceController.shared
// keel:end
// keel:if exampleFeature
        self.articleRepository = ArticleRepository(apiClient: apiClient)
// keel:end
// keel:if authentication
        let authManager = AuthManager(apiClient: apiClient, keychain: keychain)
        self.authManager = authManager

        // One place decides how a request gets its token, and one place decides
        // what an expired session does.
        apiClient.setTokenProvider { [weak authManager] in
            try await authManager?.validAccessToken()
        }
        apiClient.setUnauthorizedHandler { [weak authManager] in
            Task { await authManager?.signOut() }
        }
// keel:end
// keel:if !authentication
// keel:if networking

        // Attach an access token to every authenticated request once auth
        // exists:
        //
        // apiClient.setTokenProvider { try await tokenStore.validAccessToken() }
        //
        // And react to a 401 in one place:
        //
        // apiClient.setUnauthorizedHandler { [weak self] in self?.signOut() }
// keel:end
// keel:end
    }

    /// For `#Preview` only. Never use this at run time — it is a second
    /// container, and any state it holds is invisible to the real one.
    static let preview = AppContainer()
}

// MARK: - Environment
//
// Injection uses Observation's own `.environment(_:)` and
// `@Environment(_.self)` rather than a custom `EnvironmentKey`. An
// EnvironmentKey needs a `defaultValue`, and building a @MainActor container to
// satisfy a nonisolated protocol requirement does not compile under Swift 6
// strict concurrency.
//
// Inject once, at the app entry point:
//
//     RootView().environment(container)
//
// Read it in any view below:
//
//     @Environment(AppContainer.self) private var container
//
// A view that reads it with no ancestor injecting it traps at run time. That
// is deliberate: it surfaces the wiring mistake immediately instead of quietly
// handing out a second container nobody else can see. In `#Preview`, inject
// `AppContainer.preview`.
