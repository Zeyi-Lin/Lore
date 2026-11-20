import Foundation
import os

/// A board's chosen sidebar logo. Both cases keep their data inside the
/// library sidecar instead of `library.json`: a logo is presentation, and the
/// Agent API should not have to know about it.
///
/// - `.pin` points at an inspiration (no copy is made; the pin's derived
///   thumbnails are shown, and deleting the pin falls back to the default).
/// - `.image` is a relative path under the library root. Uploaded logos are
///   normalised into `Logos/` and never shared with a pin's original.
struct BoardLogo: Codable, Equatable, Sendable {
    var pinID: UUID?
    var image: String?

    static func pin(_ id: UUID) -> BoardLogo {
        BoardLogo(pinID: id, image: nil)
    }

    static func image(_ path: String) -> BoardLogo {
        BoardLogo(pinID: nil, image: path)
    }

}

/// Sidebar display order for the board tree, the boards the user created
/// explicitly, and the logo chosen for each board.
///
/// `library.json` deliberately stays untouched: the board of a pin is still
/// just its `board` string, and the Agent API keeps seeing the same data. This
/// sidecar only decides how those boards are *ordered* in the sidebar — and,
/// since v1.2.2, remembers boards that hold no pins yet, because an empty board
/// has no other home: `library.json` only knows the boards pins point at.
/// Since format v3 it also remembers a per-board logo.
///
/// Keys are lowercased board paths (`BoardPath.key`), the same ids `BoardNode`
/// uses; `""` is the root level. Casing and spelling come from the pins, or
/// from `declared` for a board no pin uses yet.
struct BoardOrder: Codable, Equatable, Sendable {
    static let currentVersion = 3

    var version: Int
    /// Parent path key (`""` = root) -> ordered child path keys.
    var order: [String: [String]]
    /// Board paths the user created, in creation order. A declared board that
    /// later gets pins stays declared (it just stops being empty), so deleting
    /// it in one release and re-adding it later keeps working the same way.
    var declared: [String]
    /// Lowercased board path -> chosen logo. A missing entry means "use the
    /// board's first image", which is the default; no entry is written for
    /// that, so old libraries and default boards stay untouched.
    var logos: [String: BoardLogo]

    init(
        version: Int = BoardOrder.currentVersion,
        order: [String: [String]] = [:],
        declared: [String] = [],
        logos: [String: BoardLogo] = [:]
    ) {
        self.version = version
        self.order = order
        self.declared = declared
        self.logos = logos
    }

    private enum CodingKeys: String, CodingKey {
        case version, order, declared, logos
    }

    /// v1 files predate `declared`, v2 predates `logos`; they must keep opening.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        order = try container.decodeIfPresent([String: [String]].self, forKey: .order) ?? [:]
        declared = try container.decodeIfPresent([String].self, forKey: .declared) ?? []
        logos = try container.decodeIfPresent([String: BoardLogo].self, forKey: .logos) ?? [:]
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

    /// Keeps a renamed board's logo (and the logos of everything nested under
    /// it) attached to the new path. When the destination already has a logo —
    /// a rename onto an existing board merges the two — the destination wins;
    /// the abandoned custom image is removed by `LibraryStore`.
    mutating func remapLogos(old: String, new: String) {
        guard old != new else { return }
        var moves: [(String, BoardLogo)] = []
        for key in logos.keys where Self.isWithin(key, old) {
            guard let logo = logos[key] else { continue }
            moves.append((new + key.dropFirst(old.count), logo))
        }
        for key in logos.keys where Self.isWithin(key, old) {
            logos.removeValue(forKey: key)
        }
        for (key, logo) in moves where logos[key] == nil {
            logos[key] = logo
        }
    }

    /// Drops a deleted board (and its subtree) from the order, the declared
    /// list, and the logo map.
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
        logos = logos.filter { !Self.isWithin($0.key, key) }
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
            // Normalise the on-disk version: an old file that just gained a
            // logo should not keep claiming the format it was read from.
            var stored = order
            stored.version = BoardOrder.currentVersion
            let data = try JSONEncoder().encode(stored)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("couldn't save boards.json: \(error.localizedDescription, privacy: .public)")
        }
    }
}
