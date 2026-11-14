import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import LoraAgentKit

struct ProcessedImage: Sendable {
    var image: String
    var thumbnail: String?
    var width: Int
    var height: Int
    var fileSize: Int
    var colors: [String]
    var colorFamilies: [LoraColorFamily]
    var colorTone: LoraColorTone
    var isAnimated: Bool
    var frameCount: Int
    var kind: PinKind
}

enum ImageProcessingError: LocalizedError {
    case unreadable(String)
    case unsupported(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): return TF("%@ isn't a readable image.", name)
        case .unsupported(let name): return TF("%@ uses an unsupported image format.", name)
        case .writeFailed(let message): return TF("Couldn't store the image: %@", message)
        }
    }
}

enum ImageProcessor {
    static func process(fileURL: URL, root: URL, id: UUID) throws -> ProcessedImage {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ImageProcessingError.unreadable(fileURL.lastPathComponent)
        }
        guard CGImageSourceGetCount(source) > 0, CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw ImageProcessingError.unsupported(fileURL.lastPathComponent)
        }

        try LoraPaths.ensureDirectories(root: root)
        let fileExtension = fileExtension(for: source) ?? fileURL.pathExtension.lowercased().nilIfEmpty ?? "png"
        let relativeImage = "Images/\(id.uuidString).\(fileExtension)"
        let destination = root.appendingPathComponent(relativeImage)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: fileURL, to: destination)
        } catch {
            throw ImageProcessingError.writeFailed(error.localizedDescription)
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        return try finish(source: source, root: root, id: id, relativeImage: relativeImage, fileSize: fileSize, kind: detectKind(source: source, fileURL: fileURL))
    }

    static func process(data: Data, preferredExtension: String?, root: URL, id: UUID) throws -> ProcessedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ImageProcessingError.unreadable("Clipboard image")
        }
        guard CGImageSourceGetCount(source) > 0, CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw ImageProcessingError.unsupported("Clipboard image")
        }

        try LoraPaths.ensureDirectories(root: root)
        let fileExtension = (preferredExtension ?? fileExtension(for: source) ?? "png").lowercased()
        let relativeImage = "Images/\(id.uuidString).\(fileExtension)"
        let destination = root.appendingPathComponent(relativeImage)
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            throw ImageProcessingError.writeFailed(error.localizedDescription)
        }

        return try finish(source: source, root: root, id: id, relativeImage: relativeImage, fileSize: data.count, kind: .screenshot)
    }

    private static func finish(
        source: CGImageSource,
        root: URL,
        id: UUID,
        relativeImage: String,
        fileSize: Int,
        kind: PinKind
    ) throws -> ProcessedImage {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 1
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 1

        var relativeThumbnail: String?
        var paletteSource: CGImage?
        if let thumbnail = makeThumbnail(from: source, maxPixel: 1200) {
            let relative = "Thumbnails/\(id.uuidString).jpg"
            let destination = root.appendingPathComponent(relative)
            if writeJPEG(thumbnail, to: destination) {
                relativeThumbnail = relative
                paletteSource = thumbnail
            }
        }

        // Card-sized derivative for the gallery grid. Not represented in
        // library.json: the path is derived from the pin id.
        if let card = makeThumbnail(from: source, maxPixel: 640) ?? paletteSource {
            let destination = LoraPaths.cardsDirectory(root: root)
                .appendingPathComponent("\(id.uuidString).jpg")
            _ = writeJPEG(card, to: destination)
        }
        if paletteSource == nil {
            paletteSource = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 120,
                kCGImageSourceCreateThumbnailWithTransform: true
            ] as CFDictionary)
        }

        let colors = paletteSource.map(extractPalette(from:)) ?? []
        let profile = paletteSource.map { LoraColorAnalyzer.classify(image: $0) }
            ?? LoraColorAnalyzer.classify(palette: colors)
        let animation = LoraImageAnalyzer.animation(source: source)
        return ProcessedImage(
            image: relativeImage,
            thumbnail: relativeThumbnail,
            width: width,
            height: height,
            fileSize: fileSize,
            colors: colors.isEmpty ? ["#E60023", "#171412", "#FAF8F5"] : colors,
            colorFamilies: profile.families,
            colorTone: profile.tone,
            isAnimated: animation.isAnimated,
            frameCount: animation.frameCount,
            kind: animation.isAnimated ? .image : kind
        )
    }

    /// Regenerates the 640 px grid derivative for an existing pin.
    @discardableResult
    static func writeCardThumbnail(sourcePath: String, root: URL, id: UUID) -> Bool {
        guard let source = CGImageSourceCreateWithURL(
            URL(fileURLWithPath: sourcePath) as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else { return false }
        guard let card = makeThumbnail(from: source, maxPixel: 640) else { return false }
        try? LoraPaths.ensureDirectories(root: root)
        let destination = LoraPaths.cardsDirectory(root: root)
            .appendingPathComponent("\(id.uuidString).jpg")
        return writeJPEG(card, to: destination)
    }

    static func pngData(fromTIFF data: Data) -> Data? {
        guard let bitmap = NSBitmapImageRep(data: data) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func fileExtension(for source: CGImageSource) -> String? {
        guard let type = CGImageSourceGetType(source) else { return nil }
        return UTType(type as String)?.preferredFilenameExtension
    }

    private static func detectKind(source: CGImageSource, fileURL: URL) -> PinKind {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        if let tiff = properties?[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           tiff[kCGImagePropertyTIFFMake] != nil {
            return .image
        }
        if let exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any],
           exif[kCGImagePropertyExifLensModel] != nil {
            return .image
        }
        let name = fileURL.lastPathComponent.lowercased()
        if name.contains("screenshot") || name.contains("screen shot") || name.contains("screencapture") || name.contains("截屏") {
            return .screenshot
        }
        return .screenshot
    }

    private static func makeThumbnail(from source: CGImageSource, maxPixel: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return false
        }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        return CGImageDestinationFinalize(destination)
    }

    private static func extractPalette(from image: CGImage) -> [String] {
        let sampleWidth = 44
        let ratio = CGFloat(image.height) / CGFloat(max(image.width, 1))
        let sampleHeight = max(1, min(44, Int(CGFloat(sampleWidth) * ratio)))
        let bytesPerRow = sampleWidth * 4
        var bytes = [UInt8](repeating: 0, count: sampleHeight * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: sampleWidth,
                height: sampleHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: info
            ) else { return }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
        }

        var buckets: [UInt32: Int] = [:]
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = bytes[index + 3]
            if alpha < 180 { continue }
            let red = UInt32(bytes[index] / 24) * 24
            let green = UInt32(bytes[index + 1] / 24) * 24
            let blue = UInt32(bytes[index + 2] / 24) * 24
            let key = (red << 16) | (green << 8) | blue
            buckets[key, default: 0] += 1
        }

        let ranked = buckets.sorted { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key < rhs.key }
            return lhs.value > rhs.value
        }
        var selected: [UInt32] = []
        for bucket in ranked {
            if selected.count >= 5 { break }
            if selected.contains(where: { colorDistance($0, bucket.key) < 46 }) { continue }
            selected.append(bucket.key)
        }
        if selected.isEmpty {
            return ["#E60023", "#171412", "#FAF8F5"]
        }
        return selected.map(hexString(for:))
    }

    private static func colorDistance(_ lhs: UInt32, _ rhs: UInt32) -> Int {
        let lr = Int((lhs >> 16) & 0xFF), lg = Int((lhs >> 8) & 0xFF), lb = Int(lhs & 0xFF)
        let rr = Int((rhs >> 16) & 0xFF), rg = Int((rhs >> 8) & 0xFF), rb = Int(rhs & 0xFF)
        let dr = lr - rr, dg = lg - rg, db = lb - rb
        return Int(sqrt(Double(dr * dr + dg * dg + db * db)))
    }

    private static func hexString(for color: UInt32) -> String {
        String(format: "#%02X%02X%02X", (color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF)
    }
}