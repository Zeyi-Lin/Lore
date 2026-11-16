import SwiftUI

/// Board picker behind the pin's board pill.
///
/// It replaced a flat list of every board in the library, which grew into a
/// screen-tall menu as soon as a library had nested boards (`Anthropic/…`
/// alone was twenty-eight rows). The picker folds sub-boards into their group,
/// keeps every other group closed, and lays rows out lazily, so opening it
/// costs the same whether the library holds six boards or sixty. Search covers
/// the board you want inside a group you would rather not open.
/// Shared with the row modifier, which draws the same 30 pt rhythm.
private enum BoardPickerMetrics {
    static let width: CGFloat = 244
    static let rowHeight: CGFloat = 30
    static let rowSpacing: CGFloat = 1
    static let listPadding: CGFloat = 12
    /// Roughly ten rows. Past that the list scrolls instead of outgrowing the
    /// window, which is what made the old menu so tall.
    static let maxListHeight: CGFloat = 336
    /// Below this many boards there is nothing to search through.
    static let searchThreshold = 8
}


/// The pin's board pill and its picker. The presented state lives here, not on
/// the card: toggling it used to re-evaluate the whole detail card, which made
/// opening the menu cost more than the menu itself.
struct BoardPill: View {
    let board: String
    let onPick: (String) -> Void
    let onNewBoard: () -> Void

    @State private var presented = false
    @State private var hovering = false

    var body: some View {
        Button {
            presented.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.boardColor(board))
                    .frame(width: 6, height: 6)
                Text(localizedBoard(board))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 31)
            .background(Capsule().fill(hovering ? Theme.parchmentDeep : Theme.parchment))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PointerPlainButtonStyle())
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            BoardPicker(
                current: board,
                onPick: { name in
                    onPick(name)
                    presented = false
                },
                onNewBoard: {
                    onNewBoard()
                    presented = false
                }
            )
        }
    }
}

struct BoardPicker: View {
    let current: String
    let onPick: (String) -> Void
    let onNewBoard: () -> Void

    @Environment(LibraryStore.self) private var store
    @State private var query = ""
    /// Groups the pointer opened or closed, layered on the default: the groups
    /// above the pin's own board are open so the checked row is always
    /// visible, everything else starts folded.
    @State private var opened: Set<String> = []
    @State private var closed: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.allBoardNames.count > BoardPickerMetrics.searchThreshold {
                searchField
            }

            if items.isEmpty {
                emptyState
            } else {
                list
            }

