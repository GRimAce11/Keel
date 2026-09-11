//
//  __FEATURE_NAME__ViewModel.swift
//  __PROJECT_NAME__
//

import Foundation

@Observable
@MainActor
final class __FEATURE_NAME__ViewModel {

    /// One property, not three. See `ViewState` for why.
    private(set) var state: ViewState<[__FEATURE_NAME__]> = .idle

    private let repository: any __FEATURE_NAME__RepositoryProtocol

    init(repository: any __FEATURE_NAME__RepositoryProtocol) {
        self.repository = repository
    }

    func load() async {
        // A refresh while the first load is still running would otherwise fire
        // a second request and race it.
        guard !state.isLoading else { return }

        state = .loading
        do {
            state = .loaded(try await repository.fetch__FEATURE_NAME__s())
        } catch is CancellationError {
            // The view went away. Leaving the state alone avoids flashing an
            // error onto a screen nobody is looking at.
            state = .idle
        } catch {
            state = .failed(AppError(error))
        }
    }

    func retry() {
        Task { await load() }
    }
}
