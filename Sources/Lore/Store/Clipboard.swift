import AppKit

/// Clipboard inspection shared by the paste buttons, the app menu, and the ⌘V
/// shortcut. Keeping the image-type list in one place means the importer, the
/// shortcut guard, and the empty-state copy cannot disagree about whether a
/// paste is possible.
enum Clipboard {
    static let gifTypes: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType("com.compuserve.gif"),
        NSPasteboard.PasteboardType("public.gif")
    ]

    static func isLikelyImage(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "webp", "gif", "bmp"]
            .contains(url.pathExtension.lowercased())
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
        if gifTypes.contains(where: { types.contains($0) }) { return true }
        return types.contains(.png)
            || types.contains(.tiff)
            || types.contains(NSPasteboard.PasteboardType("public.jpeg"))
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
