import AppKit

/// Double-click zoom/restore for the main window chrome. Unlike native
/// full-screen mode this keeps the menu bar and Dock accessible while filling
/// the screen's visible frame, and restores the exact previous frame.
@MainActor
enum WindowZoom {
    private static var savedFrames: [Int: NSRect] = [:]

    static var isEditingText: Bool {
        let responder = NSApp.keyWindow?.firstResponder
        return responder is NSTextView || responder is NSTextField
    }

    static func toggle() {
        guard let window = NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain })
        else { return }
        guard !window.styleMask.contains(.fullScreen) else {
            window.toggleFullScreen(nil)
            return
        }

        let key = window.windowNumber
        if let saved = savedFrames.removeValue(forKey: key) {
            apply(saved, to: window)
            return
        }

        guard let screen = window.screen ?? NSScreen.main else { return }
        savedFrames[key] = window.frame
        apply(screen.visibleFrame, to: window)
    }

    private static func apply(_ frame: NSRect, to window: NSWindow) {
        // Snap rather than animate: a live window-frame animation can leave the
        // SwiftUI hosting view mid-reflow (especially on Retina displays).
        window.setFrame(frame, display: true, animate: false)
        window.contentView?.needsLayout = true
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }
}