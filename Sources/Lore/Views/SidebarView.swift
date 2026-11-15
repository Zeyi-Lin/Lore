import SwiftUI
import AppKit

struct SidebarView: View {
    @Environment(LibraryStore.self) private var store
    @State private var hoveredNav: LibrarySection?
    @State private var hoveredBoardKey: String?
    /// Group keys the user has opened. Empty by default, so prefix groups
    /// arrive folded into a single row ("收起").
    @AppStorage("lore.expandedBoardGroups") private var expandedBoardGroups = ""
    /// Which row currently shows a drop affordance, and what kind.
    @State private var dropHint: BoardDropHint?
    /// The row being renamed inline, keyed by `BoardNode.id`, plus its draft
    /// and validation state. Inline editing lives in the sidebar so a rename
    /// doesn't require opening the board manager.
    @State private var renamingBoardKey: String?
    @State private var renameDraft = ""
    @State private var renameHasError = false
    @FocusState private var renameFocused: Bool
    /// Escape cancels the inline rename before `RootView`'s `onExitCommand`
    /// can treat it as "clear search" or "close detail".
    @State private var renameEscapeMonitor: Any?
    @State private var trashTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 20)
                // Aligns the brand row with the top bar content; keep in sync
                // with TopBarView's top padding.
                .padding(.top, 19)

            LoreButton(
                title: T("Capture"),
                icon: "plus",
                variant: .primary,
                shortcut: "⇧⌘N",
                fullWidth: true
            ) {
                store.capturePresented = true
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .shadow(color: Theme.red.opacity(0.18), radius: 12, y: 5)

            VStack(spacing: 2) {
                navRow(section: .all, icon: "square.grid.2x2", filledIcon: "square.grid.2x2.fill", badge: store.pins.count)
                navRow(section: .favorites, icon: "heart", filledIcon: "heart.fill", badge: store.favoriteCount)
                navRow(section: .recent, icon: "clock", filledIcon: "clock.fill", badge: nil)
            }
            .padding(.horizontal, 10)
            .padding(.top, 20)

            Hairline()
                .padding(.horizontal, 20)
                .padding(.vertical, 17)

            HStack(spacing: 6) {
                SectionLabel(text: T("Boards"), trailing: "\(store.boardSummaries.count)")

                Button {
                    store.boardManagerPresented = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkTertiary)
                        .frame(width: 20, height: 20)
                        .contentShape(Circle())
                }
                .buttonStyle(PointerPlainButtonStyle())
                .help(T("Manage boards"))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(visibleBoardRows) { item in
                        boardRow(item)
                    }
                    if store.boardSummaries.isEmpty {
                        Text(T("Boards appear here as you pin."))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 22)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(maxHeight: .infinity)

            footer
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 16)
        }
        .frame(width: LoreLayout.sidebarWidth)
        .background(Theme.parchment)
        .onAppear { revealSelectedBoard() }
        .onChange(of: store.selectedBoard) { _, _ in revealSelectedBoard() }
        .onReceive(NotificationCenter.default.publisher(for: .loreResignTextFocus)) { _ in
            commitRename()
        }
        .onDisappear { removeRenameEscapeMonitor() }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            LoreMark(size: 35)
            VStack(alignment: .leading, spacing: 1) {
                Text("Lore")
                    .font(.system(size: 23, weight: .bold))
                    .tracking(-0.9)
                    .foregroundStyle(Theme.ink)
                Text(T("VISUAL LIBRARY"))
                    .font(.system(size: 7.5, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(Theme.inkTertiary)
            }
            Spacer()
        }
    }

    private func navRow(section: LibrarySection, icon: String, filledIcon: String, badge: Int?) -> some View {
        let selected = store.section == section && store.selectedBoard == nil
        return Button {
            store.select(section: section)
        } label: {
            SidebarRowLabel(
                icon: selected ? filledIcon : icon,
                title: section.title,
                badge: badge,
                selected: selected,
                accent: section == .favorites ? Theme.red : nil
            )
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Theme.parchmentDeep : (hoveredNav == section ? Theme.parchmentDeep.opacity(0.5) : Color.clear))
            )
        }
        .buttonStyle(PointerPlainButtonStyle())
        .onHover { hovering in hoveredNav = hovering ? section : (hoveredNav == section ? nil : hoveredNav) }
    }

    // MARK: - Hierarchical boards

    private var expandedGroups: Set<String> {
        Set(expandedBoardGroups.split(separator: "\n").map(String.init))
    }

    private var visibleBoardRows: [BoardRowItem] {
        var rows: [BoardRowItem] = []
        let expanded = expandedGroups
        func walk(_ nodes: [BoardNode], parentKey: String, depth: Int) {
            for node in nodes {
                rows.append(BoardRowItem(node: node, parentKey: parentKey, depth: depth))
                if !node.children.isEmpty, expanded.contains(node.id) {
                    walk(node.children, parentKey: node.id, depth: depth + 1)
                }
            }
        }
        walk(store.boardTree, parentKey: "", depth: 0)
        return rows
    }

    private func setGroup(_ key: String, expanded: Bool) {
        var keys = expandedGroups
        if expanded {
            keys.insert(key)
        } else {
            keys.remove(key)
        }
        expandedBoardGroups = keys.sorted().joined(separator: "\n")
    }

    private func revealSelectedBoard() {
        guard let board = store.selectedBoard else { return }
        let ancestors = BoardPath.ancestorKeys(board)
        guard !ancestors.isEmpty else { return }
        var keys = expandedGroups
        let before = keys.count
        keys.formUnion(ancestors)
        guard keys.count != before else { return }
        expandedBoardGroups = keys.sorted().joined(separator: "\n")
    }

    /// An editing row drops the drag source, tap target, and context menu so
    /// the text field keeps text selection and its own edit menu.
    @ViewBuilder
    private func boardRow(_ item: BoardRowItem) -> some View {
        let node = item.node
        if renamingBoardKey == node.id {
            boardRowShell(item)
        } else {
            boardRowShell(item)
                .onTapGesture {
                    if let board = node.boardName {
                        store.select(board: board)
                    } else {
                        withAnimation(.snappy(duration: 0.22)) {
                            setGroup(node.id, expanded: !expandedGroups.contains(node.id))
                        }
                    }
                }
                .pointerCursor()
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .contextMenu { boardContextMenu(for: node) }
                .onDrag {
                    LoreDrag.provider(marker: store.beginBoardDrag(parentKey: item.parentKey, key: node.id))
                }
                .onDrop(of: [LoreDrag.type], delegate: BoardRowDropDelegate(
                    parentKey: item.parentKey,
                    targetKey: node.id,
                    boardName: node.boardName,
                    hint: $dropHint,
                    store: store
                ))
                .help(node.boardName == nil ? T("Drag to reorder") : T("Drag to reorder · drop a pin here to file it"))
        }
    }

    private func boardRowShell(_ item: BoardRowItem) -> some View {
        let node = item.node
        let hasChildren = !node.children.isEmpty
        let expanded = expandedGroups.contains(node.id)
        let editing = renamingBoardKey == node.id
        let selected = node.boardName.map {
            store.section == .all && store.selectedBoard?.caseInsensitiveCompare($0) == .orderedSame
        } ?? false
        let hovered = hoveredBoardKey == node.id
        let depthInset = CGFloat(item.depth) * 13

        return HStack(spacing: 0) {
            if hasChildren {
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        setGroup(node.id, expanded: !expanded)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.inkTertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 17, height: 35)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PointerPlainButtonStyle())
                .help(expanded ? T("Collapse board group") : T("Expand board group"))
            } else {
                Color.clear.frame(width: 17, height: 35)
            }

            HStack(spacing: 9) {
                boardIcon(node)

                if editing {
                    renameField
                } else {
                    Text(localizedBoard(node.title))
                        .font(.system(size: 12, weight: node.isBoard ? .medium : .semibold))
                        .foregroundStyle(selected ? Theme.ink : Theme.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 4)
                }

                Text("\(node.totalCount)")
                    .font(Theme.mono(9.5, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(.trailing, 9)
            .frame(height: 35)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .padding(.leading, 9 + depthInset)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    editing || selected
                        ? Theme.parchmentDeep
                        : (hovered ? Theme.parchmentDeep.opacity(0.5) : Color.clear)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { hovering in
            hoveredBoardKey = hovering ? node.id : (hoveredBoardKey == node.id ? nil : hoveredBoardKey)
        }
        .overlay(alignment: .top) { insertionLine(above: true, for: node.id) }
        .overlay(alignment: .bottom) { insertionLine(above: false, for: node.id) }
        .overlay { pinDropHighlight(for: node.id) }
    }

    /// Inline rename field. Enter or clicking elsewhere saves; Esc cancels.
    private var renameField: some View {
        TextField("", text: $renameDraft)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.ink)
            .focused($renameFocused)
            .onSubmit { commitRename() }
            .onChange(of: renameDraft) { _, _ in renameHasError = false }
            .onAppear { adoptRenameFocus() }
            .padding(.horizontal, 7)
            .frame(height: 25)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.paper)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        renameHasError ? Theme.red : Theme.red.opacity(0.45),
                        lineWidth: 1
                    )
            )
    }

    @ViewBuilder
    private func boardContextMenu(for node: BoardNode) -> some View {
        if BoardPath.key(node.fullName) != "unsorted" {
            Button(node.isBoard ? T("Rename board") : T("Rename group")) {
                beginRename(node)
            }
            Divider()
        }
        Button(T("Manage boards…")) {
            cancelRename()
            store.boardManagerPresented = true
        }
    }

    // MARK: - Inline rename

    private func beginRename(_ node: BoardNode) {
        renamingBoardKey = node.id
        // The field edits the row's own label, so nested boards keep their
        // parent path (`Anthropic/Commitments` stays under Anthropic).
        renameDraft = localizedBoard(node.title)
        renameHasError = false
        installRenameEscapeMonitor()
    }

    /// Focus once the field is in the window. Rename starts from a context
    /// menu, so give the menu time to finish dismissing first.
    private func adoptRenameFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard renamingBoardKey != nil else { return }
            renameFocused = true
            // Preselect the old name so typing replaces it in one go.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
        }
    }

    private func commitRename() {
        guard let key = renamingBoardKey else { return }
        guard let node = boardNode(forKey: key) else {
            cancelRename()
            return
        }

        let typedParts = BoardPath.segments(rawBoardName(fromDisplay: renameDraft))
        guard !typedParts.isEmpty else {
            renameHasError = true
            store.showToast(T("Board name can't be empty."), icon: "exclamationmark.triangle")
            focusRenameField()
            return
        }
        let typed = typedParts.joined(separator: String(BoardPath.separator))

        var parts = node.segments
        parts[parts.count - 1] = typed
        let candidate = parts.joined(separator: String(BoardPath.separator))
        guard candidate != node.fullName else {
            cancelRename()
            return
        }
        guard !BoardPath.isDescendant(candidate, of: node.fullName) else {
            renameHasError = true
            store.showToast(T("A board can't be moved inside itself."), icon: "exclamationmark.triangle")
            focusRenameField()
            return
        }

        let oldKey = node.id
        let newKey = BoardPath.key(candidate)
        let wasExpanded = expandedGroups.contains(oldKey)

        renamingBoardKey = nil
        renameFocused = false
        renameHasError = false
        removeRenameEscapeMonitor()

        guard store.renameBoard(node.fullName, to: candidate) else {
            store.showToast(T("Couldn't rename this board."), icon: "exclamationmark.triangle")
            return
        }

        // Keep a renamed group open where the user left it.
        if wasExpanded {
            var keys = expandedGroups
            keys.remove(oldKey)
            keys.insert(newKey)
            expandedBoardGroups = keys.sorted().joined(separator: "\n")
        }
    }

    private func cancelRename() {
        guard renamingBoardKey != nil else { return }
        renamingBoardKey = nil
        renameFocused = false
        renameHasError = false
        removeRenameEscapeMonitor()
    }

    private func focusRenameField() {
        // AppKit resigned the field editor on the click that triggered this
        // commit; reset the SwiftUI focus flag before asking for it again.
        renameFocused = false
        DispatchQueue.main.async {
            renameFocused = true
        }
    }

    private func boardNode(forKey key: String) -> BoardNode? {
        func find(_ nodes: [BoardNode]) -> BoardNode? {
            for node in nodes {
                if node.id == key { return node }
                if let match = find(node.children) { return match }
            }
            return nil
        }
        return find(store.boardTree)
    }

    /// `RootView` maps Escape to its global cancel chain; while a rename is
    /// live it should only close the field.
    private func installRenameEscapeMonitor() {
        guard renameEscapeMonitor == nil else { return }
        renameEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53, renamingBoardKey != nil else { return event }
            // Let an active IME composition consume Esc first; only a second
            // Esc should abandon the rename.
            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
               editor.hasMarkedText() {
                return event
            }
            cancelRename()
            return nil
        }
    }

    private func removeRenameEscapeMonitor() {
        guard let monitor = renameEscapeMonitor else { return }
        renameEscapeMonitor = nil
        // Removing a monitor from inside its own callback is fragile; let the
        // current event finish first.
        DispatchQueue.main.async {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// The 2 pt line that shows where a dragged row will land.
    @ViewBuilder
    private func insertionLine(above: Bool, for key: String) -> some View {
        if dropHint == .reorder(key: key, after: !above) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Theme.red)
                .frame(height: 2)
                .padding(.horizontal, 4)
                .offset(y: above ? -1 : 1)
                .allowsHitTesting(false)
        }
    }

    /// A board that a dragged pin (or selection) would be filed into.
    @ViewBuilder
    private func pinDropHighlight(for key: String) -> some View {
        if dropHint == .pins(key: key) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.red.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Theme.red.opacity(0.55), lineWidth: 1)
                )
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func boardIcon(_ node: BoardNode) -> some View {
        let accent = Theme.boardColor(node.segments.first ?? node.title)
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(accent.opacity(0.14))
            if let board = node.boardName, let representative = store.representativePin(forBoard: board) {
                LibraryImage(paths: store.cardImageCandidates(for: representative), maxPixel: 64, contentMode: .fill)
            } else if node.children.isEmpty {
                Circle().fill(accent).frame(width: 6, height: 6)
            } else {
                Image(systemName: "folder.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(accent)
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var footer: some View {
        ZStack {
            if store.isDraggingPins || trashTargeted {
                trashFooter
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                libraryFooter
                    .transition(.opacity)
            }
        }
        .frame(height: 44, alignment: .leading)
        .contentShape(Rectangle())
        .onDrop(of: [LoreDrag.type], delegate: TrashDropDelegate(store: store, isTargeted: $trashTargeted))
        .animation(.easeOut(duration: 0.14), value: store.isDraggingPins)
        .animation(.easeOut(duration: 0.14), value: trashTargeted)
    }

    private var libraryFooter: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().fill(Theme.parchmentDeep)
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .frame(width: 29, height: 29)
            .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))

            VStack(alignment: .leading, spacing: 1) {
                Text(T("Local library"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(TF("%ld pins · private", store.pins.count))
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.inkTertiary)
            }

            Spacer()

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.parchmentDeep))
            }
            .buttonStyle(PointerPlainButtonStyle())
            .pointerCursor()
            .help(T("Settings"))
        }
    }

    private var trashFooter: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().fill(trashTargeted ? Theme.red : Theme.parchmentDeep)
                Image(systemName: trashTargeted ? "trash.fill" : "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(trashTargeted ? Color.white : Theme.inkSecondary)
            }
            .frame(width: 29, height: 29)
            .overlay(Circle().strokeBorder(trashTargeted ? Color.clear : Theme.hairline, lineWidth: 1))

            VStack(alignment: .leading, spacing: 1) {
                Text(trashTargeted ? T("Release to delete") : T("Drop here to delete"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(trashTargeted ? Theme.red : Theme.ink)
                Text(T("This cannot be undone."))
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.inkTertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(trashTargeted ? Theme.redWash : Theme.parchmentDeep)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(trashTargeted ? Theme.red : Theme.hairline, lineWidth: 1)
        )
    }
}

private struct SidebarRowLabel: View {
    var icon: String
    var title: String
    var badge: Int?
    var selected: Bool
    var accent: Color?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 20)
                .foregroundStyle(accent ?? (selected ? Theme.ink : Theme.inkSecondary))
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
            if let badge {
                Text("\(badge)")
                    .font(Theme.mono(9.5, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 37)
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct SidebarHoverStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Theme.parchmentDeep : Color.clear)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// The selected nav row needs its own filled background.
struct SidebarNavButtonStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Theme.parchmentDeep : Color.clear)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}