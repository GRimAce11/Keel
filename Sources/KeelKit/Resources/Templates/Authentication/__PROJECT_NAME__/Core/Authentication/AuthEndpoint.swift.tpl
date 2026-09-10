//
//  AuthEndpoint.swift
//  __PROJECT_NAME__
//

import Foundation

enum AuthEndpoint: APIEndpoint {
    case signIn(email: String, password: String)
    case refresh(refreshToken: String)

    var path: String {
        switch self {
        case .signIn: return "/auth/login"
        case .refresh: return "/auth/refresh"
        }
    }

    var method: HTTPMethod { .POST }

    // These are how a token is obtained, so they cannot require one.
    var requiresAuth: Bool { false }

    /// A 401 here means "these credentials are wrong", not "your session
    /// expired" — firing the global handler would sign the user out of a
    /// session they were still trying to start.
    var suppressUnauthorizedHandler: Bool { true }

    var body: (any Encodable & Sendable)? {
        switch self {
        case .signIn(let email, let password):
            return SignInRequest(email: email, password: password)
        case .refresh(let refreshToken):
            return RefreshRequest(refreshToken: refreshToken)
        }
    }
}

private struct SignInRequest: Encodable, Sendable {
    let email: String
    let password: String
}

private struct RefreshRequest: Encodable, Sendable {
    let refreshToken: String
}
