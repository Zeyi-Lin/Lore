import Foundation
import AppKit
import CoreGraphics

/// Validation and rasterisation for SVG pins.
///
/// AppKit has decoded SVG through `NSImage` (`_NSSVGImageRep`) since macOS 14,
/// which is the app's deployment target, so vector references need neither a
/// WebKit dependency nor a third-party parser. Everything here is pure drawing:
/// it is safe to call from a background queue, which is where both the importer
/// and `ImageLoader` rasterise.
public enum SVGRasterizer {
    /// Longest side used when the caller does not ask for a size. The large
    /// image mode has no natural pixel size for a vector, so it gets a render
    /// that stays crisp on a Retina display at 100%.
    public static let defaultRenderPixel = 2048
    /// Guard rail for doctored width/height attributes.
    public static let maxRenderPixel = 8192
    /// Largest markup document accepted from a file or the clipboard.
    public static let maxDocumentBytes = 8 * 1024 * 1024

    public enum Failure: Error, LocalizedError {
        case empty
        case tooLarge
        case notMarkup
        case renderFailed

        public var errorDescription: String? {
            switch self {
            case .empty: return "The SVG markup is empty."
            case .tooLarge: return "The SVG markup is larger than \(SVGRasterizer.maxDocumentBytes / (1024 * 1024)) MB."
            case .notMarkup: return "The text is not an <svg> document."
            case .renderFailed: return "The SVG could not be rendered."
            }
        }
    }

    // MARK: - Detection

    /// True when `data` holds an SVG document rather than just any text.
    ///
    /// Used by the Agent API, where the bytes may arrive with no filename: the
    /// check deliberately looks at the markup itself, not at a file extension.
    public static func isSVG(data: Data) -> Bool {
        // Cheap gate before validating the whole payload: every SVG document
        // opens with `<` (possibly after a BOM or whitespace), so a PNG or JPEG
        // never pays for a UTF-8 scan.
        guard startsWithMarkup(data), let text = decodeText(data) else { return false }
        return normalizedMarkup(text) != nil
    }

    private static func startsWithMarkup(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(128))
        guard !bytes.isEmpty else { return false }
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) { return true }
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0xEF, index + 2 < bytes.count, bytes[index + 1] == 0xBB, bytes[index + 2] == 0xBF {
                index += 3
                continue
            }
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                index += 1
                continue
            }
            return byte == 0x3C // "<"
        }
        return false
    }

    /// True for a path whose extension is `.svg`, independent of its contents.
    public static func isSVGFile(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare("svg") == .orderedSame
    }

    /// Normalises pasted SVG code, or returns nil when the text is not a
    /// standalone document. HTML pages that merely *contain* an inline `<svg>`
    /// are rejected: the root element has to be `<svg>`.
    public static func normalizedMarkup(_ text: String) -> String? {
        var rest = text
        if rest.hasPrefix("\u{FEFF}") { rest.removeFirst() }
        rest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty else { return nil }
        guard rest.utf8.count <= maxDocumentBytes else { return nil }

        // Skip the prolog: XML declaration, processing instructions, comments
        // and a doctype (which may carry an internal subset) are all legal
        // before the root element.
        var didStrip = true
        while didStrip {
            didStrip = false
            if rest.hasPrefix("<?") {
                guard let end = rest.range(of: "?>") else { return nil }
                rest = rest[end.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                didStrip = true
            } else if rest.hasPrefix("<!--") {
                guard let end = rest.range(of: "-->") else { return nil }
                rest = rest[end.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                didStrip = true
            } else if rest.lowercased().hasPrefix("<!doctype") {
                guard let end = endOfDoctype(in: rest) else { return nil }
                rest = rest[end...].trimmingCharacters(in: .whitespacesAndNewlines)
                didStrip = true
            }
        }

        let lower = rest.lowercased()
        guard lower.hasPrefix("<svg"), lower.contains("</svg") || lower.hasSuffix("/>") else {
            return nil
        }
        return rest
    }

    /// Index just past a `<!DOCTYPE …>` declaration, tolerating an internal
    /// subset (`[ … ]`) whose `>` characters do not end the declaration.
    private static func endOfDoctype(in text: String) -> String.Index? {
        var depth = 0
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "[" {
                depth += 1
            } else if character == "]" {
                depth = max(0, depth - 1)
            } else if character == ">" && depth == 0 {
                return text.index(after: index)
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func decodeText(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        // Older exports occasionally declare a single-byte encoding; Latin-1
        // decodes every byte, and the markup check below still has to pass.
        return String(data: data, encoding: .isoLatin1)
    }

    // MARK: - Geometry

    /// The document's intrinsic size in points, as AppKit resolves it from
    /// `width`/`height` (units are converted) or the `viewBox`.
    public static func intrinsicSize(data: Data) -> CGSize? {
        guard isSVG(data: data), let image = NSImage(data: data) else { return nil }
        return sanitized(image.size)
    }

    // MARK: - Rasterisation

    /// Renders `data` so its longest side is `maxPixel` wide.
    ///
    /// `background` composites the artwork onto an opaque fill, which is what
    /// the JPEG thumbnails need; the detail view passes nil so a transparent
    /// vector lands on the card's paper mat instead of a hard white box.
    public static func rasterize(
        data: Data,
        maxPixel: Int,
        background: CGColor? = nil
    ) throws -> CGImage {
        guard !data.isEmpty else { throw Failure.empty }
        guard data.count <= maxDocumentBytes else { throw Failure.tooLarge }
        guard let text = decodeText(data), normalizedMarkup(text) != nil else {
            throw Failure.notMarkup
        }
        guard let image = NSImage(data: data) else { throw Failure.renderFailed }
        guard let intrinsic = sanitized(image.size) else { throw Failure.renderFailed }

        let requested = maxPixel > 0 ? min(maxPixel, maxRenderPixel) : defaultRenderPixel
        let scale = CGFloat(requested) / max(intrinsic.width, intrinsic.height)
        let width = max(1, min(maxRenderPixel, Int((intrinsic.width * scale).rounded())))
        let height = max(1, min(maxRenderPixel, Int((intrinsic.height * scale).rounded())))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
            throw Failure.renderFailed
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        if let background {
            context.cgContext.setFillColor(background)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        image.draw(
            in: NSRect(x: 0, y: 0, width: width, height: height),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let rendered = rep.cgImage else { throw Failure.renderFailed }
        return rendered
    }

    /// Convenience overload for a stored `.svg` file.
    public static func rasterize(fileURL: URL, maxPixel: Int, background: CGColor? = nil) -> CGImage? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? rasterize(data: data, maxPixel: maxPixel, background: background)
    }

    /// AppKit resolves unitless sizes to points and percentages to the viewBox;
    /// a document with neither can still report a degenerate size. Callers fall
    /// back to the raster's own dimensions when this returns nil.
    private static func sanitized(_ size: CGSize) -> CGSize? {
        let width = size.width
        let height = size.height
        guard width.isFinite, height.isFinite, width > 0.01, height > 0.01 else { return nil }
        guard width < 1_000_000, height < 1_000_000 else { return nil }
        return CGSize(width: width, height: height)
    }
}
