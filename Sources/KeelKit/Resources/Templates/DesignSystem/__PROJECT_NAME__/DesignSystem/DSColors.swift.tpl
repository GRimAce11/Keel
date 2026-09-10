//
//  DSColors.swift
//  __PROJECT_NAME__
//
//  Semantic colours. Name what a colour is for, not what it looks like —
//  `textSecondary` survives a rebrand, `.gray` does not.
//
//  These default to system colours so the app is correct in light and dark
//  from the first launch. Replace the values with your own palette, ideally by
//  adding colour sets to Assets.xcassets and reading them here.
//

import SwiftUI

enum DSColors {

    // Brand
    static let brandPrimary = Color.accentColor
    static let brandSecondary = Color.accentColor.opacity(0.7)

    // Background
    static let backgroundPrimary = Color(.systemBackground)
    static let backgroundSecondary = Color(.secondarySystemBackground)
    static let backgroundTertiary = Color(.tertiarySystemBackground)
    static let backgroundCard = Color(.secondarySystemGroupedBackground)

    // Text
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)
    static let textDisabled = Color(.quaternaryLabel)

    // Status
    static let statusSuccess = Color.green
    static let statusWarning = Color.orange
    static let statusError = Color.red
    static let statusInfo = Color.blue

    // Lines and overlays
    static let borderDefault = Color(.separator)
    static let borderFocused = Color.accentColor
    static let overlayLight = Color.black.opacity(0.1)
    static let overlayMedium = Color.black.opacity(0.4)
}

extension View {
    /// Standard card surface: fill, rounded corner, hairline border.
    func dsCard(padding: CGFloat = DSSpacing.md) -> some View {
        self
            .padding(padding)
            .background(DSColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.md)
                    .strokeBorder(DSColors.borderDefault, lineWidth: 0.5)
            )
    }
}
