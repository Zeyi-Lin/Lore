import Foundation

/// Board names double as paths: `Linear/Settings` is the `Settings` board
/// nested inside the `Linear` group. The slash is a naming convention only —
/// the stored board string is still the exact match used by filtering and the
/// API — but the sidebar folds boards that share a leading segment into one
/// collapsible group.
enum BoardPath {
    static let separator: Character = "/"

    /// Trimmed, non-empty segments of a board name.
    static func segments(_ raw: String) -> [String] {
        raw
            .split(separator: separator, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Segments re-joined without stray whitespace: `" Linear / Settings "`
    /// becomes `"Linear/Settings"`.
    static func canonicalName(_ raw: String) -> String {
        let parts = segments(raw)
        guard !parts.isEmpty else { return raw.trimmingCharacters(in: .whitespacesAndNewlines) }
        return parts.joined(separator: String(separator))
    }

    static func key(_ raw: String) -> String {
        canonicalName(raw).lowercased()
    }

    /// Keys of every group above this board, outermost first. Selecting
    /// `Linear/Settings` reveals `linear` in the sidebar.
    static func ancestorKeys(_ raw: String) -> [String] {
        let parts = segments(raw)
        guard parts.count > 1 else { return [] }
        return (1..<parts.count).map { depth in
            parts.prefix(depth).joined(separator: String(separator)).lowercased()
        }
    }

    /// True when `parts` starts with `prefix`, compared case-insensitively.
    static func segmentsHasPrefix(_ parts: [String], _ prefix: [String]) -> Bool {
        guard prefix.count <= parts.count else { return false }
        return zip(prefix, parts).allSatisfy { $0.caseInsensitiveCompare($1) == .orderedSame }
    }

    /// True when `raw` sits strictly below `parent` in the `/` hierarchy.
    static func isDescendant(_ raw: String, of parent: String) -> Bool {
        let parts = segments(raw)
        let parentParts = segments(parent)
        guard parts.count > parentParts.count else { return false }
        return segmentsHasPrefix(parts, parentParts)
    }

    /// Rewrites a board path when it sits on or under `old`, keeping every
    /// descendant segment. Returns nil for unrelated paths.
    static func replacingPrefix(in raw: String, old: [String], new: [String]) -> String? {
        let parts = segments(raw)
        guard segmentsHasPrefix(parts, old) else { return nil }
        let suffix = Array(parts.dropFirst(old.count))
        return (new + suffix).joined(separator: String(separator))
    }
}

/// One row of the sidebar's board tree: either a real board, a group that only
/// exists because its children share a prefix, or a board that is also a group.
struct BoardNode: Identifiable, Hashable {
    /// Path components with their original casing, e.g. `["Linear", "Settings"]`.
    let segments: [String]
    /// The literal `board` string as stored on pins, when this path is itself a
    /// board. `nil` for pure prefix groups.
    let boardName: String?
    /// Pins on exactly this board (0 for pure groups).
    let count: Int
    /// Pins on this board plus every descendant board.
    let totalCount: Int
    var children: [BoardNode]

    /// Full path, used for ids and tooltips.
    var fullName: String { segments.joined(separator: String(BoardPath.separator)) }
    var id: String { BoardPath.key(fullName) }
    var isBoard: Bool { boardName != nil }
    /// Label for this row: the last path component.
    var title: String { segments.last ?? boardName ?? "" }
}

enum BoardDefaults {
    /// Boards the app ships with, kept in this order at the top of the sidebar.
    static let suggested = ["Web dashboards", "Mobile flows", "Landing pages", "Editorial", "Unsorted"]
}

enum BoardTreeBuilder {
    /// Folds flat board names into a prefix tree, preserving the sidebar's
    /// familiar ordering: suggested boards first, then alphabetical groups.
    static func build(
        boardCounts: [String: Int],
        preferredOrder: [String] = BoardDefaults.suggested
    ) -> [BoardNode] {
        final class Node {
            var name: String
            var boardName: String?
            var count = 0
            var children: [String: Node] = [:]

            init(name: String) {
                self.name = name
            }
        }

        let root = Node(name: "")
        for (board, count) in boardCounts {
            let parts = BoardPath.segments(board)
            guard !parts.isEmpty else { continue }
            var current = root
            for part in parts {
                let key = part.lowercased()
                if let existing = current.children[key] {
                    current = existing
                } else {
                    let child = Node(name: part)
                    current.children[key] = child
                    current = child
                }
            }
            // Two spellings of the same board (case or whitespace) collapse
            // into one row; their counts add up.
            current.count += count
            if current.boardName == nil {
                // Keep the literal board string: selection, filtering, and the
                // representative lookup all match the stored value, not the
                // tidied path.
                current.boardName = board.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let preferredIndex = Dictionary(
            preferredOrder.enumerated().map { ($0.element.lowercased(), $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )

        func orderedChildren(of node: Node, isRoot: Bool) -> [Node] {
            node.children.keys
                .compactMap { node.children[$0] }
                .sorted { lhs, rhs in
                    if isRoot {
                        let leftRank = preferredIndex[lhs.name.lowercased()] ?? Int.max
                        let rightRank = preferredIndex[rhs.name.lowercased()] ?? Int.max
                        if leftRank != rightRank { return leftRank < rightRank }
                    }
                    return lhs.name.lowercased() < rhs.name.lowercased()
                }
        }

        func build(_ node: Node, path: [String]) -> BoardNode? {
            let childNodes = orderedChildren(of: node, isRoot: false).compactMap { child in
                build(child, path: path + [child.name])
            }
            let childTotal = childNodes.reduce(0) { $0 + $1.totalCount }
            guard node.boardName != nil || !childNodes.isEmpty else { return nil }
            return BoardNode(
                segments: path,
                boardName: node.boardName,
                count: node.count,
                totalCount: node.count + childTotal,
                children: childNodes
            )
        }

        return orderedChildren(of: root, isRoot: true).compactMap { child in
            build(child, path: [child.name])
        }
    }
}
