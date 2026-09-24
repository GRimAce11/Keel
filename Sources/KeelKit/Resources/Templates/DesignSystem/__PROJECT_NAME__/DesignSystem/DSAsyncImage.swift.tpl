//
//  DSAsyncImage.swift
//  __PROJECT_NAME__
//

import SwiftUI

/// `AsyncImage` with the three things it lacks once the images are real
/// photographs: it retries a failed download with back-off, it decodes at
/// display size rather than at upload resolution, and it shows a shimmer
/// instead of a bare spinner.
///
/// Successful loads are memoised in `DSImageCache`, so a row scrolled back
/// into view redraws without a network call and without a second decode.
///
/// ```swift
/// DSAsyncImage(url: article.imageURL, maxPixels: DSImageLoader.thumbnailMaxPixels) { image in
///     image.resizable().scaledToFill()
/// } failed: {
///     Image(systemName: "photo")
/// }
/// ```
///
/// The `Image` handed to `success` is decorative, so VoiceOver skips it —
/// right for a thumbnail beside a label that already says what it is. Where
/// the image *is* the content, add `.accessibilityLabel(_:)` at the call site.
struct DSAsyncImage<Success: View, Failed: View>: View {

    let url: URL?
    let maxAttempts: Int
    let maxPixels: Int
    let cornerRadius: CGFloat
    let success: (Image) -> Success
    let failed: () -> Failed

    @State private var image: CGImage?
    @State private var didFail = false

    init(
        url: URL?,
        maxAttempts: Int = 3,
        maxPixels: Int = DSImageLoader.defaultMaxPixels,
        cornerRadius: CGFloat = DSRadius.md,
        @ViewBuilder success: @escaping (Image) -> Success,
        @ViewBuilder failed: @escaping () -> Failed
    ) {
        self.url = url
        self.maxAttempts = maxAttempts
        self.maxPixels = maxPixels
        self.cornerRadius = cornerRadius
        self.success = success
        self.failed = failed
        // Seeded synchronously, because `.task` only runs after the first
        // render: without this a cached image still flashes a shimmer every
        // time its row is recycled.
        _image = State(initialValue: url.flatMap {
            DSImageCache.shared.object(forKey: DSImageCache.key(for: $0, maxPixels: maxPixels))
        })
    }

    var body: some View {
        ZStack {
            if let image {
                success(Image(decorative: image, scale: 1))
            } else if didFail {
                failed()
            } else {
                DSShimmerPlaceholder(cornerRadius: cornerRadius)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            image = nil
            didFail = true
            return
        }

        let key = DSImageCache.key(for: url, maxPixels: maxPixels)

        if let cached = DSImageCache.shared.object(forKey: key) {
            image = cached
            didFail = false
            return
        }

        // A recycled row arrives here still holding the previous URL's image.
        // Clearing it is what stops the wrong photo showing under the new one
        // until the download lands.
        image = nil
        didFail = false

        for attempt in 0..<maxAttempts {
            if Task.isCancelled { return }

            do {
                var request = URLRequest(url: url)
                // The first attempt may be served from the session's cache;
                // later ones bypass it, so a cached transient failure is not
                // replayed as the answer to every retry.
                if attempt > 0 {
                    request.cachePolicy = .reloadIgnoringLocalCacheData
                }

                let (data, response) = try await DSImageLoader.session.data(for: request)

                if let http = response as? HTTPURLResponse {
                    // 4xx means the image is gone for good — spending the
                    // remaining attempts and their delays on it only keeps a
                    // shimmer on screen for another second and a half.
                    if (400..<500).contains(http.statusCode) {
                        didFail = true
                        return
                    }
                    if !(200..<300).contains(http.statusCode) {
                        throw URLError(.badServerResponse)
                    }
                }

                guard let decoded = await DSImageLoader.decodeDetached(data, maxPixels: maxPixels) else {
                    // Bytes arrived but are not an image. Retried like any
                    // other failure — a truncated response is common enough,
                    // and back-off is cheaper than an immediate second pull.
                    throw URLError(.cannotDecodeContentData)
                }

                guard !Task.isCancelled else { return }
                DSImageCache.shared.setObject(decoded, forKey: key, cost: DSImageCache.cost(for: decoded))
                image = decoded
                return

            } catch {
                guard !Task.isCancelled else { return }
                // Linear back-off: 0.4s, then 0.8s. Nothing after the last
                // attempt — a delay there only postpones the failure view.
                if attempt < maxAttempts - 1 {
                    try? await Task.sleep(for: .seconds(Double(attempt + 1) * 0.4))
                }
            }
        }

        didFail = true
    }
}

// Previews never reach the network — it makes the canvas slow and flaky — so
// this one shows the state a nil URL resolves to immediately.
#Preview("Failed") {
    DSAsyncImage(url: nil) { image in
        image.resizable().scaledToFill()
    } failed: {
        Image(systemName: "photo")
            .font(.system(size: DSSize.iconLarge))
            .foregroundStyle(DSColors.textTertiary)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 180)
    .background(DSColors.backgroundSecondary)
    .clipShape(RoundedRectangle(cornerRadius: DSRadius.md))
    .padding(DSSpacing.md)
}
