import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Animation metadata for a pin's original image. Lora currently plays GIFs;
/// `isAnimated` also reports multi-frame images in other containers so the API
/// never has to guess.
public struct LoraImageAnimation: Equatable, Sendable {
    public let isAnimated: Bool
    public let isGIF: Bool
    public let frameCount: Int
    /// Sum of the GIF frame delays, in seconds. Zero for still images.
    public let duration: Double

    public init(isAnimated: Bool, isGIF: Bool, frameCount: Int, duration: Double) {
        self.isAnimated = isAnimated
        self.isGIF = isGIF
        self.frameCount = max(frameCount, 1)
        self.duration = max(duration, 0)
    }

    public static let still = LoraImageAnimation(
        isAnimated: false,
        isGIF: false,
        frameCount: 1,
        duration: 0
    )
}

/// Reads frame counts and GIF timing without decoding the frames themselves.
/// Both the app's import pipeline and Agent API ingestion use this, so a GIF
/// added by either path carries the same metadata.
public enum LoraImageAnalyzer {
    public static func animation(source: CGImageSource) -> LoraImageAnimation {
        let frameCount = max(1, CGImageSourceGetCount(source))
        let typeIdentifier = CGImageSourceGetType(source) as String?
        let isGIF = typeIdentifier == UTType.gif.identifier

        guard frameCount > 1, isGIF else {
            return LoraImageAnimation(
                isAnimated: frameCount > 1,
                isGIF: isGIF,
                frameCount: frameCount,
                duration: 0
            )
        }

        var duration = 0.0
        for index in 0..<frameCount {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let unclamped = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
            let clamped = (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
            let delay = unclamped ?? clamped ?? 0
            // Browsers and ImageIO treat sub-10 ms GIF delays as 100 ms.
            duration += delay < 0.011 ? 0.1 : delay
        }
        return LoraImageAnimation(
            isAnimated: true,
            isGIF: true,
            frameCount: frameCount,
            duration: duration
        )
    }

    public static func animation(imageURL: URL) -> LoraImageAnimation? {
        guard FileManager.default.fileExists(atPath: imageURL.path),
              let source = CGImageSourceCreateWithURL(
                imageURL as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary
              ) else {
            return nil
        }
        return animation(source: source)
    }

    public static func animation(data: Data) -> LoraImageAnimation? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            return nil
        }
        return animation(source: source)
    }
}
