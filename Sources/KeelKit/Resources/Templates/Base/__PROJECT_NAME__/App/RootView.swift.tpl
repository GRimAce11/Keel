//
//  RootView.swift
//  __PROJECT_NAME__
//

import SwiftUI

/// The app's first screen. Replace this with your own navigation — a
/// `TabView`, a router, or whatever the project needs.
struct RootView: View {
// keel:if exampleFeature
// keel:if dependencyInjection
    @Environment(AppContainer.self) private var container
// keel:else
    // Without a container, the view owns the repository itself. @State so it
    // survives redraws rather than being rebuilt on every body evaluation.
    @State private var repository = ArticleRepository(apiClient: APIClient())
// keel:end
// keel:end

    var body: some View {
// keel:if exampleFeature
        NavigationStack {
// keel:if dependencyInjection
            ArticleListView(repository: container.articleRepository)
// keel:else
            ArticleListView(repository: repository)
// keel:end
        }
// keel:else
        VStack(spacing: 16) {
            Image(systemName: "swift")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("__PROJECT_NAME__")
                .font(.title.bold())

            Text("Start building in RootView.swift")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
// keel:end
    }
}

#Preview {
    RootView()
// keel:if dependencyInjection
        .environment(AppContainer.preview)
// keel:end
}
