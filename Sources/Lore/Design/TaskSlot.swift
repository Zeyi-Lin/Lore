import Foundation

/// A debounced task slot that does not invalidate the owning view when it is
/// replaced. Assigning a `@State` task on every resize event would re-run the
/// body for every pixel, which is exactly the cost this is meant to avoid.
final class TaskSlot {
    /// True from the moment a task is scheduled until it fires. While it is
    /// true the window is moving continuously (a drag or a zoom animation), so
    /// the gallery coarsens its layout grid instead of relaying out per pixel.
    private(set) var pending = false

    private var task: Task<Void, Never>?

    func schedule(delay: UInt64, _ work: @escaping @MainActor () -> Void) {
        task?.cancel()
        pending = true
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            pending = false
            work()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        pending = false
    }
}
