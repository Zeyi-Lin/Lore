import CoreGraphics
import Foundation

/// Turns a stream of scroll-wheel or trackpad deltas into at most one pin step
/// per gesture. A trackpad flick fires dozens of events and a wheel notch can
/// fire several; without accumulating them the detail view would fly through
/// half the library on one scroll.
final class ScrollNavigationAccumulator {
    private var accumulated: CGFloat = 0
    private var lastStep: Date = .distantPast

    /// - Returns: `-1` for the previous pin, `1` for the next pin, or `nil`
    ///   while the gesture is still below the threshold (or cooling down).
    func step(deltaY: CGFloat, precise: Bool, at date: Date = Date()) -> Int? {
        guard abs(deltaY) > 0.0001 else { return nil }
        // A trackpad gesture needs to settle before it can step again; a mouse
        // wheel is already discrete, so rapid notches should each move a pin.
        let cooldown: TimeInterval = precise ? 0.45 : 0.05
        guard date.timeIntervalSince(lastStep) >= cooldown else { return nil }
        accumulated += deltaY
        // Trackpads report pixel deltas; a traditional wheel reports coarse
        // line deltas that are already one notch per event.
        let threshold: CGFloat = precise ? 36 : 0.9
        guard abs(accumulated) >= threshold else { return nil }
        // Positive deltaY scrolls up, which should reveal the previous pin.
        let direction = accumulated > 0 ? -1 : 1
        accumulated = 0
        lastStep = date
        return direction
    }

    func reset() {
        accumulated = 0
    }
}
