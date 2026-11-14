import AppKit
import SwiftUI

/// Double-click zoom/restore for the main window chrome. Unlike native
/// full-screen mode this keeps the menu bar and Dock accessible while filling
/// the screen's visible frame, and restores the exact previous frame.
///
/// The resize goes through AppKit's animated `setFrame`, which runs the whole
/// transition on the main thread: SwiftUI lays the gallery out at every
/// intermediate width, and no later pass can land on a half-resized window.
/// Stepping frames from a display link, or animating with `NSAnimationContext`,
/// made SwiftUI's hosting view re-enter its constraint pass during a resize and
/// throw.
@MainActor
enum WindowZoom {
    private static var savedFrames: [Int: NSRect] = [:]

    static func toggle(for window: NSWindow? = nil) {
        guard let window = window ?? targetWindow() else { return }

        guard !window.styleMask.contains(.fullScreen) else {
            window.toggleFullScreen(nil)
            return
        }
        guard window.isVisible, !window.isMiniaturized else { return }

        let key = window.windowNumber
        let target: NSRect
        if let saved = savedFrames.removeValue(forKey: key) {
            target = saved
        } else {
            guard let screen = window.screen ?? NSScreen.main else { return }
            savedFrames[key] = window.frame
            target = screen.visibleFrame
        }
        guard window.frame != target else { return }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            land(on: target, in: window)
        } else {
            window.setFrame(target, display: true, animate: true)
            land(on: target, in: window)
        }
    }

    /// Snap to the exact frame and force one full layout pass, so the gallery's
    /// column count matches the new width as soon as the zoom settles.
    private static func land(on frame: NSRect, in window: NSWindow) {
        window.setFrame(frame, display: true)
        window.contentView?.needsLayout = true
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    private static func targetWindow() -> NSWindow? {
        if let key = NSApp.keyWindow, key.canBecomeMain { return key }
        return NSApp.mainWindow
            ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
    }
}
