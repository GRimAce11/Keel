//
//  DSTypography.swift
//  __PROJECT_NAME__
//
//  Every font in the app. Reach for a token rather than Font.system(size:) —
//  otherwise the type scale drifts one screen at a time.
//
//  Each token is built on a text style, not on a point size, so it grows and
//  shrinks with Dynamic Type. `Font.system(size: 17)` does not: an app whose
//  body copy is written that way stays at 17pt however large the reader has
//  set their text, which is the single most common accessibility failure in a
//  SwiftUI codebase. The comments give the size each token resolves to at the
//  default text size.
//
//  When you adopt a typeface, swap these for
//  `Font.custom("YourFont-Regular", size: 17, relativeTo: .body)` — that form
//  takes an exact size and still scales.
//

import SwiftUI

extension Font {

    // Display
    static let displayLarge = Font.system(.largeTitle, weight: .bold)      // 34
    static let displayMedium = Font.system(.title, weight: .bold)          // 28
    static let displaySmall = Font.system(.title2, weight: .bold)          // 22

    // Headline
    static let headlineLarge = Font.system(.title3, weight: .semibold)     // 20
    static let headlineMedium = Font.system(.headline)                     // 17
    static let headlineSmall = Font.system(.subheadline, weight: .semibold) // 15

    // Body — use these for anything a person actually reads.
    static let bodyLarge = Font.system(.body)                              // 17
    static let bodyMedium = Font.system(.callout)                          // 16
    static let bodySmall = Font.system(.footnote)                          // 13

    // Label
    static let labelLarge = Font.system(.subheadline, weight: .medium)     // 15
    static let labelMedium = Font.system(.footnote, weight: .medium)       // 13
    static let labelSmall = Font.system(.caption2, weight: .medium)        // 11

    // Caption — reserve for metadata, never for body copy.
    static let captionLarge = Font.system(.caption)                        // 12
    static let captionSmall = Font.system(.caption2)                       // 11

    // Button
    static let buttonLarge = Font.system(.headline)                        // 17
    static let buttonMedium = Font.system(.callout, weight: .semibold)     // 16
    static let buttonSmall = Font.system(.subheadline, weight: .semibold)  // 15
}

extension View {
    /// Body copy that wraps instead of truncating, with comfortable leading.
    func dsReadableText() -> some View {
        lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}
