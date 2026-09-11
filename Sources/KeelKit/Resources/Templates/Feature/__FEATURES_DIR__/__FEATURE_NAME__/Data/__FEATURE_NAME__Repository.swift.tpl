//
//  __FEATURE_NAME__Repository.swift
//  __PROJECT_NAME__
//

import Foundation

/// The only type in the feature that knows where __FEATURE_NAME__ values come
/// from.
///
/// The view model depends on this protocol, which is what lets a test hand it
/// canned data instead of standing up the real thing.
@MainActor
protocol __FEATURE_NAME__RepositoryProtocol {
    func fetch__FEATURE_NAME__s() async throws -> [__FEATURE_NAME__]
}

@Observable
@MainActor
final class __FEATURE_NAME__Repository: __FEATURE_NAME__RepositoryProtocol {

// keel:if networking
    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }
// keel:end
// keel:if !networking

    init() {}
// keel:end

    func fetch__FEATURE_NAME__s() async throws -> [__FEATURE_NAME__] {
// keel:if networking
        // Replace this with a real endpoint. Decoding into a DTO and mapping
        // here is what keeps the API's shape out of the rest of the app.
        []
// keel:end
// keel:if !networking
        // This project has no networking layer, so Keel did not invent one.
        // Load from wherever this feature's data actually lives.
        []
// keel:end
    }
}