            Divider()
            newBoardRow
        }
        .frame(width: BoardPickerMetrics.width)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)

            TextField(T("Search boards"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .onSubmit { pickFirstMatch() }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkTertiary)
                }
                .buttonStyle(PointerPlainButtonStyle())
                .help(T("Clear search"))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 27)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.parchment))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .padding(.horizontal, 6)
        .padding(.top, 7)
    }

    private var emptyState: some View {
        Text(T("No boards match"))
            .font(.system(size: 11))
            .foregroundStyle(Theme.inkTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
    }

    // MARK: - List

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: BoardPickerMetrics.rowSpacing) {
                ForEach(items) { item in
                    row(item)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .frame(height: listHeight)
    }

    private var listHeight: CGFloat {
        let rows = CGFloat(max(items.count, 1))
        let content = rows * BoardPickerMetrics.rowHeight
            + max(rows - 1, 0) * BoardPickerMetrics.rowSpacing
            + BoardPickerMetrics.listPadding
        return min(content, BoardPickerMetrics.maxListHeight)
    }

    @ViewBuilder
    private func row(_ item: BoardPickerItem) -> some View {
        switch item.kind {
        case .group(let node, let expanded):
            groupRow(item, node: node, expanded: expanded)
        case .board(let name):
            boardRow(item, name: name)
        }
    }

    private func groupRow(_ item: BoardPickerItem, node: BoardNode, expanded: Bool) -> some View {
        let board = node.boardName
        let selected = board.map { isCurrent($0) } ?? false
        return HStack(spacing: 7) {
            // The chevron is its own button: the row itself files the pin when
            // the group is also a real board.
            Button {
                toggle(node.id, expanded: !expanded)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.inkTertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 13, height: BoardPickerMetrics.rowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PointerPlainButtonStyle())
            .help(expanded ? T("Collapse board group") : T("Expand board group"))

            if let board {
                Circle()
                    .fill(Theme.boardColor(board))
                    .frame(width: 6, height: 6)
            }

            Text(item.label)
                .font(.system(size: 12, weight: board == nil ? .semibold : .medium))
                .foregroundStyle(board == nil ? Theme.inkSecondary : Theme.ink)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text("\(node.totalCount)")
                .font(Theme.mono(9.5, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)

            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.red)
            }
        }
        .modifier(PickerRowStyle(item: item, isCurrent: selected))
        .onTapGesture {
            if let board {
                onPick(board)
            } else {
                toggle(node.id, expanded: !expanded)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func boardRow(_ item: BoardPickerItem, name: String) -> some View {
        let selected = isCurrent(name)
        return HStack(spacing: 7) {
            Color.clear.frame(width: 13, height: BoardPickerMetrics.rowHeight)

            Circle()
                .fill(Theme.boardColor(name))
                .frame(width: 6, height: 6)

            Text(item.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.red)
            }
        }
        .modifier(PickerRowStyle(item: item, isCurrent: selected))
        .onTapGesture { onPick(name) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var newBoardRow: some View {
        Button(action: onNewBoard) {
            Label(T("New board…"), systemImage: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: BoardPickerMetrics.rowHeight)
                .contentShape(Rectangle())
                .menuRowHover()
        }
        .buttonStyle(PointerPlainButtonStyle())
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    // MARK: - Rows

    private var items: [BoardPickerItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty {
            return matches(for: needle.lowercased())
        }

        let ancestors = Set(BoardPath.ancestorKeys(current))
        var items: [BoardPickerItem] = []
        func walk(_ nodes: [BoardNode], depth: Int) {
            for node in nodes {
                if node.children.isEmpty {
                    guard let board = node.boardName else { continue }
                    items.append(
                        BoardPickerItem(
                            id: "board:\(node.id)",
                            depth: depth,
                            label: localizedBoard(node.title),
                            kind: .board(board)
                        )
                    )
                } else {
                    let expanded = isExpanded(node, ancestors: ancestors)
                    items.append(
                        BoardPickerItem(
                            id: "group:\(node.id)",
                            depth: depth,
                            label: localizedBoard(node.title),
                            kind: .group(node, expanded: expanded)
                        )
                    )
                    if expanded {
                        walk(node.children, depth: depth + 1)
                    }
                }
            }
        }
        walk(store.boardTree, depth: 0)
        return items
    }

    /// Flat results while searching: a hit can be several levels deep, so each
    /// row carries its full path instead of its indentation.
    private func matches(for needle: String) -> [BoardPickerItem] {
        var items: [BoardPickerItem] = []
        func walk(_ nodes: [BoardNode]) {
            for node in nodes {
                if let board = node.boardName {
                    let path = localizedBoard(board)
                    if path.lowercased().contains(needle) || board.lowercased().contains(needle) {
                        items.append(
                            BoardPickerItem(
                                id: "board:\(node.id)",
                                depth: 0,
                                label: path,
                                kind: .board(board)
                            )
                        )
                    }
                }
                walk(node.children)
            }
        }
        walk(store.boardTree)
        return items
    }

    /// Return picks the top hit, so a search is type → Return.
    private func pickFirstMatch() {
        guard !query.isEmpty, case .board(let name)? = items.first?.kind else { return }
        onPick(name)
    }

    private func isCurrent(_ board: String) -> Bool {
        board.caseInsensitiveCompare(current) == .orderedSame
    }

    private func isExpanded(_ node: BoardNode, ancestors: Set<String>) -> Bool {
        if closed.contains(node.id) { return false }
        if opened.contains(node.id) { return true }
        return ancestors.contains(node.id)
    }

    private func toggle(_ key: String, expanded: Bool) {
        if expanded {
            closed.remove(key)
            opened.insert(key)
        } else {
            opened.remove(key)
            closed.insert(key)
        }
    }
}

// MARK: - Row model

private struct BoardPickerItem: Identifiable {
    enum Kind {
        case group(BoardNode, expanded: Bool)
        case board(String)
    }

    let id: String
    let depth: Int
    let label: String
    let kind: Kind
}

/// Shared row chrome: inset by depth, hover surface, pointer cursor.
private struct PickerRowStyle: ViewModifier {
    let item: BoardPickerItem
    let isCurrent: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.leading, CGFloat(item.depth) * 13)
            .frame(height: BoardPickerMetrics.rowHeight)
            .contentShape(Rectangle())
            .menuRowHover(isSelected: isCurrent)
            .pointerCursor()
    }
}
