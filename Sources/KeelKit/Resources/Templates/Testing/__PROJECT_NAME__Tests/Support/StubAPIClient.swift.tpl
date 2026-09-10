// keel:if networking
//
//  StubAPIClient.swift
//  __PROJECT_NAME__Tests
//

import Foundation
@testable import __PROJECT_NAME__

/// An `APIClient` that never touches the network.
///
/// Set `json` to what the endpoint should return, or `error` to the failure it
/// should throw. Recorded paths let a test assert which call was actually made.
@MainActor
final class StubAPIClient: APIClientProtocol {

    var json: String?
    var error: (any Error)?
    private(set) var requestedPaths: [String] = []

    init(json: String? = nil, error: (any Error)? = nil) {
        self.json = json
        self.error = error
    }

    func request<T: Decodable & Sendable>(_ endpoint: any APIEndpoint) async throws -> T {
        let data = try recordAndResolve(endpoint)
        let decoder = JSONDecoder()
        // Matches APIClient, so a test exercises the same key mapping the app
        // uses rather than a more forgiving one.
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    func requestRaw(_ endpoint: any APIEndpoint) async throws -> Data {
        try recordAndResolve(endpoint)
    }

    private func recordAndResolve(_ endpoint: any APIEndpoint) throws -> Data {
        requestedPaths.append(endpoint.path)
        if let error { throw error }
        guard let json else { throw APIError.invalidResponse }
        return Data(json.utf8)
    }
}
// keel:end
