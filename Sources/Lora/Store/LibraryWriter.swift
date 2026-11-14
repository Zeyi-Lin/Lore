import Foundation

/// Serial, debounced `library.json` writer.
///
/// Every edit used to re-encode the entire library and write it atomically on
/// the main actor (15–45 ms per keystroke). Writes now happen on a private
/// queue, coalesced to at most one per debounce window, with stale snapshots
/// skipped by generation.
final class LibraryWriter {
    private let root: URL
    private let fileURL: URL
    private let queue = DispatchQueue(label: "studio.lora.library-writer", qos: .utility)
    private let lock = NSLock()
    private let encoder = LoraJSON.makeEncoder()

    private var latestGeneration: UInt64 = 0
    private var scheduled: DispatchWorkItem?

    /// Called with a message when a background write fails.
    var onError: (@Sendable (String) -> Void)?

    init(root: URL, fileURL: URL) {
        self.root = root
        self.fileURL = fileURL
    }

    func schedule(pins: [Pin], debounce: TimeInterval) {
        lock.lock()
        latestGeneration &+= 1
        let generation = latestGeneration
        scheduled?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.write(snapshot: pins, generation: generation)
        }
        scheduled = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + max(0, debounce), execute: item)
    }

    /// Enqueue a write as soon as possible (still off the main thread).
    func flush(pins: [Pin]) {
        schedule(pins: pins, debounce: 0)
    }

    /// Block until the latest snapshot is on disk. Used on app termination and
    /// when leaving an editing context, bounded so a wedged disk cannot hang quit.
    func flushAndWait(pins: [Pin], timeout: TimeInterval = 2) {
        let semaphore = DispatchSemaphore(value: 0)
        lock.lock()
        latestGeneration &+= 1
        let generation = latestGeneration
        scheduled?.cancel()
        lock.unlock()
        queue.async { [weak self] in
            self?.write(snapshot: pins, generation: generation)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout)
    }

    private func write(snapshot pins: [Pin], generation: UInt64) {
        lock.lock()
        let isLatest = generation == latestGeneration
        lock.unlock()
        guard isLatest else { return }

        let state = Perf.begin("library.write")
        defer { Perf.end("library.write", state) }
        do {
            try LoraPaths.ensureDirectories(root: root)
            let library = LoraLibrary(version: 1, pins: pins)
            let data = try encoder.encode(library)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            onError?(error.localizedDescription)
        }
    }
}
