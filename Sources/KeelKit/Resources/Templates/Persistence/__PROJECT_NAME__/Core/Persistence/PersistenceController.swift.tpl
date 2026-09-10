//
//  PersistenceController.swift
//  __PROJECT_NAME__
//

import Foundation
import SwiftData

/// Owns the SwiftData stack.
///
/// Register every `@Model` type in `schema`. A container is built from an
/// explicit schema rather than inferred, so adding a model without registering
/// it fails visibly at launch instead of silently not persisting.
@MainActor
final class PersistenceController {

    static let shared = PersistenceController()

    /// In-memory, for previews and tests. Never touches the on-disk store, so
    /// a test run cannot corrupt real data or leak state into the next test.
    static let preview = PersistenceController(inMemory: true)

    let container: ModelContainer

    private static let schema = Schema([
        StoredItem.self,
    ])

    init(inMemory: Bool = false) {
        let configuration = ModelConfiguration(
            schema: Self.schema,
            isStoredInMemoryOnly: inMemory
        )

        do {
            container = try ModelContainer(for: Self.schema, configurations: configuration)
        } catch {
            // A container that cannot open means every read and write below
            // would fail anyway. Failing loudly here points at the real cause —
            // usually a model change with no migration — instead of surfacing
            // as empty screens later.
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    /// Saves only when something actually changed.
    func save() {
        let context = container.mainContext
        guard context.hasChanges else { return }

        do {
            try context.save()
        } catch {
            AppLogger.data.error("Failed to save context: \(error.localizedDescription)")
        }
    }
}
