//
//  APIEndpoint.swift
//  __PROJECT_NAME__
//

import Foundation

/// How `Encodable` request bodies are keyed on the wire.
enum RequestKeyEncodingStrategy: Sendable {
    /// `brandName` is sent as `brand_name`.
    case snakeCase
    /// Keys are sent exactly as declared.
    case defaultKeys
}

/// One API call, described as data.
///
/// Declare one enum per feature conforming to this protocol. Everything has a
/// default below, so a simple GET needs only `path` and `method`.
protocol APIEndpoint: Sendable {
    var path: String { get }
    var method: HTTPMethod { get }
    var headers: [String: String]? { get }
    var queryItems: [URLQueryItem]? { get }
    var body: (any Encodable & Sendable)? { get }
    /// Pre-encoded body. When set, bypasses the encoder so exact JSON key
    /// names are preserved.
    var rawBody: Data? { get }
    var requiresAuth: Bool { get }
    var timeoutInterval: TimeInterval { get }
    /// Set true for absolute paths that must not have the API version prefixed.
    var skipVersionPrefix: Bool { get }
    var keyEncodingStrategy: RequestKeyEncodingStrategy { get }
    /// Send this one request to a different host than the configured base URL.
    var baseURL: URL? { get }
    /// When true, a 401 does not fire the global unauthorized handler. Use it
    /// where a 401 means a feature-level token problem, not an expired session.
    var suppressUnauthorizedHandler: Bool { get }
}

extension APIEndpoint {
    var headers: [String: String]? { nil }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable & Sendable)? { nil }
    var rawBody: Data? { nil }
    var requiresAuth: Bool { true }
    var timeoutInterval: TimeInterval { APIClient.Defaults.requestTimeout }
    var skipVersionPrefix: Bool { false }
    var keyEncodingStrategy: RequestKeyEncodingStrategy { .snakeCase }
    var baseURL: URL? { nil }
    var suppressUnauthorizedHandler: Bool { false }
}
