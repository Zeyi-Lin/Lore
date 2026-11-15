import Foundation
import CoreGraphics
import ImageIO
import LoreAgentKit

/// Thread-safe holder so decoded `CGImage`s can live in `NSCache`.
final class CGImageBox: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

/// Lock-free, thread-safe cache store shared by the actor and synchronous
/// cache lookups from view initialization.
final class ImageStore: @unchecked Sendable {
    private let cache = NSCache<NSString, CGImageBox>()

    init(totalCostLimit: Int, countLimit: Int) {
        cache.totalCostLimit = totalCostLimit
        cache.countLimit = countLimit
    }

    func image(for key: String) -> CGImage? {
        cache.object(forKey: key as NSString)?.image
    }

    func insert(_ image: CGImage, for key: String) {
        cache.setObject(CGImageBox(image), forKey: key as NSString, cost: image.bytesPerRow * image.height)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

/// Background image loader with a byte-bounded cache and bounded concurrency.
///
/// The old `LibraryImage` only called `NSImage(contentsOfFile:)`, which parses
/// the header and defers the real (60–70 ms) decode to the main thread at draw
/// time. This loader decodes to the *display* pixel size off the main thread and
/// returns an already-decoded `CGImage`.
actor ImageLoader {
    static let shared = ImageLoader()

    /// The detail card grows with the window, so it asks for a larger decode
    /// than the old fixed 1200 px pane. 2400 px covers a 2x display at the
    /// card's maximum size; one decoded bitmap stays in the 15–23 MB range.
    static let detailMaxPixel = 2400

    nonisolated let store: ImageStore
    private var inflight: [String: Task<CGImage?, Never>] = [:]
    private let maxConcurrent: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int = max(2, min(6, ProcessInfo.processInfo.activeProcessorCount / 2))) {
        self.maxConcurrent = maxConcurrent
        self.store = ImageStore(totalCostLimit: 128 * 1024 * 1024, countLimit: 600)
    }

    /// Synchronous cache hit used by `LibraryImage.init`, so a hover-prefetched
    /// image can be installed in the very first rendered frame.
    nonisolated func cachedImage(paths: [String], maxPixel: Int) -> CGImage? {
        guard !paths.isEmpty else { return nil }
        return store.image(for: Self.cacheKey(paths: paths, maxPixel: maxPixel))
    }

    /// `maxPixel == 0` means "decode at native size" (used by the large image mode).
    func image(paths: [String], maxPixel: Int) async -> CGImage? {
        guard !paths.isEmpty else { return nil }
        let key = Self.cacheKey(paths: paths, maxPixel: maxPixel)
        if let cached = store.image(for: key) {
            return cached
        }
        if let running = inflight[key] {
            return await running.value
        }

        let task = Task.detached(priority: .userInitiated) { [weak self] () -> CGImage? in
            guard let self else { return nil }
            await self.acquire()
            let state = Perf.begin("image.decode")
            let image = Self.decode(paths: paths, maxPixel: maxPixel)
            Perf.end("image.decode", state)
            await self.finish(image: image, key: key)
            return image
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        return result
    }

    func prefetch(_ requests: [(paths: [String], maxPixel: Int)]) async {
        for request in requests {
            _ = await image(paths: request.paths, maxPixel: request.maxPixel)
        }
    }

    func purge() {
        store.removeAll()
    }

    // MARK: - Slot gate

    private func acquire() async {
        if active < maxConcurrent {
            active += 1
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    private func finish(image: CGImage?, key: String) {
        if let image {
            store.insert(image, for: key)
        }
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
        } else {
            active = max(0, active - 1)
        }
    }

    private static func cacheKey(paths: [String], maxPixel: Int) -> String {
        "\(maxPixel)|" + paths.joined(separator: "|")
    }

    private static func decode(paths: [String], maxPixel: Int) -> CGImage? {
        for path in paths {
            // ImageIO has no SVG decoder, but AppKit rasterises vectors through
            // `NSImage`. Decoding here (background queue, at the requested
            // pixel size) keeps the cache contract identical for vectors and
            // bitmaps: the view receives an already-drawn `CGImage`.
            if path.lowercased().hasSuffix(".svg") {
                if let vector = SVGRasterizer.rasterize(
                    fileURL: URL(fileURLWithPath: path),
                    maxPixel: maxPixel
                ) {
                    return vector
                }
                continue
            }
            guard let source = CGImageSourceCreateWithURL(
                URL(fileURLWithPath: path) as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ) else { continue }

            if maxPixel <= 0 {
                if let image = CGImageSourceCreateImageAtIndex(
                    source, 0,
                    [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
                ) {
                    return image
                }
                continue
            }

            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceShouldCacheImmediately: true
            ]
            if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return image
            }
            if let image = CGImageSourceCreateImageAtIndex(
                source, 0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            ) {
                return image
            }
        }
        return nil
    }
}
