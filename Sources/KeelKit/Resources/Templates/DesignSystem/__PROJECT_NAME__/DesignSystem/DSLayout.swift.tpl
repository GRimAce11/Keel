//
//  DSLayout.swift
//  __PROJECT_NAME__
//
//  Spacing, radius and size tokens. Use these instead of raw numbers — a
//  magic 14 somewhere is invisible when the scale changes.
//

import SwiftUI

enum DSSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    /// Standard screen and card padding.
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    static let xxxl: CGFloat = 64
}

enum DSRadius {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    /// Standard card corner.
    static let md: CGFloat = 14
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
    /// Capsule.
    static let full: CGFloat = 999
}

enum DSSize {
    /// The smallest a tappable target may be, per Apple's HIG.
    ///
    /// An icon button whose glyph is smaller still needs this much hit area:
    /// `.frame(minWidth: DSSize.hitTargetMin, minHeight: DSSize.hitTargetMin)`
    /// plus `.contentShape(Rectangle())`, so the padding is tappable without
    /// distorting the glyph.
    static let hitTargetMin: CGFloat = 44

    static let buttonHeightLarge: CGFloat = 60
    static let buttonHeightMedium: CGFloat = 50
    static let buttonHeightSmall: CGFloat = 40
    static let textFieldHeight: CGFloat = 56

    static let iconSmall: CGFloat = 16
    static let iconMedium: CGFloat = 24
    static let iconLarge: CGFloat = 32

    static let avatarSmall: CGFloat = 32
    static let avatarMedium: CGFloat = 48
    static let avatarLarge: CGFloat = 80
}

extension View {
    /// Expands a control to the minimum tap target without changing how big it
    /// looks.
    func dsHitTarget() -> some View {
        frame(minWidth: DSSize.hitTargetMin, minHeight: DSSize.hitTargetMin)
            .contentShape(Rectangle())
    }
}
