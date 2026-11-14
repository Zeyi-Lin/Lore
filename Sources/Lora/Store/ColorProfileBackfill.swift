import Foundation
import ImageIO
import LoraAgentKit

/// Resumable, low-priority colour analysis for pins created before colour
/// families existed (or added by an older Agent API). It decodes a small
/// ImageIO thumbnail — not the original — so a 4K screenshot costs the same as
/// a phone-sized one.
enum ColorProfileBackfill {
    static func run(root: URL, pins: [Pin]) async -> [UUID: LoraColorProfile] {
        var profiles: [UUID: LoraColorProfile] = [:]
        for pin in pins {
            if Task.isCancelled { return profiles }
            let needsFamilies = pin.colorFamilies?.isEmpty ?? true
            guard needsFamilies || pin.colorTone == nil else { continue }

            let candidates = [pin.thumbnail, pin.image].compactMap { $0 }
            for relative in candidates {
                let url = root.appendingPathComponent(relative)
                if let profile = profile(for: url) {
                    profiles[pin.id] = profile
                    break
                }
            }
            try? await Task.sleep(nanoseconds: 4_000_000)
        }
        return profiles
    }

    private static func profile(for url: URL) -> LoraColorProfile? {
        guard FileManager.default.fileExists(atPath: url.path),
              let source = CGImageSourceCreateWithURL(
                url as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary
              ) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 128,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return LoraColorAnalyzer.classify(image: image)
    }
}
