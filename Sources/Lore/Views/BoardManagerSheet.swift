import SwiftUI

/// Board manager. Boards only exist as names on pins, so every operation here
/// rewrites those names: renaming a group carries its descendants, renaming
/// onto an existing name merges the two, and deleting re-files pins under
/// Unsorted without touching their images.
struct BoardManagerSheet: View {
    @Environment(LibraryStore.self) private var store

    private struct Row: Identifiable {
        let node: BoardNode
        let depth: Int
        var id: String { node.id }
    }

    @State private var editingPath: String?
    @State private var draft = ""
    @State private var inlineError: String?
    @State private var pendingDelete: BoardNode?
    @State private var hoveredPath: String?
    @State private var creatingBoard = false
    /// Folder the create form is nested under, when it was opened from a group
    /// row rather than from the general "New board" button.
    @State private var creatingParent: String?
    @FocusState private var nameFocused: Bool

    private var rows: [Row] {
        var result: [Row] = []
        func walk(_ nodes: [BoardNode], depth: Int) {
            for node in nodes {
                result.append(Row(node: node, depth: depth))
                if !node.children.isEmpty { walk(node.children, depth: depth + 1) }
            }
        }
        walk(store.boardTree, depth: 0)
        return result
    }

    /// Lowercased full paths of every board and group, for the merge hint.
    private var knownPaths: Set<String> {
        var paths = Set<String>()
        func walk(_ nodes: [BoardNode]) {
            for node in nodes {
                paths.insert(node.id)
                walk(node.children)
            }
        }
        walk(store.boardTree)
        return paths
    }

    private var mergeTarget: String? {
        guard let editingPath else { return nil }
        let candidate = BoardPath.canonicalName(rawBoardName(fromDisplay: draft))
        guard !candidate.isEmpty else { return nil }
        let key = BoardPath.key(candidate)
        guard key != BoardPath.key(editingPath), knownPaths.contains(key) else { return nil }
        return candidate
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.34)
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .onTapGesture { close() }

