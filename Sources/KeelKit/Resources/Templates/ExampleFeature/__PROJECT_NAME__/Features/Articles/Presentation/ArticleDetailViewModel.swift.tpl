//
//  ArticleDetailViewModel.swift
//  __PROJECT_NAME__
//

import Foundation

@Observable
@MainActor
final class ArticleDetailViewModel {

    private(set) var state: ViewState<Article>

    private let articleID: Int
    private let repository: any ArticleRepositoryProtocol

    /// - Parameter article: the row that was tapped, if there is one. Seeding
    ///   the state with it means the screen opens with content already on it
    ///   and refreshes in place, instead of showing a spinner over data the
    ///   app has in hand.
    init(articleID: Int, repository: any ArticleRepositoryProtocol, article: Article? = nil) {
        self.articleID = articleID
        self.repository = repository
        self.state = article.map { .loaded($0) } ?? .idle
    }

    func load() async {
        guard !state.isLoading else { return }

        // Only show a spinner when there is nothing to show yet.
        if state.value == nil { state = .loading }

        do {
            state = .loaded(try await repository.fetchArticle(id: articleID))
        } catch is CancellationError {
            return
        } catch {
            AppLogger.network.error("Failed to load article \(self.articleID): \(error.localizedDescription)")
            // Keep whatever was already on screen rather than replacing real
            // content with an error the user cannot act on.
            if state.value == nil {
                state = .failed(AppError(error))
            }
        }
    }

    func retry() {
        Task { await load() }
    }
}
