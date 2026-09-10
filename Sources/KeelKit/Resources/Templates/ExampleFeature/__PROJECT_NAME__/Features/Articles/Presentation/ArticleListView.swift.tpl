//
//  ArticleListView.swift
//  __PROJECT_NAME__
//

import SwiftUI

struct ArticleListView: View {

    @State private var viewModel: ArticleListViewModel
    private let repository: any ArticleRepositoryProtocol

    init(repository: any ArticleRepositoryProtocol) {
        // The ViewModel is created once and owned by the view. Building it in
        // `body` would discard its state on every redraw.
        self.repository = repository
        _viewModel = State(initialValue: ArticleListViewModel(repository: repository))
    }

    var body: some View {
        content
            .navigationTitle("Articles")
            .task { await viewModel.load() }
    }

    // Every case is handled, so a new one cannot be forgotten.
    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingView(message: "Loading articles…")

        case .loaded(let articles) where articles.isEmpty:
            EmptyStateView(
                title: "No articles",
                message: "Nothing has been published yet.",
                systemImage: "doc.text"
            )

        case .loaded(let articles):
            List(articles) { article in
                NavigationLink(value: article) {
                    row(for: article)
                }
            }
            .listStyle(.plain)
            .refreshable { await viewModel.load() }
            .navigationDestination(for: Article.self) { article in
                ArticleDetailView(article: article, repository: repository)
            }

        case .failed(let error):
            ErrorStateView(error: error) {
                viewModel.retry()
            }
        }
    }

    private func row(for article: Article) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(article.title)
                .font(.headline)
                .lineLimit(2)
            Text(article.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        ArticleListView(repository: PreviewArticleRepository())
    }
}

/// Previews must never hit the network — it makes the canvas slow and flaky.
@MainActor
private final class PreviewArticleRepository: ArticleRepositoryProtocol {
    func fetchArticles() async throws -> [Article] {
        (1...8).map {
            Article(
                id: $0,
                authorID: 1,
                title: "Sample article \($0)",
                body: "A short summary of what this article covers."
            )
        }
    }

    func fetchArticle(id: Int) async throws -> Article {
        Article(id: id, authorID: 1, title: "Sample article \(id)", body: "Body text.")
    }
}
