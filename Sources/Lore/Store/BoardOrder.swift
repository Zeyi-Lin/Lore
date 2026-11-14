import Foundation
import os

/// Sidebar display order for the board tree.
///
/// `library.json` deliberately stays untouched: the board of a pin is still
/// just its `board` string, and the Agent API keeps seeing the same data. This
/// sidecar only decides how those boards are *ordered* in the sidebar, so an
/// older build — or an Agent writing pins — cannot corrupt it.
///
/// Keys are lowercased board paths (`BoardPath.key`), the same ids `BoardNode`
/// uses; `""` is the root level. Casing and spelling always come from the
/// pins, so an order entry for a renamed board is simply ignored.
struct BoardOrder: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    /// Parent path key (`""` = root) -> ordered child path keys.
    var order: [String: [String]]

    init(version: Int = BoardOrder.currentVersion, order: [String: [String]] = [:]) {
        self.version = version
        self.order = order
    }

    func children(of parent: String) -> [String]? {
        order[parent]
    }

    /// Moves `key` before/after `target` among `current` (the siblings in their
    /// displayed order) and stores the result. Returns false when nothing
    /// moved.
    mutating func move(
        _ key: String,
        in parent: String,
        relativeTo target: String,
        after: Bool,
        current: [String]
    ) -> Bool {
        guard key != target else { return false }
        var list = current
        guard let from = list.firstIndex(of: key) else { return false }
        list.remove(at: from)
        guard let to = list.firstIndex(of: target) else { return false }
        list.insert(key, at: after ? to + 1 : to)
        guard order[parent] != list else { return false }
        order[parent] = list
        return true
    }

    /// Keeps a renamed board (and everything nested under it) at the same
    /// place. `old` and `new` are path keys, e.g. `linear/settings` ->
    /// `linear/preferences`.
    mutating func remap(old: String, new: String) {
        guard old != new else { return }
        var updated: [String: [String]] = [:]
        for (parent, children) in order {
            let key = Self.reparent(parent, old: old, new: new)
            let mapped = children.map { Self.reparent($0, old: old, new: new) }
            updated[key] = mapped
        }
        order = updated
    }

    /// Drops a deleted board (and its subtree) from the order.
    mutating func removeSubtree(_ key: String) {
        guard !key.isEmpty else { return }
        var updated: [String: [String]] = [:]
        for (parent, children) in order where !Self.isWithin(parent, key) {
            updated[parent] = children.filter { !Self.isWithin($0, key) }
        }
        order = updated
    }

    private static func isWithin(_ candidate: String, _ key: String) -> Bool {
        candidate == key || candidate.hasPrefix(key + "/")
    }

    private static func reparent(_ candidate: String, old: String, new: String) -> String {
        guard candidate == old || candidate.hasPrefix(old + "/") else { return candidate }
        return new + candidate.dropFirst(old.count)
    }
}

/// Reads and writes `<library>/boards.json`. Missing or stale files fall back
/// to the default ordering, so a library never fails to open because of it.
enum BoardOrderFile {
    private static let log = Logger(subsystem: "studio.lore.library", category: "board-order")

    static func url(root: URL) -> URL {
        root.appendingPathComponent("boards.json")
    }

    static func load(root: URL) -> BoardOrder {
        let fileURL = url(root: root)
        guard let data = try? Data(contentsOf: fileURL) else { return BoardOrder() }
        guard let order = try? JSONDecoder().decode(BoardOrder.self, from: data) else {
            log.error("boards.json is unreadable; falling back to the default order")
            return BoardOrder()
        }
        return BoardOrder(version: order.version, order: order.order)
    }

    static func save(_ order: BoardOrder, root: URL) {
        let fileURL = url(root: root)
        do {
            let data = try JSONEncoder().encode(order)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("couldn't save boards.json: \(error.localizedDescription, privacy: .public)")
        }
    }
}
