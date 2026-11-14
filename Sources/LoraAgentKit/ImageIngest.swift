import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// A decoded, validated image ready to be persisted as a Lora pin.
struct ProcessedImage {
    let originalData: Data
    let fileExtension: String
    let width: Int
    let height: Int
    let colors: [String]
    let thumbnailJPEG: Data
}

/// Validates upload bytes with ImageIO and derives the derived assets Lora
/// stores for a pin: pixel dimensions, a JPEG thumbnail (max 1200 px), and up
/// to five dominant palette colours.
enum ImageIngestProcessor {
    static let maxThumbnailPixelSize = 1200
    private static let thumbnailJPEGQuality: CGFloat = 0.82
    private static let paletteColorLimit = 5
    private static let paletteSampleSize = 32

    static func process(_ data: Data, declaredMimeType: String?) throws -> ProcessedImage {
        guard !data.isEmpty else {
            throw PinIngestError.missingImage("The request did not include any image bytes.")
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else {
            throw PinIngestError.invalidImageData("The uploaded bytes are not a supported image format.")
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PinIngestError.invalidImageData("The uploaded image could not be decoded.")
        }
        guard image.width > 0, image.height > 0 else {
            throw PinIngestError.invalidImageData("The uploaded image has invalid pixel dimensions.")
        }
        let fileExtension = fileExtension(for: source, declaredMimeType: declaredMimeType)
        let thumbnail = try makeThumbnail(source: source, fallback: image)
        guard let jpeg = encodeJPEG(thumbnail) else {
            throw PinIngestError.invalidImageData("The uploaded image could not be encoded as a JPEG thumbnail.")
        }
        return ProcessedImage(
            originalData: data,
            fileExtension: fileExtension,
            width: image.width,
            height: image.height,
            colors: palette(from: thumbnail),
            thumbnailJPEG: jpeg
        )
    }

    // MARK: - Format naming

    private static func fileExtension(for source: CGImageSource, declaredMimeType: String?) -> String {
        if let typeIdentifier = CGImageSourceGetType(source) as String?,
           let type = UTType(typeIdentifier),
           let extensionName = type.preferredFilenameExtension,
           isSafeExtension(extensionName) {
            return normalizedExtension(extensionName)
        }
        if let declaredMimeType, let extensionName = fileExtension(forMimeType: declaredMimeType) {
            return extensionName
        }
        return "png"
    }

    private static func normalizedExtension(_ value: String) -> String {
        switch value.lowercased() {
        case "jpeg": return "jpg"
        case "tif": return "tiff"
        default: return value.lowercased()
        }
    }

    private static func isSafeExtension(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 8 else { return false }
        return value.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber)
        }
    }

    private static func fileExtension(forMimeType mimeType: String) -> String? {
        switch mimeType.lowercased() {
        case "image/png": return "png"
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/heic": return "heic"
        case "image/heif": return "heif"
        case "image/tiff": return "tiff"
        case "image/bmp": return "bmp"
        case "image/avif": return "avif"
        default: return nil
        }
    }

    // MARK: - Thumbnail

    private static func makeThumbnail(source: CGImageSource, fallback image: CGImage) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxThumbnailPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return thumbnail
        }
        return try scaledImage(image)
    }

    private static func scaledImage(_ image: CGImage) throws -> CGImage {
        let longestSide = max(image.width, image.height)
        let scale = longestSide > maxThumbnailPixelSize ? CGFloat(maxThumbnailPixelSize) / CGFloat(longestSide) : 1
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PinIngestError.invalidImageData("The uploaded image could not be resized.")
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else {
            throw PinIngestError.invalidImageData("The uploaded image could not be resized.")
        }
        return result
    }

    private static func encodeJPEG(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: thumbnailJPEGQuality
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return Data(referencing: output)
    }

    // MARK: - Palette

    private static func palette(from image: CGImage) -> [String] {
        let sampleSize = paletteSampleSize
        let bytesPerRow = sampleSize * 4
        var pixels = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)
        let drawn = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: sampleSize,
                height: sampleSize,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))
            return true
        }
        guard drawn else { return [] }

        struct Bucket {
            var count = 0
            var redSum = 0
            var greenSum = 0
            var blueSum = 0
        }
        var buckets: [Int: Bucket] = [:]
        var index = 0
        while index + 3 < pixels.count {
            let alpha = Int(pixels[index + 3])
            if alpha > 8 {
                let alphaScale = Double(alpha) / 255.0
                let red = alphaScale < 0.98 ? min(255, Int(Double(pixels[index]) / alphaScale)) : Int(pixels[index])
                let green = alphaScale < 0.98 ? min(255, Int(Double(pixels[index + 1]) / alphaScale)) : Int(pixels[index + 1])
                let blue = alphaScale < 0.98 ? min(255, Int(Double(pixels[index + 2]) / alphaScale)) : Int(pixels[index + 2])
                let key = (red >> 4) << 8 | (green >> 4) << 4 | (blue >> 4)
                var bucket = buckets[key] ?? Bucket()
                bucket.count += 1
                bucket.redSum += red
                bucket.greenSum += green
                bucket.blueSum += blue
                buckets[key] = bucket
            }
            index += 4
        }
        guard !buckets.isEmpty else { return [] }
        let ordered = buckets.map { key, bucket -> (key: Int, count: Int, red: Int, green: Int, blue: Int) in
            let count = max(1, bucket.count)
            return (key, bucket.count, bucket.redSum / count, bucket.greenSum / count, bucket.blueSum / count)
        }.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.key < rhs.key
        }
        return ordered.prefix(paletteColorLimit).map { color in
            String(format: "#%02X%02X%02X", color.red, color.green, color.blue)
        }
    }
}
