//
//  __PROJECT_NAME__App.swift
//  __PROJECT_NAME__
//
//  Created on __DATE__.
//

import SwiftUI
// keel:if persistence
import SwiftData
// keel:end

@main
struct __PROJECT_NAME__App: App {

// keel:if dependencyInjection
    // The container is owned here and injected into the environment. Views
    // read it with @Environment(AppContainer.self) — never by constructing
    // their own, which would spin up a second copy of every service.
    @State private var container = AppContainer()
// keel:end

    var body: some Scene {
        WindowGroup {
            RootView()
// keel:if dependencyInjection
                .environment(container)
// keel:end
// keel:if persistence
// keel:if dependencyInjection
                .modelContainer(container.persistence.container)
// keel:else
                .modelContainer(PersistenceController.shared.container)
// keel:end
// keel:end
        }
    }
}
