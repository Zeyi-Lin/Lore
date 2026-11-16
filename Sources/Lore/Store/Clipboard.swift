import AppKit
import UniformTypeIdentifiers
import LoreAgentKit

/// Clipboard inspection shared by the paste buttons, the app menu, and the ⌘V
/// shortcut. Keeping the image-type list in one place means the importer, the
/// shortcut guard, and the empty-state copy cannot disagree about whether a
/// paste is possible.
enum Clipboard {
    static let gifTypes: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType("com.compuserve.gif"),
        NSPasteboard.PasteboardType("public.gif")
    ]

    /// `public.svg-image`: set by Finder for an SVG file copy and by browsers
    /// and design tools that put the markup on the pasteboard directly.
    static let svgType = NSPasteboard.PasteboardType(UTType.svg.identifier)

    static func isLikelyImage(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "webp", "gif", "bmp", "svg"]
            .contains(url.pathExtension.lowercased())
    }

    /// The SVG markup on the pasteboard, or nil. Copying code from a text
    /// editor puts a plain string on the clipboard, so the text itself is
    /// checked for a standalone `<svg>` document; HTML pages that merely embed
    /// one are rejected by `SVGRasterizer`.
    static func svgCode(from pasteboard: NSPasteboard = .general) -> String? {
        if let data = pasteboard.data(forType: svgType) {
            if let text = String(data: data, encoding: .utf8),
               let markup = SVGRasterizer.normalizedMarkup(text) {
                return markup
            }
        }
        guard let text = pasteboard.string(forType: .string),
              text.utf8.count <= SVGRasterizer.maxDocumentBytes else { return nil }
        return SVGRasterizer.normalizedMarkup(text)
    }

    /// True when a paste would import something. Only inspects pasteboard types
    /// and file URLs, so ⌘V can decide whether to consume the event without
    /// decoding a large bitmap.
    static func containsImage(_ pasteboard: NSPasteboard = .general) -> Bool {
        if let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) {
            let urls = objects.compactMap { ($0 as? NSURL) as URL? }
            if urls.contains(where: isLikelyImage) { return true }
        }

        let types = Set(pasteboard.types ?? [])
        if types.contains(svgType), svgCode(from: pasteboard) != nil { return true }
        if gifTypes.contains(where: { types.contains($0) }) { return true }
        if types.contains(.png)
            || types.contains(.tiff)
            || types.contains(NSPasteboard.PasteboardType("public.jpeg")) {
            return true
        }
        // Copied markup is text: no image type is advertised, but ⌘V should
        // still pin it. The check is intentionally strict about the root
        // element so a copied paragraph is never mistaken for a vector.
        return svgCode(from: pasteboard) != nil
    }

    /// ⌘V exactly: ⇧⌘V still belongs to the app-menu command, and ⌘⌥V is not a
    /// paste gesture.
    static func isPasteShortcut(_ event: NSEvent) -> Bool {
        guard event.keyCode == 9 else { return false } // kVK_ANSI_V
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        return modifiers == .command
    }

    /// Text fields and editors keep the standard paste behavior; importing a
    /// screenshot must never steal ⌘V from the search field or a note editor.
    static func isTextInputFocused(_ window: NSWindow? = NSApp.keyWindow) -> Bool {
        guard let responder = window?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }
}
