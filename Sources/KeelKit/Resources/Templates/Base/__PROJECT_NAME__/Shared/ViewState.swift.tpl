//
//  ViewState.swift
//  __PROJECT_NAME__
//

import Foundation

/// The state of a screen that loads something.
///
/// One property instead of four (`data` + `isLoading` + `errorMessage` +
/// `isEmpty`). Four booleans have sixteen combinations and only about four of
/// them make sense — that gap is where the spinner-on-top-of-an-error bugs
/// live. One enum makes the rest unrepresentable, and the `switch` in the view
/// has to handle every case.
enum ViewState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(AppError)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var error: AppError? {
        if case .failed(let error) = self { return error }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

extension ViewState: Equatable where Value: Equatable {}
extension ViewState: Sendable where Value: Sendable {}
