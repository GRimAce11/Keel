//
//  ArticleDetailView.swift
//  __PROJECT_NAME__
//

import SwiftUI

struct ArticleDetailView: View {

    @State private var viewModel: ArticleDetailViewModel

    init(article: Article, repository: any ArticleRepositoryProtocol) {
        _viewModel = State(initialValue: ArticleDetailViewModel(
            articleID: article.id,
            repository: repository,
            // Seeded with the row that was tapped, so the screen opens with
            // content instead of a spinner.
            article: article
        ))
    }

    var body: some View {
        content
            .navigationTitle("Article")
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingView()

        case .loaded(let article):
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(article.title)
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)

                    Text(article.body)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }

        case .failed(let error):
            ErrorStateView(error: error) {
                viewModel.retry()
            }
        }
    }
}

#Preview {
    NavigationStack {
        ArticleDetailView(
            article: Article(
                id: 1,
                authorID: 1,
                title: "A sample article title that runs onto two lines",
                body: "The body of the article goes here."
            ),
            repository: PreviewDetailRepository()
        )
    }
}

@MainActor
private final class PreviewDetailRepository: ArticleRepositoryProtocol {
    func fetchArticles() async throws -> [Article] { [] }

    func fetchArticle(id: Int) async throws -> Article {
        Article(id: id, authorID: 1, title: "Sample article", body: "Body text.")
    }
}
