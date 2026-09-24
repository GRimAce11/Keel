//
//  DSShimmer.swift
//  __PROJECT_NAME__
//

import SwiftUI

/// A skeleton block with a travelling highlight, for anything whose size is
/// known before its content is — an image tile, a card, a row.
///
/// Prefer this to a `ProgressView` wherever the final layout is already
/// decided: the placeholder occupies the space the content will, so nothing
/// jumps when it arrives.
struct DSShimmerPlaceholder: View {
    var cornerRadius: CGFloat = DSRadius.md

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        Color(.secondarySystemFill)
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, Color.primary.opacity(0.09), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.55)
                    .offset(x: phase * proxy.size.width * 1.6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onAppear {
                // A highlight sweeping forever is exactly what Reduce Motion
                // exists to silence. The plain block still reads as "loading".
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
            // It carries nothing VoiceOver can use, and announcing a
            // placeholder once per row of a list is noise.
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: DSSpacing.md) {
        DSShimmerPlaceholder()
            .frame(height: 160)
        DSShimmerPlaceholder(cornerRadius: DSRadius.sm)
            .frame(height: DSSize.buttonHeightSmall)
    }
    .padding(DSSpacing.md)
}
