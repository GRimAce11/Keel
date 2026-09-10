//
//  ContentView.swift
//  __PROJECT_NAME__
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "swift")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("__PROJECT_NAME__")
                .font(.title.bold())

            Text("Start building in ContentView.swift")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
