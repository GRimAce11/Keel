//
//  ArticleRepository.swift
//  __PROJECT_NAME__
//

import Foundation

/// The only type in the feature that knows the API exists.
///
/// ViewModels depend on this protocol, which is what lets a test hand them
/// canned data instead of standing up a network.
@MainActor
protocol ArticleRepositoryProtocol {
    func fetchArticles() async throws -> [Article]
    func fetchArticle(id: Int) async throws -> Article
}

@Observable
@MainActor
final class ArticleRepository: ArticleRepositoryProtocol {

    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    func fetchArticles() async throws -> [Article] {
        // Decoding into DTOs and mapping here is what keeps the API's shape
        // from leaking into the rest of the app.
        let dtos: [ArticleDTO] = try await apiClient.request(ArticleEndpoint.list)
        return dtos.map(\.asArticle)
    }

    func fetchArticle(id: Int) async throws -> Article {
        let dto: ArticleDTO = try await apiClient.request(ArticleEndpoint.detail(id: id))
        return dto.asArticle
    }
}
