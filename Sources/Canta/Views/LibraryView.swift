import SwiftUI

/// Lazy Pinterest-style masonry: one `LazyVStack` per column. Columns are
/// balanced once from aspect ratios (see `MasonryComposer`), so the grid no
/// longer instantiates or measures every card up front.
struct MasonryColumns<Card: View>: View {
    let columns: [[PinCardModel]]
    let columnWidth: CGFloat
    let spacing: CGFloat
    let rowSpacing: CGFloat
    private let card: (PinCardModel) -> Card

    init(
        columns: [[PinCardModel]],
        columnWidth: CGFloat,
        spacing: CGFloat,
        rowSpacing: CGFloat,
        @ViewBuilder card: @escaping (PinCardModel) -> Card
    ) {
        self.columns = columns
        self.columnWidth = columnWidth
        self.spacing = spacing
        self.rowSpacing = rowSpacing
        self.card = card
    }

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(columns.indices, id: \.self) { index in
                LazyVStack(spacing: rowSpacing) {
                    ForEach(columns[index]) { model in
                        card(model)
                            .frame(width: columnWidth)
                    }
                }
                .frame(width: columnWidth)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LibraryView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.cantaContentWidth) private var contentWidth
    @State private var showSortMenu = false
    @State private var gridWidth: CGFloat = 1080
    @State private var pendingDeleteID: UUID?

    private struct GridWidthKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    var body: some View {
        libraryScroll
            .overlay(alignment: .bottom) {
                if store.isSelectingPins {
                    HStack(spacing: 0) {
                        Spacer(minLength: 20)
                        BatchActionBar()
                            .environment(store)
                        Spacer(minLength: 20)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(4)
                }
            }
            .background(Theme.paper)
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: store.isSelectingPins)
            .alert(T("Delete this pin?"), isPresented: Binding(
                get: { pendingDeleteID != nil },
                set: { if !$0 { pendingDeleteID = nil } }
            )) {
                Button(T("Delete"), role: .destructive) {
                    if let id = pendingDeleteID,
                       let pin = store.pins.first(where: { $0.id == id }) {
                        store.deletePin(pin)
                    }
                    pendingDeleteID = nil
                }
                Button(T("Cancel"), role: .cancel) { pendingDeleteID = nil }
            } message: {
                Text(T("The original image and its metadata will be removed from Canta."))
            }
    }

    private var libraryScroll: some View {
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

                    Group {
                        if store.visibleCards.isEmpty {
                            EmptyStateView(mode: store.pins.isEmpty ? .emptyLibrary : .noResults)
                                .padding(.horizontal, 34)
                                .padding(.top, 8)
                                .transition(.opacity)
                        } else {
                            grid
                        }
                    }
                    .animation(.snappy(duration: 0.30), value: store.searchText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onPreferenceChange(GridWidthKey.self) { width in
                guard width > 0, abs(width - gridWidth) > 0.5 else { return }
                gridWidth = width
            }
            .defaultScrollAnchor(.top)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        proxy.scrollTo("library-top", anchor: .top)
                    }
                }
            }
            .onChange(of: store.currentListIdentity) { _, _ in
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    proxy.scrollTo("library-top", anchor: .top)
                }
                if store.isSelectingPins {
                    store.clearSelection()
                }
            }
        }
    }

    private var grid: some View {
        // Prefer the exact main-column width. The gridWidth preference can
        // trail behind a live window resize, which made the masonry keep the
        // old column count for a moment (and could overflow into the sidebar).
        let measuredWidth = contentWidth > 0 ? contentWidth : gridWidth
        let available = max(measuredWidth - 68, 240)
        let columns = store.columns(forWidth: available)
        let spacing = store.cardColumnSpacing
        let columnWidth = MasonryComposer.columnWidth(
            availableWidth: available,
            columns: max(columns.count, 1),
            spacing: spacing
        )
        return MasonryColumns(
            columns: columns,
            columnWidth: columnWidth,
            spacing: spacing,
            rowSpacing: 28
        ) { model in
            PinCard(
                model: model,
                isSelected: store.selectedPinIDs.contains(model.id),
                isSelecting: store.isSelectingPins,
                actions: cardActions
            )
            .equatable()
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                removal: .opacity.combined(with: .scale(scale: 0.94))
            ))
        }
        .padding(.horizontal, 34)
        .padding(.bottom, 64)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: GridWidthKey.self,
                    value: max(proxy.size.width - 68, 0)
                )
            }
        )
    }

    private var cardActions: PinCardActions {
        PinCardActions(
            open: { store.openDetail(id: $0) },
            toggleSelection: { store.toggleSelection($0) },
            toggleFavorite: { store.toggleFavorite(id: $0) },
            copySnippet: { store.copyAgentSnippet(id: $0) },
            copyImage: { store.copyImage(id: $0) },
            moveToBoard: { store.movePin($0, toBoard: $1) },
            openOriginal: { store.openOriginal(id: $0) },
            reveal: { store.revealPin(id: $0) },
            openSource: { store.openSource(id: $0) },
            requestDelete: { pendingDeleteID = $0 },
            boardNames: { store.allBoardNames }
        )
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

            HStack(spacing: 8) {
                if !store.isSelectingPins {
                    selectButton
                }
                sortMenu
            }
            .padding(.bottom, 3)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { WindowZoom.toggle() }
        )
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
                store.filter = .all
            }
            FilterChip(title: T("Screenshots"), count: store.screenshotCount, isSelected: store.filter == .screenshots) {
                store.filter = .screenshots
            }
            FilterChip(title: T("Favorites"), count: store.favoriteCount, isSelected: store.filter == .favorites) {
                store.filter = .favorites
            }

            Rectangle()
                .fill(Theme.hairline)
                .frame(width: 1, height: 18)
                .padding(.horizontal, 5)

            if let board = store.selectedBoard {
                Button {
                    store.selectedBoard = nil
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
                .buttonStyle(PointerPlainButtonStyle())
                .help(T("Clear board filter"))
            } else {
                Text(TF("%ld shown", store.visibleCards.count))
                    .font(Theme.mono(10.5, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.leading, 2)
            }

            Spacer()
        }
    }

    private var selectButton: some View {
        Button {
            store.beginSelection()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 11, weight: .semibold))
                Text(T("Select"))
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(Theme.inkSecondary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(Theme.parchment))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PointerPlainButtonStyle())
        .focusEffectDisabled()
        .disabled(store.visibleCards.isEmpty)
        .opacity(store.visibleCards.isEmpty ? 0.45 : 1)
        .help(T("Select pins"))
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
        .buttonStyle(PointerPlainButtonStyle())
        .focusEffectDisabled()
        .popover(isPresented: $showSortMenu, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(PinSort.allCases) { sort in
                    Button {
                        store.sort = sort
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
                    .buttonStyle(PointerPlainButtonStyle())
                }
            }
            .padding(6)
            .frame(width: 196)
        }
    }
}