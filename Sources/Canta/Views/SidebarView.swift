import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var hoveredNav: LibrarySection?
    @State private var hoveredBoard: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 20)
                .padding(.top, 48)

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
                    ForEach(store.boardSummaries) { board in
                        boardRow(board)
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
        .frame(width: 246)
        .background(Theme.parchment)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(width: 1)
        }
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
        .buttonStyle(.plain)
        .onHover { hovering in hoveredNav = hovering ? section : (hoveredNav == section ? nil : hoveredNav) }
    }

    private func boardRow(_ board: BoardSummary) -> some View {
        let selected = store.section == .all && store.selectedBoard == board.name
        let representative = store.pins.first { $0.board.caseInsensitiveCompare(board.name) == .orderedSame }

        return Button {
            store.select(board: board.name)
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.boardColor(board.name).opacity(0.14))
                    if let representative {
                        LibraryImage(path: store.thumbnailURL(for: representative).path, contentMode: .fill)
                    } else {
                        Circle().fill(Theme.boardColor(board.name)).frame(width: 6, height: 6)
                    }
                }
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(localizedBoard(board.name))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selected ? Theme.ink : Theme.inkSecondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(board.count)")
                    .font(Theme.mono(9.5, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(.horizontal, 9)
            .frame(height: 35)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Theme.parchmentDeep : (hoveredBoard == board.name ? Theme.parchmentDeep.opacity(0.5) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in hoveredBoard = hovering ? board.name : (hoveredBoard == board.name ? nil : hoveredBoard) }
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
            .buttonStyle(.plain)
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