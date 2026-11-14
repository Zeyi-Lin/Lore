import SwiftUI
import AppKit

/// Plays an animated GIF with AppKit's image view, which understands GIF frame
/// timing and disposal natively. The view is deliberately non-interactive so
/// SwiftUI taps, double-clicks, and pans on the parent keep working.
struct AnimatedGIFView: NSViewRepresentable {
    var paths: [String]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AnimatedGIFNSView {
        let view = AnimatedGIFNSView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        view.imageFrameStyle = .none
        view.animates = true
        view.alphaValue = 0
        context.coordinator.load(paths: paths, into: view)
        return view
    }

    func updateNSView(_ nsView: AnimatedGIFNSView, context: Context) {
        context.coordinator.load(paths: paths, into: nsView)
    }

    static func dismantleNSView(_ nsView: AnimatedGIFNSView, coordinator: Coordinator) {
        coordinator.cancel()
        nsView.animates = false
        nsView.image = nil
    }

    final class Coordinator {
        private var key = ""
        private var task: Task<Void, Never>?

        func load(paths: [String], into view: AnimatedGIFNSView) {
            let nextKey = paths.joined(separator: "|")
            guard nextKey != key else { return }
            key = nextKey
            task?.cancel()
            view.animates = false
            view.image = nil
            view.alphaValue = 0

            guard let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
                return
            }

            task = Task { [weak self, weak view] in
                let image = await Task.detached(priority: .userInitiated) {
                    NSImage(contentsOfFile: path)
                }.value
                guard !Task.isCancelled,
                      let self,
                      let view,
                      self.key == nextKey,
                      let image else {
                    return
                }
                await MainActor.run {
                    guard self.key == nextKey else { return }
                    view.image = image
                    view.animates = true
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.16
                        view.animator().alphaValue = 1
                    }
                }
            }
        }

        func cancel() {
            task?.cancel()
            task = nil
            key = ""
        }
    }
}

/// `hitTest` returns nil so the animated image never steals mouse events from
/// the SwiftUI card, detail image, or large-image viewer.
final class AnimatedGIFNSView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
