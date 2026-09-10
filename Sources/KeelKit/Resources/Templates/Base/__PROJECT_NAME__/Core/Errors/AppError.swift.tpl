//
//  AppError.swift
//  __PROJECT_NAME__
//

import Foundation

/// The single error type screens deal with.
///
/// Everything thrown below the presentation layer is funnelled through here,
/// so a view never has to know whether a failure came from the network, from
/// decoding, or from somewhere else. Every case carries a sentence that can be
/// shown to a person as-is.
enum AppError: LocalizedError, Sendable, Equatable {
    case offline
    case timeout
    case unauthorized
    case notFound
    case server(String)
    case decoding
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .offline:
            return "You are not connected to the internet. Check your connection and try again."
        case .timeout:
            return "The request timed out. Please try again."
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .notFound:
            return "We couldn't find what you were looking for."
        case .server(let message):
            return message
        case .decoding:
            return "We couldn't read the server's response."
        case .cancelled:
            return "The request was cancelled."
        case .unknown(let message):
            return message
        }
    }

    /// Maps anything thrown lower down onto a case a screen can render.
    ///
    /// A layer with its own error type conforms it to `AppErrorConvertible`
    /// rather than being special-cased here — that keeps this file from
    /// needing to know which parts of the app happen to exist.
    init(_ error: any Error) {
        if let convertible = error as? any AppErrorConvertible {
            self = convertible.asAppError
            return
        }
        if error is CancellationError {
            self = .cancelled
            return
        }

        switch (error as? URLError)?.code {
        case .notConnectedToInternet, .networkConnectionLost:
            self = .offline
        case .timedOut:
            self = .timeout
        case .cancelled:
            self = .cancelled
        default:
            self = .unknown(error.localizedDescription)
        }
    }
}

/// Lets a lower layer decide how its own errors surface to the user, without
/// `AppError` having to import that layer.
protocol AppErrorConvertible: Error {
    var asAppError: AppError { get }
}
