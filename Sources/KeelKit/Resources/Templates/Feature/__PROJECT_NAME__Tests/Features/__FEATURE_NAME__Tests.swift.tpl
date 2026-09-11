// keel:if testing
//
//  __FEATURE_NAME__Tests.swift
//  __PROJECT_NAME__Tests
//

import Testing
@testable import __PROJECT_NAME__

@MainActor
@Suite("__FEATURE_NAME__ViewModel")
struct __FEATURE_NAME__ViewModelTests {

    /// Hands the view model canned data, so the test never touches the real
    /// source.
    private struct Stub__FEATURE_NAME__Repository: __FEATURE_NAME__RepositoryProtocol {
        var result: Result<[__FEATURE_NAME__], Error> = .success([])

        func fetch__FEATURE_NAME__s() async throws -> [__FEATURE_NAME__] {
            try result.get()
        }
    }

    @Test("Loading moves from idle to loaded")
    func loadsSuccessfully() async {
        let item = __FEATURE_NAME__(id: 1, title: "First")
        let viewModel = __FEATURE_NAME__ViewModel(
            repository: Stub__FEATURE_NAME__Repository(result: .success([item]))
        )

        await viewModel.load()

        #expect(viewModel.state.value == [item])
    }

    @Test("A failure is surfaced rather than swallowed")
    func reportsFailure() async {
        struct Boom: Error {}
        let viewModel = __FEATURE_NAME__ViewModel(
            repository: Stub__FEATURE_NAME__Repository(result: .failure(Boom()))
        )

        await viewModel.load()

        #expect(viewModel.state.error != nil)
    }
}
// keel:end
