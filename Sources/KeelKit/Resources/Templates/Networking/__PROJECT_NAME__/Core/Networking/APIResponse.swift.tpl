//
//  APIResponse.swift
//  __PROJECT_NAME__
//

import Foundation

/// The common `{ success, data, message }` envelope. `APIClient` unwraps it
/// automatically and falls back to decoding the bare type when the API
/// returns one.
struct APIResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let success: Bool
    let data: T?
    let message: String?
    let errors: [String]?
}

struct EmptyResponse: Decodable, Sendable {}

struct PaginatedResponse<T: Decodable & Sendable>: Decodable, Sendable {
    // No explicit CodingKeys: the shared decoder uses `.convertFromSnakeCase`,
    // which already maps `per_page`/`has_more` onto `perPage`/`hasMore`.
    // Declaring snake_case keys here would fight that conversion, and since
    // these are non-optional, decoding would throw.
    let data: [T]
    let total: Int
    let page: Int
    let perPage: Int
    let hasMore: Bool
}

/// A best-effort read of whatever shape the server uses for error messages.
struct ServerErrorResponse: Decodable, Sendable {
    let message: String?
    let msg: String?
    let error: String?
    let detail: String?

    var bestMessage: String? {
        [message, msg, error, detail]
            .compactMap { $0 }
            .first { !$0.isEmpty }
    }

    static func bestMessage(from data: Data, decoder: JSONDecoder) -> String? {
        (try? decoder.decode(ServerErrorResponse.self, from: data))?.bestMessage
    }
}
