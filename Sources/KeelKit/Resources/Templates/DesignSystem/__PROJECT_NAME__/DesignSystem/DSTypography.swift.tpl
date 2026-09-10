//
//  DSTypography.swift
//  __PROJECT_NAME__
//
//  Every font in the app. Reach for a token rather than Font.system(size:) —
//  otherwise the type scale drifts one screen at a time.
//

import SwiftUI

extension Font {
    // Display
    static let displayLarge = Font.system(size: 40, weight: .bold)
    static let displayMedium = Font.system(size: 32, weight: .bold)
    static let displaySmall = Font.system(size: 28, weight: .bold)

    // Headline
    static let headlineLarge = Font.system(size: 24, weight: .semibold)
    static let headlineMedium = Font.system(size: 20, weight: .semibold)
    static let headlineSmall = Font.system(size: 17, weight: .semibold)

    // Body — use these for anything a person actually reads.
    static let bodyLarge = Font.system(size: 17, weight: .regular)
    static let bodyMedium = Font.system(size: 15, weight: .regular)
    static let bodySmall = Font.system(size: 13, weight: .regular)

    // Label
    static let labelLarge = Font.system(size: 15, weight: .medium)
    static let labelMedium = Font.system(size: 13, weight: .medium)
    static let labelSmall = Font.system(size: 11, weight: .medium)

    // Caption — reserve for metadata, never for body copy.
    static let captionLarge = Font.system(size: 12, weight: .regular)
    static let captionSmall = Font.system(size: 11, weight: .regular)

    // Button
    static let buttonLarge = Font.system(size: 18, weight: .semibold)
    static let buttonMedium = Font.system(size: 16, weight: .semibold)
    static let buttonSmall = Font.system(size: 14, weight: .semibold)
}

extension View {
    /// Body copy that wraps instead of truncating, with comfortable leading.
    func dsReadableText() -> some View {
        lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}
