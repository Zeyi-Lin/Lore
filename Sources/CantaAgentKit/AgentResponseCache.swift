import Foundation

/// Small LRU of encoded GET responses keyed by request target and the
/// library.json stat stamp. Avoids re-reading, re-decoding, re-sorting and
/// re-encoding the whole library for every poll from an agent.
final class AgentResponseCache: @unchecked Sendable {
    private let lock = NSLock()
    private var stamp: LibraryFileStamp?
    private var entries: [String: HTTPResponse] = [:]
    private var order: [String] = []
    private var totalBytes = 0
    private let maxBytes = 16 * 1024 * 1024
    private let maxEntries = 64

    func response(for key: String, stamp newStamp: LibraryFileStamp) -> HTTPResponse? {
        lock.lock()
        defer { lock.unlock() }
        if stamp != newStamp {
            stamp = newStamp
            entries.removeAll(keepingCapacity: true)
            order.removeAll(keepingCapacity: true)
            totalBytes = 0
            return nil
        }
        return entries[key]
    }

    func store(_ response: HTTPResponse, for key: String, stamp newStamp: LibraryFileStamp) {
        lock.lock()
        defer { lock.unlock() }
        if stamp != newStamp {
            stamp = newStamp
            entries.removeAll(keepingCapacity: true)
            order.removeAll(keepingCapacity: true)
            totalBytes = 0
        }
        guard response.body.count <= maxBytes else { return }

        if let old = entries[key] {
            totalBytes -= old.body.count
            order.removeAll { $0 == key }
        }
        while (entries.count >= maxEntries || totalBytes + response.body.count > maxBytes),
              let oldest = order.first {
            order.removeFirst()
            if let removed = entries.removeValue(forKey: oldest) {
                totalBytes -= removed.body.count
            }
        }
        entries[key] = response
        order.append(key)
        totalBytes += response.body.count
    }
}
