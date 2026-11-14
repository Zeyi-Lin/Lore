import Foundation
import CoreGraphics
import ImageIO

/// Thread-safe holder so decoded `CGImage`s can live in `NSCache`.
final class CGImageBox: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

/// Background image loader with a byte-bounded cache and bounded concurrency.
///
/// The old `LibraryImage` only called `NSImage(contentsOfFile:)`, which parses
/// the header and defers the real (60–70 ms) decode to the main thread at draw
/// time. This loader decodes to the *display* pixel size off the main thread and
/// returns an already-decoded `CGImage`.
actor ImageLoader {
    static let shared = ImageLoader()

    private let cache = NSCache<NSString, CGImageBox>()
    private var inflight: [String: Task<CGImage?, Never>] = [:]
    private let maxConcurrent: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int = max(2, min(6, ProcessInfo.processInfo.activeProcessorCount / 2))) {
        self.maxConcurrent = maxConcurrent
        cache.totalCostLimit = 128 * 1024 * 1024
        cache.countLimit = 600
    }

    /// `maxPixel == 0` means "decode at native size" (used by the large image mode).
    func image(paths: [String], maxPixel: Int) async -> CGImage? {
        guard !paths.isEmpty else { return nil }
        let key = Self.cacheKey(paths: paths, maxPixel: maxPixel)
        if let cached = cache.object(forKey: key as NSString) {
            return cached.image
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
        cache.removeAllObjects()
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
            cache.setObject(CGImageBox(image), forKey: key as NSString, cost: image.bytesPerRow * image.height)
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
