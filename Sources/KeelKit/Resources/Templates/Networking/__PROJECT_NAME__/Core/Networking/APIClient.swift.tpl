//
//  APIClient.swift
//  __PROJECT_NAME__
//

import Foundation
import OSLog

// MARK: - Protocol

/// Repositories depend on this, not on `APIClient` directly — that is what
/// lets the test target substitute a stub and run without a network.
@MainActor
protocol APIClientProtocol: AnyObject {
    func request<T: Decodable & Sendable>(_ endpoint: any APIEndpoint) async throws -> T
    func requestRaw(_ endpoint: any APIEndpoint) async throws -> Data
}

// MARK: - Client

@Observable
@MainActor
final class APIClient: APIClientProtocol {

    enum Defaults {
        static let requestTimeout: TimeInterval = 30
        static let resourceTimeout: TimeInterval = 120
        /// How many times a retryable failure is retried before the error
        /// reaches the caller.
        static let maxRetries = 2
    }

    private let session: URLSession
    private let decoder: JSONDecoder

    private var tokenProvider: (() async throws -> String?)?
    private var unauthorizedHandler: (() -> Void)?

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Defaults.requestTimeout
        configuration.timeoutIntervalForResource = Defaults.resourceTimeout
        // API responses must never be written to disk.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        // Accepts ISO 8601 with and without fractional seconds. Servers are
        // inconsistent about this, and the difference stays invisible until one
        // endpoint starts returning milliseconds.
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }

            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot parse date: \(string)"
            )
        }
        self.decoder = decoder
    }

    // MARK: Configuration

    /// Called before every authenticated request. Wire this to whatever owns
    /// the access token so refreshes happen in one place.
    func setTokenProvider(_ provider: @escaping () async throws -> String?) {
        tokenProvider = provider
    }

    /// Fired on any 401 that does not opt out. Typically triggers a sign-out.
    func setUnauthorizedHandler(_ handler: @escaping () -> Void) {
        unauthorizedHandler = handler
    }

    // MARK: Requests

    func request<T: Decodable & Sendable>(_ endpoint: any APIEndpoint) async throws -> T {
        let urlRequest = try await buildRequest(from: endpoint)
        return try await execute(urlRequest, endpoint: endpoint, retriesRemaining: Defaults.maxRetries)
    }

    func requestRaw(_ endpoint: any APIEndpoint) async throws -> Data {
        let urlRequest = try await buildRequest(from: endpoint)
        let (data, response) = try await session.data(for: urlRequest)
        log(urlRequest)
        try validate(response: response, data: data, endpoint: endpoint)
        return data
    }

    // MARK: Building

    private func buildRequest(from endpoint: any APIEndpoint) async throws -> URLRequest {
        guard NetworkMonitor.shared.isConnected else {
            throw APIError.noInternetConnection
        }

        let version = URLConstants.API.version
        let resolvedPath = (endpoint.skipVersionPrefix || version.isEmpty)
            ? endpoint.path
            : "/\(version)\(endpoint.path)"

        var components = URLComponents(
            url: (endpoint.baseURL ?? URLConstants.API.base).appendingPathComponent(resolvedPath),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = endpoint.queryItems

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url, timeoutInterval: endpoint.timeoutInterval)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        for (key, value) in endpoint.headers ?? [:] {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if endpoint.requiresAuth, let token = try await tokenProvider?() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let rawBody = endpoint.rawBody {
            request.httpBody = rawBody
        } else if let body = endpoint.body {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = endpoint.keyEncodingStrategy == .snakeCase
                ? .convertToSnakeCase
                : .useDefaultKeys
            encoder.dateEncodingStrategy = .iso8601
            do {
                request.httpBody = try encoder.encode(AnyEncodable(body))
            } catch {
                throw APIError.encodingFailed(error.localizedDescription)
            }
        }

        return request
    }

    // MARK: Executing

    private func execute<T: Decodable & Sendable>(
        _ request: URLRequest,
        endpoint: any APIEndpoint,
        retriesRemaining: Int
    ) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            log(request)
            try validate(response: response, data: data, endpoint: endpoint)
            return try decode(from: data)

        } catch let error as APIError {
            guard error.isRetryable, retriesRemaining > 0 else { throw error }

            // Honour a 429's Retry-After; otherwise back off briefly.
            let delay: UInt64
            if case .rateLimited(let retryAfter, _) = error, let retryAfter, retryAfter > 0 {
                delay = UInt64(retryAfter * 1_000_000_000)
            } else {
                delay = 250_000_000
            }

            AppLogger.network.info("Retrying \(request.url?.path ?? "") — \(retriesRemaining) attempts left")
            try await Task.sleep(nanoseconds: delay)
            return try await execute(request, endpoint: endpoint, retriesRemaining: retriesRemaining - 1)

        } catch let error as URLError {
            throw map(error)
        }
    }

    private func decode<T: Decodable & Sendable>(from data: Data) throws -> T {
        // Unwrap the `{ success, data }` envelope when present, otherwise
        // decode the bare type.
        if let wrapped = try? decoder.decode(APIResponse<T>.self, from: data),
           let value = wrapped.data {
            return value
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            AppLogger.network.error("Decoding \(String(describing: T.self)) failed: \(error.localizedDescription)")
            throw APIError.decodingFailed(error.localizedDescription)
        }
    }

    private func validate(response: URLResponse, data: Data, endpoint: any APIEndpoint) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        let serverMessage = ServerErrorResponse.bestMessage(from: data, decoder: decoder)

        switch http.statusCode {
        case 200...299:
            return
        case 401:
            if !endpoint.suppressUnauthorizedHandler {
                unauthorizedHandler?()
            }
            throw serverMessage.map { APIError.serverError(statusCode: 401, message: $0) } ?? .unauthorized
        case 403:
            throw serverMessage.map { APIError.serverError(statusCode: 403, message: $0) } ?? .forbidden
        case 404:
            throw serverMessage.map { APIError.serverError(statusCode: 404, message: $0) } ?? .notFound
        case 422:
            throw APIError.validation(message: serverMessage ?? "Validation failed.")
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw APIError.rateLimited(retryAfter: retryAfter, message: serverMessage)
        default:
            throw APIError.serverError(statusCode: http.statusCode, message: serverMessage)
        }
    }

    private func map(_ error: URLError) -> APIError {
        switch error.code {
        case .notConnectedToInternet: return .noInternetConnection
        case .networkConnectionLost: return .networkConnectionLost
        case .timedOut: return .timeout
        case .cancelled: return .cancelled
        default: return .unknown
        }
    }

    private func log(_ request: URLRequest) {
        #if DEBUG
        guard AppConfiguration.current.isLoggingEnabled else { return }
        // Path only — the query string and body can carry tokens and PII.
        AppLogger.network.info("\(request.httpMethod ?? "?") \(request.url?.path ?? "")")
        #endif
    }
}

// MARK: - Helpers

/// Type-erases `any Encodable` so `JSONEncoder` can take it.
private struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        encodeValue = wrapped.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}
