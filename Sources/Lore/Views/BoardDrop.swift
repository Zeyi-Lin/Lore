import SwiftUI
import UniformTypeIdentifiers

/// The pasteboard type used for sidebar/gallery drags.
///
/// A private type instead of `.text` keeps foreign drags (a paragraph dragged
/// from another app) from matching a board row and replaying a stale payload.
enum LoreDrag {
    static let identifier = "studio.lore.sidebar-drag"
    /// `UTType(_:)` returns nil for an identifier nobody declared, which would
    /// make `onDrop(of:)` accept nothing; `exportedAs:` always yields a usable
    /// type (and the bundle declares it too, see `scripts/build-app.sh`).
    static let type = UTType(exportedAs: identifier)

    static func provider(marker: String) -> NSItemProvider {
        NSItemProvider(item: marker as NSString, typeIdentifier: identifier)
    }
}

/// One row of the sidebar's board tree plus the path key it hangs under, which
/// is what the reorder logic needs (siblings only reorder within their parent).
struct BoardRowItem: Identifiable {
    let node: BoardNode
    let parentKey: String
    let depth: Int
    var id: String { node.id }
}

/// What is being dragged over a board row right now. `key` is the row's node
/// id, so the row can draw the matching affordance.
enum BoardDropHint: Equatable {
    /// Reorder: insert the dragged row above/below this one.
    case reorder(key: String, after: Bool)
    /// A pin (or a selection of pins) would land on this board.
    case pins(key: String)

    /// Id of the row this hint belongs to.
    var key: String {
        switch self {
        case let .reorder(key, _): return key
        case let .pins(key): return key
        }
    }
}

/// Drop handling for one sidebar row.
///
/// `DropDelegate` is `@MainActor` in the SDK, so this can talk to the store
/// directly. The drag *source* never travels through the pasteboard: the store
/// remembers what started the drag (`LibraryStore.activeDragPayload`), which
/// keeps `dropUpdated` synchronous and lets the row show the right affordance
/// before the mouse is released.
struct BoardRowDropDelegate: DropDelegate {
    let parentKey: String
    let targetKey: String
    /// `nil` for pure prefix groups, which are not a board a pin can move to.
    let boardName: String?
    @Binding var hint: BoardDropHint?
    let store: LibraryStore

    func validateDrop(info: DropInfo) -> Bool {
        proposal() != nil
    }

    func dropEntered(info: DropInfo) {
        updateHint(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateHint(info)
        return proposal()
    }

    func dropExited(info: DropInfo) {
        if hint?.key == targetKey {
            hint = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { hint = nil }
        guard let payload = store.activeDragPayload else { return false }
        defer { store.finishDrag() }

        switch payload {
        case let .pins(ids):
            guard let boardName, !ids.isEmpty else { return false }
            store.movePins(ids, toBoard: boardName)
            return true
        case let .board(sourceParent, sourceKey):
            guard sourceParent == parentKey, sourceKey != targetKey else { return false }
            let after = hint == .reorder(key: targetKey, after: true)
            store.moveBoardNode(sourceKey, in: parentKey, relativeTo: targetKey, after: after)
            return true
        }
    }

    /// Rejects mismatched drops so the system shows the "no" cursor instead of
    /// silently accepting a move to an unrelated group.
    private func proposal() -> DropProposal? {
        guard let payload = store.activeDragPayload else { return nil }
        switch payload {
        case let .pins(ids):
            guard boardName != nil, !ids.isEmpty else { return nil }
            return DropProposal(operation: .copy)
        case let .board(sourceParent, sourceKey):
            guard sourceParent == parentKey, sourceKey != targetKey else { return nil }
            return DropProposal(operation: .move)
        }
    }

    private func updateHint(_ info: DropInfo) {
        switch store.activeDragPayload {
        case let .pins(ids) where !ids.isEmpty && boardName != nil:
            hint = .pins(key: targetKey)
        case let .board(sourceParent, sourceKey) where sourceParent == parentKey && sourceKey != targetKey:
            hint = .reorder(key: targetKey, after: info.location.y > BoardRowMetrics.height / 2)
        default:
            if hint?.key == targetKey { hint = nil }
        }
    }
}

enum BoardRowMetrics {
    /// Keep in sync with the row height in `SidebarView`.
    static let height: CGFloat = 35
}
