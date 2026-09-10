//
//  AuthManager.swift
//  __PROJECT_NAME__
//

import Foundation
import Observation

/// Owns the session: the token, its refresh, and signing out.
///
/// Nothing else reads or writes the token. `APIClient` asks this type for one
/// through its token provider, so there is a single place where a refresh can
/// happen and a single place that decides a session has ended.
@Observable
@MainActor
final class AuthManager {

    private enum StorageKey {
        static let token = "auth.token"
    }

    private(set) var isSignedIn: Bool = false

    private let apiClient: APIClient
    private let keychain: any KeychainServiceProtocol

    /// Guards against several concurrent 401s each starting their own refresh.
    private var refreshTask: Task<AuthToken, any Error>?

    /// Called after the session ends, so the app can return to its signed-out
    /// state without this type knowing anything about navigation.
    var onSignOut: (() -> Void)?

    init(apiClient: APIClient, keychain: any KeychainServiceProtocol) {
        self.apiClient = apiClient
        self.keychain = keychain
        self.isSignedIn = (try? loadToken()) != nil
    }

    // MARK: - Session

    func signIn(email: String, password: String) async throws {
        let token: AuthToken = try await apiClient.request(
            AuthEndpoint.signIn(email: email, password: password)
        )
        try store(token)
        isSignedIn = true
    }

    func signOut() async {
        refreshTask?.cancel()
        refreshTask = nil
        try? keychain.delete(for: StorageKey.token)
        isSignedIn = false
        onSignOut?()
    }

    // MARK: - Tokens

    /// The token `APIClient` should attach, refreshing it first if needed.
    ///
    /// Returns nil rather than throwing when there is no session at all, so an
    /// unauthenticated request simply goes out without a header.
    func validAccessToken() async throws -> String? {
        guard let token = try? loadToken() else { return nil }
        if token.isValid { return token.accessToken }

        guard let refreshToken = token.refreshToken else {
            await signOut()
            return nil
        }

        // Concurrent callers join the refresh already in flight instead of
        // each starting one — several parallel refreshes would invalidate
        // each other's tokens.
        if let refreshTask {
            return try await refreshTask.value.accessToken
        }

        let task = Task<AuthToken, any Error> { [apiClient] in
            let refreshed: AuthToken = try await apiClient.request(
                AuthEndpoint.refresh(refreshToken: refreshToken)
            )
            try store(refreshed)
            return refreshed
        }
        refreshTask = task
        defer { refreshTask = nil }

        do {
            return try await task.value.accessToken
        } catch {
            AppLogger.auth.error("Token refresh failed: \(error.localizedDescription)")
            await signOut()
            throw error
        }
    }

    // MARK: - Storage

    private func store(_ token: AuthToken) throws {
        let data = try JSONEncoder().encode(token)
        try keychain.save(data, for: StorageKey.token)
    }

    private func loadToken() throws -> AuthToken {
        let data = try keychain.load(for: StorageKey.token)
        return try JSONDecoder().decode(AuthToken.self, from: data)
    }
}
