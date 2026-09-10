//
//  ArticleDTO.swift
//  __PROJECT_NAME__
//
//  The wire format, kept separate from the domain model on purpose. When the
//  API renames a field or starts sending null where it used to send a string,
//  only this file and its mapping change.
//

import Foundation

struct ArticleDTO: Decodable, Sendable {
    let id: Int
    let userId: Int
    let title: String
    let body: String
}

extension ArticleDTO {
    /// Maps the wire format onto the domain model.
    var asArticle: Article {
        Article(
            id: id,
            authorID: userId,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: body.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
