import Foundation
import os

/// Sidebar display order for the board tree, plus the boards the user created
/// explicitly.
///
/// `library.json` deliberately stays untouched: the board of a pin is still
/// just its `board` string, and the Agent API keeps seeing the same data. This
/// sidecar only decides how those boards are *ordered* in the sidebar — and,
/// since v1.2.2, remembers boards that hold no pins yet, because an empty board
/// has no other home: `library.json` only knows the boards pins point at.
///
/// Keys are lowercased board paths (`BoardPath.key`), the same ids `BoardNode`
/// uses; `""` is the root level. Casing and spelling come from the pins, or
/// from `declared` for a board no pin uses yet.
struct BoardOrder: Codable, Equatable, Sendable {
    static let currentVersion = 2

    var version: Int
    /// Parent path key (`""` = root) -> ordered child path keys.
    var order: [String: [String]]
    /// Board paths the user created, in creation order. A declared board that
    /// later gets pins stays declared (it just stops being empty), so deleting
    /// it in one release and re-adding it later keeps working the same way.
    var declared: [String]

    init(
        version: Int = BoardOrder.currentVersion,
        order: [String: [String]] = [:],
        declared: [String] = []
    ) {
        self.version = version
        self.order = order
        self.declared = declared
    }

    private enum CodingKeys: String, CodingKey {
        case version, order, declared
    }

    /// v1 files predate `declared`; they must keep opening.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        order = try container.decodeIfPresent([String: [String]].self, forKey: .order) ?? [:]
        declared = try container.decodeIfPresent([String].self, forKey: .declared) ?? []
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

    /// Renames declared boards with the casing the user typed. `order` keys are
    /// lowercased, but the declared list keeps the spelling of the board, so it
    /// is matched case-insensitively and rewritten with `new`.
    mutating func remapDeclared(old: [String], new: [String]) {
        guard !old.isEmpty else { return }
        declared = declared.compactMap { entry in
            let parts = BoardPath.segments(entry)
            guard parts.count >= old.count, BoardPath.segmentsHasPrefix(parts, old) else {
                return entry
            }
            return (new + parts.dropFirst(old.count)).joined(separator: "/")
        }
    }

    /// Drops a deleted board (and its subtree) from the order and from the
    /// declared list.
    mutating func removeSubtree(_ key: String) {
        guard !key.isEmpty else { return }
        var updated: [String: [String]] = [:]
        for (parent, children) in order where !Self.isWithin(parent, key) {
            updated[parent] = children.filter { !Self.isWithin($0, key) }
        }
        order = updated
        // Declared boards keep their display casing, so compare by key.
        declared.removeAll { entry in
            let entryKey = BoardPath.key(entry)
            return entryKey == key || entryKey.hasPrefix(key + "/")
        }
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
        return order
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
