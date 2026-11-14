import Foundation
import LoraAgentKit

/// Fills in animation metadata for GIF pins created before Lora understood
/// GIFs (or added by an older Agent API). The pin JSON may say `frameCount: 1`
/// for an existing animated GIF; the UI already animates by extension, and this
/// backfill corrects the stored metadata and API response.
enum AnimationMetadataBackfill {
    static func run(root: URL, pins: [Pin]) async -> [UUID: LoraImageAnimation] {
        var detected: [UUID: LoraImageAnimation] = [:]
        for pin in pins {
            if Task.isCancelled { return detected }
            guard pin.isGIF, pin.frameCount <= 1 else { continue }
            let url = root.appendingPathComponent(pin.image)
            if let animation = LoraImageAnalyzer.animation(imageURL: url), animation.isAnimated {
                detected[pin.id] = animation
            }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return detected
    }
}
