//
//  RootView.swift
//  __PROJECT_NAME__
//

import SwiftUI

/// The app's first screen. Replace this with your own navigation — a
/// `TabView`, a router, or whatever the project needs.
struct RootView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "swift")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("__PROJECT_NAME__")
                .font(.title.bold())

            Text("Start building in RootView.swift")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    RootView()
}
