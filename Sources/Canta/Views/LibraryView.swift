import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var showSortMenu = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(height: 1)
                        .id("library-top")

                    header
                        .padding(.horizontal, 34)
                        .padding(.top, 22)

                    filterBar
                        .padding(.horizontal, 34)
                        .padding(.top, 23)
                        .padding(.bottom, 21)

                    if store.filteredPins.isEmpty {
                        EmptyStateView(mode: store.pins.isEmpty ? .emptyLibrary : .noResults)
                            .padding(.horizontal, 34)
                            .padding(.top, 8)
                    } else {
                        MasonryLayout(
                            minColumnWidth: 238,
                            maxColumns: 5,
                            columnSpacing: 20,
                            rowSpacing: 28
                        ) {
                            ForEach(store.filteredPins) { pin in
                                PinCard(pin: pin)
                                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                            }
                        }
                        .padding(.horizontal, 34)
                        .padding(.bottom, 64)
                        .animation(.snappy(duration: 0.32), value: store.currentListIdentity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.top)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    proxy.scrollTo("library-top", anchor: .top)
                }
            }
            .onChange(of: store.currentListIdentity) { _, _ in
                proxy.scrollTo("library-top", anchor: .top)
            }
        }
        .background(Theme.paper)
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Theme.red)
                        .frame(width: 5, height: 5)
                    Text(kicker)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(Theme.inkTertiary)
                }

                Text(store.pageTitle)
                    .font(.system(size: 35, weight: .bold))
                    .tracking(-1.35)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(store.pageSubtitle)
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(Theme.inkTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            sortMenu
                .padding(.bottom, 3)
        }
    }

    private var kicker: String {
        if !store.searchText.trimmed.isEmpty { return T("SEARCHING YOUR LIBRARY") }
        if let board = store.selectedBoard { return TF("BOARD · %@", localizedBoard(board).uppercased()) }
        switch store.section {
        case .all: return T("YOUR VISUAL LIBRARY")
        case .favorites: return T("SAVED FOR LATER")
        case .recent: return T("RECENTLY PINNED")
        case .agent: return T("AGENT ACCESS")
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            FilterChip(title: T("All"), count: store.pins.count, isSelected: store.filter == .all) {
                withAnimation(.easeOut(duration: 0.18)) { store.filter = .all }
            }
            FilterChip(title: T("Screenshots"), count: store.screenshotCount, isSelected: store.filter == .screenshots) {
                withAnimation(.easeOut(duration: 0.18)) { store.filter = .screenshots }
            }
            FilterChip(title: T("Favorites"), count: store.favoriteCount, isSelected: store.filter == .favorites) {
                withAnimation(.easeOut(duration: 0.18)) { store.filter = .favorites }
            }

            Rectangle()
                .fill(Theme.hairline)
                .frame(width: 1, height: 18)
                .padding(.horizontal, 5)

            if let board = store.selectedBoard {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { store.selectedBoard = nil }
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.boardColor(board)).frame(width: 6, height: 6)
                        Text(localizedBoard(board))
                            .font(.system(size: 11.5, weight: .semibold))
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .background(Capsule().fill(Theme.parchmentDeep))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(T("Clear board filter"))
            } else {
                Text(TF("%ld shown", store.filteredPins.count))
                    .font(Theme.mono(10.5, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.leading, 2)
            }

            Spacer()
        }
    }

    private var sortMenu: some View {
        Button {
            showSortMenu.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10, weight: .semibold))
                Text(store.sort.title)
                    .font(.system(size: 11.5, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.55)
            }
            .foregroundStyle(Theme.inkSecondary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(Theme.parchment))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .popover(isPresented: $showSortMenu, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(PinSort.allCases) { sort in
                    Button {
                        withAnimation(.snappy(duration: 0.24)) { store.sort = sort }
                        showSortMenu = false
                    } label: {
                        HStack(spacing: 8) {
                            Text(sort.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            if store.sort == sort {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Theme.red)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 31)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(store.sort == sort ? Theme.parchment : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .frame(width: 196)
        }
    }
}