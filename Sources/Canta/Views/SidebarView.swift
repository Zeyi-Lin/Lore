import SwiftUI

struct SidebarView: View {
    @Environment(LibraryStore.self) private var store
    @State private var hoveredNav: LibrarySection?
    @State private var hoveredBoardKey: String?
    /// Group keys the user has opened. Empty by default, so prefix groups
    /// arrive folded into a single row ("收起").
    @AppStorage("canta.expandedBoardGroups") private var expandedBoardGroups = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 20)
                // Aligns the brand row with the top bar content; keep in sync
                // with TopBarView's top padding.
                .padding(.top, 19)

            CantaButton(
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

            SectionLabel(text: T("Boards"), trailing: "\(store.boardSummaries.count)")
                .padding(.horizontal, 22)
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

            agentCard
                .padding(.horizontal, 14)
                .padding(.top, 10)

            footer
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 16)
        }
        .frame(width: CantaLayout.sidebarWidth)
        .background(Theme.parchment)
        .contentShape(Rectangle())
        .onAppear { revealSelectedBoard() }
        .onChange(of: store.selectedBoard) { _, _ in revealSelectedBoard() }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { WindowZoom.toggle() }
        )
    }

    private var brand: some View {
        HStack(spacing: 10) {
            CantaMark(size: 35)
            VStack(alignment: .leading, spacing: 1) {
                Text("Canta")
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

    private struct BoardRowItem: Identifiable {
        let node: BoardNode
        let depth: Int
        var id: String { node.id }
    }

    private var expandedGroups: Set<String> {
        Set(expandedBoardGroups.split(separator: "\n").map(String.init))
    }

    private var visibleBoardRows: [BoardRowItem] {
        var rows: [BoardRowItem] = []
        let expanded = expandedGroups
        func walk(_ nodes: [BoardNode], depth: Int) {
            for node in nodes {
                rows.append(BoardRowItem(node: node, depth: depth))
                if !node.children.isEmpty, expanded.contains(node.id) {
                    walk(node.children, depth: depth + 1)
                }
            }
        }
        walk(store.boardTree, depth: 0)
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

    private func boardRow(_ item: BoardRowItem) -> some View {
        let node = item.node
        let hasChildren = !node.children.isEmpty
        let expanded = expandedGroups.contains(node.id)
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

            Button {
                if let board = node.boardName {
                    store.select(board: board)
                } else {
                    withAnimation(.snappy(duration: 0.22)) {
                        setGroup(node.id, expanded: !expanded)
                    }
                }
            } label: {
                HStack(spacing: 9) {
                    boardIcon(node)

                    Text(localizedBoard(node.title))
                        .font(.system(size: 12, weight: node.isBoard ? .medium : .semibold))
                        .foregroundStyle(selected ? Theme.ink : Theme.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 4)

                    Text("\(node.totalCount)")
                        .font(Theme.mono(9.5, weight: .medium))
                        .foregroundStyle(Theme.inkTertiary)
                }
                .padding(.trailing, 9)
                .frame(height: 35)
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(PointerPlainButtonStyle())
        }
        .padding(.leading, 9 + depthInset)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Theme.parchmentDeep : (hovered ? Theme.parchmentDeep.opacity(0.5) : Color.clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { hovering in
            hoveredBoardKey = hovering ? node.id : (hoveredBoardKey == node.id ? nil : hoveredBoardKey)
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

    private var agentCard: some View {
        Button {
            store.select(section: .agent)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(agentDotColor)
                        .frame(width: 6, height: 6)
                    Text(T("Agent API").uppercased())
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(Theme.inkTertiary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.inkTertiary)
                }

                Text(store.agentStatusLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ink)

                Text(store.agentStatusDetail ?? T("Metadata and image streams for your coding agent."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.inkTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.paper)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(store.section == .agent ? Theme.red.opacity(0.35) : Theme.hairline, lineWidth: 1)
            )
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(store.section == .agent ? Theme.red.opacity(0.0) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PressableStyle())
    }

    private var agentDotColor: Color {
        switch store.agentStatus {
        case .running: return Theme.moss
        case .starting: return Theme.amber
        case .failed: return Theme.red
        case .stopped: return Theme.inkTertiary
        }
    }

    private var footer: some View {
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