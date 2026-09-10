//
//  Article.swift
//  __PROJECT_NAME__
//
//  The domain model. Views and ViewModels only ever see this type — never the
//  DTO — so a change to the API's field names stops at the repository.
//

import Foundation

// Hashable is what lets `NavigationLink(value:)` and `navigationDestination`
// route to this type.
struct Article: Identifiable, Sendable, Hashable {
    let id: Int
    let authorID: Int
    let title: String
    let body: String

    /// First line of the body, for a list row.
    var summary: String {
        body
            .split(separator: "\n")
            .first
            .map(String.init) ?? body
    }
}
