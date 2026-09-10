//
//  ViewStateTests.swift
//  __PROJECT_NAME__Tests
//

import Foundation
import Testing
@testable import __PROJECT_NAME__

@Suite("ViewState")
struct ViewStateTests {

    @Test("Only the loaded case carries a value")
    func exposesValueWhenLoaded() {
        #expect(ViewState.loaded([1, 2, 3]).value == [1, 2, 3])
        #expect(ViewState<[Int]>.loading.value == nil)
        #expect(ViewState<[Int]>.idle.value == nil)
        #expect(ViewState<[Int]>.failed(.timeout).value == nil)
    }

    @Test("Only the failed case carries an error")
    func exposesErrorWhenFailed() {
        #expect(ViewState<Int>.failed(.offline).error == .offline)
        #expect(ViewState<Int>.loaded(1).error == nil)
    }

    @Test("A loaded state is never also loading")
    func loadedIsNotLoading() {
        // The point of one enum instead of several booleans: these cannot
        // both be true, so a spinner cannot render on top of content.
        #expect(ViewState.loaded(1).isLoading == false)
        #expect(ViewState<Int>.loading.isLoading)
    }
}

@Suite("AppError")
struct AppErrorTests {

    @Test("Every case has a message that can be shown to a person")
    func hasUserFacingMessages() {
        let errors: [AppError] = [
            .offline, .timeout, .unauthorized, .notFound,
            .server("Server said no"), .decoding, .cancelled, .unknown("Boom"),
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test("A cancelled task maps to cancelled, not to a failure worth showing")
    func mapsCancellation() {
        #expect(AppError(CancellationError()) == .cancelled)
    }

    @Test("Losing the connection maps to offline")
    func mapsOffline() {
        let error = URLError(.notConnectedToInternet)
        #expect(AppError(error) == .offline)
    }
}
