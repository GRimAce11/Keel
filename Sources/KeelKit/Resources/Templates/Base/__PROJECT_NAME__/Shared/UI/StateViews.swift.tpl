//
//  StateViews.swift
//  __PROJECT_NAME__
//
//  The screens every loading view needs. Kept together because they share a
//  layout and are almost always changed as a set.
//

import SwiftUI

struct LoadingView: View {
    var message: String?

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorStateView: View {
    let error: AppError
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("Something went wrong", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct EmptyStateView: View {
    var title: String = "Nothing here yet"
    var message: String?
    var systemImage: String = "tray"

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message { Text(message) }
        }
    }
}

#Preview("Loading") {
    LoadingView(message: "Loading…")
}

#Preview("Error") {
    ErrorStateView(error: .timeout, retry: {})
}

#Preview("Empty") {
    EmptyStateView(message: "Pull to refresh once you have data.")
}
