//
//  ArticleListViewModel.swift
//  __PROJECT_NAME__
//

import Foundation

@Observable
@MainActor
final class ArticleListViewModel {

    /// One property, not three. See `ViewState` for why.
    private(set) var state: ViewState<[Article]> = .idle

    private let repository: any ArticleRepositoryProtocol

    init(repository: any ArticleRepositoryProtocol) {
        self.repository = repository
    }

    func load() async {
        // A pull-to-refresh while the first load is still running would
        // otherwise fire a second request and race it.
        guard !state.isLoading else { return }

        state = .loading
        do {
            state = .loaded(try await repository.fetchArticles())
        } catch is CancellationError {
            // The view went away. Leaving the state alone avoids flashing an
            // error onto a screen nobody is looking at.
            state = .idle
        } catch {
            AppLogger.network.error("Failed to load articles: \(error.localizedDescription)")
            state = .failed(AppError(error))
        }
    }

    func retry() {
        Task { await load() }
    }
}
