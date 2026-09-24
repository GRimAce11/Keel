//
//  DSImageLoader.swift
//  __PROJECT_NAME__
//
//  What `DSAsyncImage` loads with, kept separate because prefetching, a
//  fullscreen viewer and a share sheet all want the same decode and the same
//  cache as the row the user tapped.
//
//  ImageIO rather than UIKit: `CGImage` is what SwiftUI's `Image` takes and
//  what the decode already produces, so there is no `UIImage` in the middle
//  and no UIKit in a SwiftUI app.
//

import Foundation
import ImageIO

enum DSImageLoader {

    /// Longest edge, in pixels, when a call site does not ask for one. Above
    /// any single device screen edge, so a full-width image stays sharp.
    static let defaultMaxPixels = 1280

    /// Longest edge for a thumbnail in a list row or a grid cell.
    static let thumbnailMaxPixels = 600

    /// Images, kept apart from the API session: media may be cached and is
    /// allowed to fail fast, API responses are neither.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        // Compressed bytes in memory only — the app's storage footprint should
        // not grow with the number of images scrolled past.
        configuration.urlCache = URLCache(memoryCapacity: 32 * 1_024 * 1_024, diskCapacity: 0)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpShouldSetCookies = false
        // Tight, so a row on a poor network fails and retries rather than
        // holding a connection and its buffers open.
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    /// Decodes at the size the image is displayed rather than the size it was
    /// uploaded at.
    ///
    /// A full decode expands a 4000×3000 photo to roughly 48 MB resident
    /// however small it is drawn — a scrolling list of those is what exhausts
    /// memory on smaller devices. `CGImageSourceCreateThumbnailAtIndex`
    /// decodes straight to the size asked for instead.
    ///
    /// Falls back to a full decode when thumbnailing fails, so valid bytes
    /// always produce an image.
    static func decode(_ data: Data, maxPixels: Int = defaultMaxPixels) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            // Without this, a photo shot in portrait comes back on its side.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// `decode` off the calling actor.
    ///
    /// A SwiftUI view's `.task` body runs on the main actor. Decoding a large
    /// image inline there stalls the very scroll that asked for it.
    static func decodeDetached(_ data: Data, maxPixels: Int = defaultMaxPixels) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            decode(data, maxPixels: maxPixels)
        }.value
    }
}

/// Decoded images, so a row scrolled back into view costs nothing. `NSCache`
/// evicts under memory pressure by itself — there is no policy to maintain.
enum DSImageCache {

    // NSCache is thread safe but predates Sendable, so the compiler needs
    // telling. Reading and writing it from any actor is safe.
    nonisolated(unsafe) static let shared: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 48 * 1_024 * 1_024
        return cache
    }()

    /// The decode size belongs in the key alongside the URL. A row asks for
    /// `thumbnailMaxPixels` and a fullscreen viewer for the larger default;
    /// keyed on the URL alone, whichever ran first would hand the other its
    /// size — usually a thumbnail, blown up.
    static func key(for url: URL, maxPixels: Int) -> NSString {
        "\(maxPixels)|\(url.absoluteString)" as NSString
    }

    /// Resident bytes, so `totalCostLimit` is measured in memory rather than
    /// in a count of images whose sizes vary by two orders of magnitude.
    static func cost(for image: CGImage) -> Int {
        image.bytesPerRow * image.height
    }
}
