// keel:if exampleFeature
//
//  ArticleTests.swift
//  __PROJECT_NAME__Tests
//
//  The pattern to copy for every feature: hand the repository a stub client,
//  hand the ViewModel a stub repository, then assert on `state`. No network,
//  no simulator services, no waiting.
//

import Foundation
import Testing
@testable import __PROJECT_NAME__

// MARK: - Repository

@Suite("ArticleRepository")
@MainActor
struct ArticleRepositoryTests {

    private let listJSON = """
        [
          { "id": 1, "userId": 7, "title": "  First  ", "body": "Body one" },
          { "id": 2, "userId": 7, "title": "Second", "body": "Body two" }
        ]
        """

    @Test("Decodes the wire format and maps it onto the domain model")
    func mapsDTOsToArticles() async throws {
        let client = StubAPIClient(json: listJSON)
        let articles = try await ArticleRepository(apiClient: client).fetchArticles()

        #expect(articles.count == 2)
        #expect(articles.first?.id == 1)
        // userId on the wire becomes authorID in the domain.
        #expect(articles.first?.authorID == 7)
        // Mapping trims, so stray server whitespace never reaches a label.
        #expect(articles.first?.title == "First")
    }

    @Test("Requests the expected path")
    func requestsListPath() async throws {
        let client = StubAPIClient(json: listJSON)
        _ = try await ArticleRepository(apiClient: client).fetchArticles()
        #expect(client.requestedPaths == ["/posts"])
    }

    @Test("Fetching one article asks for that article")
    func requestsDetailPath() async throws {
        let client = StubAPIClient(json: #"{ "id": 42, "userId": 1, "title": "T", "body": "B" }"#)
        let article = try await ArticleRepository(apiClient: client).fetchArticle(id: 42)

        #expect(article.id == 42)
        #expect(client.requestedPaths == ["/posts/42"])
    }

    @Test("A transport failure propagates rather than being swallowed")
    func propagatesFailure() async {
        let client = StubAPIClient(error: APIError.timeout)
        await #expect(throws: APIError.self) {
            try await ArticleRepository(apiClient: client).fetchArticles()
        }
    }
}

// MARK: - List

@Suite("ArticleListViewModel")
@MainActor
struct ArticleListViewModelTests {

    @Test("Starts idle, before anything has been asked for")
    func startsIdle() {
        let viewModel = ArticleListViewModel(repository: StubArticleRepository())
        #expect(viewModel.state.value == nil)
        #expect(viewModel.state.isLoading == false)
    }

    @Test("Loads articles into the loaded state")
    func loadsArticles() async {
        let repository = StubArticleRepository(articles: [
            Article(id: 1, authorID: 1, title: "First", body: "Body"),
            Article(id: 2, authorID: 1, title: "Second", body: "Body"),
        ])
        let viewModel = ArticleListViewModel(repository: repository)

        await viewModel.load()

        #expect(viewModel.state.value?.count == 2)
        #expect(viewModel.state.value?.first?.title == "First")
    }

    @Test("An empty response lands in loaded, not failed")
    func emptyIsLoaded() async {
        // Empty is a legitimate result, not an error — the view shows an
        // empty state rather than "something went wrong".
        let viewModel = ArticleListViewModel(repository: StubArticleRepository(articles: []))

        await viewModel.load()

        #expect(viewModel.state.value?.isEmpty == true)
        #expect(viewModel.state.error == nil)
    }

    @Test("A failure surfaces as an AppError the view can render")
    func surfacesFailure() async {
        let viewModel = ArticleListViewModel(
            repository: StubArticleRepository(error: APIError.timeout)
        )

        await viewModel.load()

        #expect(viewModel.state.error == .timeout)
        #expect(viewModel.state.value == nil)
    }

    @Test("Losing the connection reads as offline, not as a generic failure")
    func mapsOfflineFailure() async {
        let viewModel = ArticleListViewModel(
            repository: StubArticleRepository(error: APIError.noInternetConnection)
        )

        await viewModel.load()

        #expect(viewModel.state.error == .offline)
    }
}

// MARK: - Detail

@Suite("ArticleDetailViewModel")
@MainActor
struct ArticleDetailViewModelTests {

    private let seed = Article(id: 1, authorID: 1, title: "Seeded", body: "Body")

    @Test("Opens with the article it was handed, before loading anything")
    func startsWithSeededArticle() {
        // The row was already on screen, so the detail view should not flash a
        // spinner over content the app already has.
        let viewModel = ArticleDetailViewModel(
            articleID: 1,
            repository: StubArticleRepository(),
            article: seed
        )
        #expect(viewModel.state.value?.title == "Seeded")
    }

    @Test("Refreshes in place with the server's version")
    func refreshesSeededArticle() async {
        let fresh = Article(id: 1, authorID: 1, title: "Fresh", body: "Updated")
        let viewModel = ArticleDetailViewModel(
            articleID: 1,
            repository: StubArticleRepository(articles: [fresh]),
            article: seed
        )

        await viewModel.load()

        #expect(viewModel.state.value?.title == "Fresh")
    }

    @Test("A refresh failure keeps the content already on screen")
    func failureKeepsExistingContent() async {
        // Replacing a readable article with an error the user cannot act on
        // would be a worse outcome than a silently stale one.
        let viewModel = ArticleDetailViewModel(
            articleID: 1,
            repository: StubArticleRepository(error: APIError.timeout),
            article: seed
        )

        await viewModel.load()

        #expect(viewModel.state.value?.title == "Seeded")
        #expect(viewModel.state.error == nil)
    }

    @Test("With nothing seeded, a failure is shown")
    func failureWithoutSeedShowsError() async {
        let viewModel = ArticleDetailViewModel(
            articleID: 1,
            repository: StubArticleRepository(error: APIError.notFound)
        )

        await viewModel.load()

        #expect(viewModel.state.error == .notFound)
    }
}

// MARK: - Stub

@MainActor
private final class StubArticleRepository: ArticleRepositoryProtocol {
    private let articles: [Article]
    private let error: (any Error)?

    init(articles: [Article] = [], error: (any Error)? = nil) {
        self.articles = articles
        self.error = error
    }

    func fetchArticles() async throws -> [Article] {
        if let error { throw error }
        return articles
    }

    func fetchArticle(id: Int) async throws -> Article {
        if let error { throw error }
        guard let article = articles.first(where: { $0.id == id }) else {
            throw APIError.notFound
        }
        return article
    }
}
// keel:end
