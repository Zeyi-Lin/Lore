import AppKit
import SwiftUI

/// One of the islands where the window can be moved from.
///
/// The app turns off AppKit's own window dragging (`isMovable = false`,
/// `isMovableByWindowBackground = false`), so the window only moves from the
/// explicit grips. Dragging starts on the first mouse-move after the press — no
/// hold delay, no cursor change — so the window tracks the pointer one to one.
/// Double-clicking a grip still zooms, like the old title-bar gesture.
final class WindowGripView: NSView {
    private var isDragging = false
    /// Pointer and window position captured on press; every drag event is
    /// resolved from these, which keeps the motion absolute and jitter free.
    private var pointerStart: NSPoint = .zero
    private var originStart: NSPoint = .zero

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        if event.clickCount == 2 {
            // Outside the tracking loop: resizing the window from inside a
            // mouse-down can re-enter AppKit's constraint pass.
            DispatchQueue.main.async { [weak self] in
                WindowZoom.toggle(for: self?.window)
            }
            return
        }
        guard let window else { return }
        isDragging = true
        originStart = window.frame.origin
        pointerStart = NSPoint(
            x: originStart.x + event.locationInWindow.x,
            y: originStart.y + event.locationInWindow.y
        )
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let window else { return }
        let current = window.frame
        // Screen position of the pointer: the event is window-relative, so
        // adding the *current* origin gives an absolute point even while the
        // window is moving under the cursor.
        let pointer = NSPoint(
            x: current.origin.x + event.locationInWindow.x,
            y: current.origin.y + event.locationInWindow.y
        )
        var target = current
        target.origin = NSPoint(
            x: originStart.x + (pointer.x - pointerStart.x),
            y: originStart.y + (pointer.y - pointerStart.y)
        )
        // Sub-pixel moves would still cost a window update; skip them.
        guard abs(target.origin.x - current.origin.x) >= 0.5
            || abs(target.origin.y - current.origin.y) >= 0.5 else { return }
        // No synchronous redraw per drag event: moving a window does not change
        // its contents, and this keeps the move off the drawing path.
        window.setFrame(target, display: false)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }
}

struct WindowGrip: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowGripView {
        WindowGripView()
    }

    func updateNSView(_ nsView: WindowGripView, context: Context) {}
}
