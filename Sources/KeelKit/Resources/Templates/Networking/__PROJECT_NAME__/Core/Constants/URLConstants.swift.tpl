//
//  URLConstants.swift
//  __PROJECT_NAME__
//
//  Every host the app talks to lives here. No URL strings anywhere else.
//

import Foundation

enum URLConstants {

    enum API {
        // keel:if exampleFeature
        // Points at a public test API so the generated project runs before you
        // have a backend. Replace both with your own hosts.
        static let development = URL(string: "https://jsonplaceholder.typicode.com")!
        static let production = URL(string: "https://jsonplaceholder.typicode.com")!
        // keel:else
        // TODO: replace with your own hosts.
        static let development = URL(string: "https://api.example.com")!
        static let production = URL(string: "https://api.example.com")!
        // keel:end

        /// Prepended to every request path, so `"v1"` produces `/v1/users`.
        /// Leave empty when the API is not versioned by path.
        static let version = ""

        /// The host for the current build.
        static var base: URL {
            switch AppEnvironment.current {
            case .development: return development
            case .production: return production
            }
        }
    }
}
