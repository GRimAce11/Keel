//
//  __FEATURE_NAME__View.swift
//  __PROJECT_NAME__
//

import SwiftUI

struct __FEATURE_NAME__View: View {

    @State private var viewModel: __FEATURE_NAME__ViewModel

    init(repository: any __FEATURE_NAME__RepositoryProtocol) {
        _viewModel = State(wrappedValue: __FEATURE_NAME__ViewModel(repository: repository))
    }

    var body: some View {
        content
            .navigationTitle("__FEATURE_NAME__")
            .task { await viewModel.load() }
    }

    // Every case is handled, so a new one cannot be forgotten.
    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingView(message: "Loading…")

        case .loaded(let items) where items.isEmpty:
            EmptyStateView(
                title: "Nothing here yet",
                message: "This feature has no data to show.",
                systemImage: "tray"
            )

        case .loaded(let items):
            List(items) { item in
                Text(item.title)
            }
            .listStyle(.plain)
            .refreshable { await viewModel.load() }

        case .failed(let error):
            ErrorStateView(error: error, retry: viewModel.retry)
        }
    }
}
