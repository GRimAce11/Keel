//
//  StoredItem.swift
//  __PROJECT_NAME__
//

import Foundation
import SwiftData

/// A placeholder model so the container has a valid schema from the first
/// launch. Replace it with your own — and remember to update
/// `PersistenceController.schema` when you do.
@Model
final class StoredItem {
    /// Unique so re-saving the same remote object updates it rather than
    /// inserting a duplicate.
    @Attribute(.unique) var id: String
    var title: String
    var createdAt: Date

    init(id: String = UUID().uuidString, title: String, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
    }
}