                VStack(alignment: .leading, spacing: 0) {
                    header
                    Divider()
                        .overlay(Theme.hairline)
                        .padding(.top, 18)
                    boardList
                    footer
                }
                .padding(26)
                .frame(width: min(600, geo.size.width - 96))
                .frame(maxHeight: min(640, geo.size.height - 96))
                .background(Theme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 48, y: 22)
                .overlay(alignment: .topTrailing) { closeButton }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.975)))
        .alert(
            T("Delete board?"),
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { node in
            Button(T("Delete"), role: .destructive) {
                store.deleteBoard(node.fullName)
                pendingDelete = nil
            }
            Button(T("Cancel"), role: .cancel) {
                pendingDelete = nil
            }
        } message: { node in
            Text(deleteMessage(for: node))
        }
    }

    // MARK: - Header / footer

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(T("Manage boards"))
                .font(.system(size: 26, weight: .bold))
                .tracking(-1)
                .foregroundStyle(Theme.ink)

            Text(T("Rename a board, merge it into another by using the same name, or remove it. Use “/” to nest, e.g. Baseten/Products."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkTertiary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.trailing, 34)
    }

    private var closeButton: some View {
        Button { close() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 29, height: 29)
                .background(Circle().fill(Theme.parchment))
        }
        .buttonStyle(PressableStyle())
        .padding(16)
        .help(T("Close"))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
                .overlay(Theme.hairline)

            HStack(alignment: .center, spacing: 14) {
                Text(T("Rename to an existing board name to merge the two."))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                LoreButton(title: T("Done"), variant: .secondary) {
                    close()
                }
            }
        }
        .padding(.top, 16)
    }

    // MARK: - List

    private var boardList: some View {
        VStack(spacing: 10) {
            createRow
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 1) {
                    if rows.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "folder")
                                .font(.system(size: 20, weight: .light))
                                .foregroundStyle(Theme.inkTertiary)
                            Text(T("No boards yet — create one above."))
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.inkTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 42)
                    } else {
                        ForEach(rows) { item in
                            row(item)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(height: listHeight)
        }
        .padding(.top, 10)
    }

    /// Creating a board lives here as well as in the sidebar: an empty board is
    /// exactly what this sheet is for, and it can be named before it has pins.
    private var createRow: some View {
        Group {
            if creatingBoard {
                NewBoardForm(
                    parent: creatingParent,
                    onCancel: {
                        creatingBoard = false
                        creatingParent = nil
                    },
                    onCreated: { _ in
                        creatingBoard = false
                        creatingParent = nil
                    }
                )
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.parchment.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
            } else {
                Button {
                    creatingParent = nil
                    creatingBoard = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text(T("New board"))
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text(T("Use “/” to nest"))
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.parchment))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PointerPlainButtonStyle())
            }
        }
    }

    /// Size the list to its rows, capped so large libraries scroll.
    private var listHeight: CGFloat {
        guard !rows.isEmpty else { return 150 }
        return min(CGFloat(rows.count) * 41 + 12, 396)
    }

    private func row(_ item: Row) -> some View {
        let node = item.node
        let path = node.fullName
        let editing = editingPath == path
        let protected = BoardPath.key(path) == "unsorted"
        let hovered = hoveredPath == path

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                if item.depth > 0 {
                    Color.clear.frame(width: CGFloat(item.depth) * 15, height: 1)
                }

                glyph(node)

                if editing {
                    TextField(T("New board name"), text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .focused($nameFocused)
                        .onSubmit { commit(node) }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Theme.parchment)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    inlineError == nil ? Theme.hairline : Theme.red.opacity(0.55),
                                    lineWidth: 1
                                )
                        )

                    Button { commit(node) } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Theme.red))
                    }
                    .buttonStyle(PointerPlainButtonStyle())
                    .help(T("Rename board"))

                    Button { cancelEdit() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.inkSecondary)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Theme.parchment))
                    }
                    .buttonStyle(PointerPlainButtonStyle())
                    .help(T("Cancel"))
                } else {
                    Text(localizedBoard(node.title))
                        .font(.system(size: 12.5, weight: node.isBoard ? .medium : .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if !node.isBoard {
                        chip(T("Group"))
                    }

                    Spacer(minLength: 8)

                    Text("\(node.totalCount)")
                        .font(Theme.mono(10, weight: .medium))
                        .foregroundStyle(Theme.inkTertiary)
                        .frame(minWidth: 18, alignment: .trailing)

                    if protected {
                        chip(T("Default"))
                            .help(T("Unsorted is the fallback inbox and can't be removed."))
                    } else {
                        HStack(spacing: 2) {
                            if !node.children.isEmpty {
                                iconButton("plus", help: T("New board in this group")) {
                                    creatingParent = path
                                    creatingBoard = true
                                }
                            }
                            if let board = node.boardName {
                                iconButton("photo", help: T("Change board logo")) {
                                    store.boardLogoEditor = board
                                }
                            }
                            iconButton("pencil", help: T("Rename board")) {
                                beginEdit(node)
                            }
                            iconButton("trash", help: T("Delete board")) {
                                pendingDelete = node
                            }
                        }
                        .opacity(hovered ? 1 : 0.65)
                    }
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovered ? Theme.parchment.opacity(0.75) : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    hoveredPath = path
                } else if hoveredPath == path {
                    hoveredPath = nil
                }
            }

            if editing, let inlineError {
                Text(inlineError)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.red)
                    .padding(.leading, CGFloat(item.depth) * 15 + 41)
            } else if editing, mergeTarget != nil {
                Text(T("A board with this name already exists — saving will merge them."))
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.amber)
                    .padding(.leading, CGFloat(item.depth) * 15 + 41)
            }
        }
    }

    private func glyph(_ node: BoardNode) -> some View {
        let accent = Theme.boardColor(node.segments.first ?? node.title)
        return ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(accent.opacity(0.14))
            if let board = node.boardName, let display = store.boardLogoDisplay(for: board) {
                BoardLogoBadge(display: display, accent: accent, size: 24, cornerRadius: 7)
            } else {
                Image(systemName: node.isBoard ? "rectangle.stack.fill" : "folder.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
            }
        }
        .frame(width: 24, height: 24)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(Theme.inkTertiary)
            .padding(.horizontal, 6)
            .frame(height: 17)
            .background(Capsule().fill(Theme.parchmentDeep))
    }

    private func iconButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(PointerPlainButtonStyle())
        .help(help)
    }

    // MARK: - Actions

    private func beginEdit(_ node: BoardNode) {
        editingPath = node.fullName
        draft = localizedBoard(node.fullName)
        inlineError = nil
        DispatchQueue.main.async {
            nameFocused = true
        }
    }

    private func cancelEdit() {
        editingPath = nil
        inlineError = nil
        nameFocused = false
    }

    private func commit(_ node: BoardNode) {
        let candidate = BoardPath.canonicalName(rawBoardName(fromDisplay: draft))
        guard !candidate.isEmpty else {
            inlineError = T("Board name can't be empty.")
            return
        }
        guard !BoardPath.isDescendant(candidate, of: node.fullName) else {
            inlineError = T("A board can't be moved inside itself.")
            return
        }
        guard store.renameBoard(node.fullName, to: candidate) else {
            inlineError = T("Couldn't rename this board.")
            return
        }
        cancelEdit()
    }

    private func deleteMessage(for node: BoardNode) -> String {
        let display = localizedBoard(node.fullName)
        if node.children.isEmpty {
            return TF("“%@” will be removed. %ld pins will move to Unsorted; images are kept.", display, node.totalCount)
        }
        return TF("“%@” and its sub-boards will be removed. %ld pins will move to Unsorted; images are kept.", display, node.totalCount)
    }

    private func close() {
        store.boardManagerPresented = false
    }
}
