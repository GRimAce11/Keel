//
//  ArticleEndpoint.swift
//  __PROJECT_NAME__
//
//  One enum per feature, one case per call. Anything not declared here falls
//  back to the defaults in the APIEndpoint extension.
//

import Foundation

enum ArticleEndpoint: APIEndpoint {
    case list
    case detail(id: Int)

    var path: String {
        switch self {
        case .list: return "/posts"
        case .detail(let id): return "/posts/\(id)"
        }
    }

    var method: HTTPMethod { .GET }

    // The sample API is public. Delete this line once yours needs a token.
    var requiresAuth: Bool { false }
}
