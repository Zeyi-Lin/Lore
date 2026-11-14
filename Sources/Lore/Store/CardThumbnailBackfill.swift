import Foundation

/// One-time, low-priority backfill of 640 px grid derivatives for libraries
/// created before `Cards/` existed. Resumable by construction: it skips any
/// pin whose card file is already present.
enum CardThumbnailBackfill {
    static func run(root: URL, pins: [Pin]) async {
        guard !pins.isEmpty else { return }
        let fileManager = FileManager.default
        let cardsDirectory = LorePaths.cardsDirectory(root: root)
        try? fileManager.createDirectory(at: cardsDirectory, withIntermediateDirectories: true)

        for pin in pins {
            if Task.isCancelled { return }
            let destination = cardsDirectory.appendingPathComponent("\(pin.id.uuidString).jpg")
            if fileManager.fileExists(atPath: destination.path) { continue }

            // Prefer the existing 1200 px thumbnail: decoding it is ~3 ms,
            // whereas a 4K original can cost 60 ms+.
            var sourceURL = root.appendingPathComponent(pin.image)
            if let thumbnail = pin.thumbnail {
                let candidate = root.appendingPathComponent(thumbnail)
                if fileManager.fileExists(atPath: candidate.path) { sourceURL = candidate }
            }
            _ = ImageProcessor.writeCardThumbnail(sourcePath: sourceURL.path, root: root, id: pin.id)
            try? await Task.sleep(nanoseconds: 8_000_000)
        }
    }
}
