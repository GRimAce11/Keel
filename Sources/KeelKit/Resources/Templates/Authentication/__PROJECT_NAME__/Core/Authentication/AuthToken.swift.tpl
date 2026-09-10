//
//  AuthToken.swift
//  __PROJECT_NAME__
//

import Foundation

/// What the sign-in endpoint returns.
///
/// Adjust the field names to match your API. The shared decoder converts
/// snake_case, so `access_token` maps onto `accessToken` without CodingKeys.
struct AuthToken: Codable, Sendable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?

    /// A token is treated as expired slightly early, so a request is not sent
    /// with a token that lapses while it is in flight.
    private static let expiryMargin: TimeInterval = 30

    var isValid: Bool {
        guard let expiresAt else { return true }
        return expiresAt.timeIntervalSinceNow > Self.expiryMargin
    }
}
