//
//  APIError.swift
//  __PROJECT_NAME__
//

import Foundation

enum APIError: LocalizedError, Sendable, Equatable {
    // Transport
    case invalidURL
    case invalidResponse
    case noInternetConnection
    case networkConnectionLost
    case timeout
    case cancelled

    // Auth
    case unauthorized
    case forbidden

    // Client / server
    case notFound
    case serverError(statusCode: Int, message: String?)
    case rateLimited(retryAfter: TimeInterval?, message: String?)
    case validation(message: String)

    // Coding
    case decodingFailed(String)
    case encodingFailed(String)

    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The request URL is invalid."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .noInternetConnection:
            return "You are not connected to the internet. Check your connection and try again."
        case .networkConnectionLost:
            return "Your network connection was lost. Please try again."
        case .timeout:
            return "The request timed out. Please try again."
        case .cancelled:
            return "The request was cancelled."
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .forbidden:
            return "You don't have permission to do that."
        case .notFound:
            return "The requested resource was not found."
        case .serverError(let code, let message):
            return message ?? "Server error (\(code)). Please try again later."
        case .rateLimited(_, let message):
            return message ?? "Too many requests. Please try again later."
        case .validation(let message):
            return message
        case .decodingFailed:
            return "We couldn't read the server's response."
        case .encodingFailed:
            return "We couldn't prepare the request."
        case .unknown:
            return "An unexpected error occurred."
        }
    }

    /// Whether `APIClient` should retry automatically.
    ///
    /// Anything caused by the request itself — 4xx other than 429 — is not
    /// retried, because repeating it would fail identically.
    var isRetryable: Bool {
        switch self {
        case .timeout, .noInternetConnection, .networkConnectionLost:
            return true
        case .serverError(let code, _):
            return code >= 500
        case .rateLimited:
            // Honours the server's own back-off via Retry-After.
            return true
        default:
            return false
        }
    }
}

// MARK: - Presentation

extension APIError: AppErrorConvertible {
    /// Networking decides how its own failures surface, so `AppError` never has
    /// to know this layer exists.
    var asAppError: AppError {
        switch self {
        case .noInternetConnection, .networkConnectionLost:
            return .offline
        case .timeout:
            return .timeout
        case .unauthorized, .forbidden:
            return .unauthorized
        case .notFound:
            return .notFound
        case .cancelled:
            return .cancelled
        case .decodingFailed, .encodingFailed:
            return .decoding
        case .serverError, .rateLimited, .validation:
            return .server(localizedDescription)
        case .invalidURL, .invalidResponse, .unknown:
            return .unknown(localizedDescription)
        }
    }
}
