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
    /// Width the content column was given by the window. It is the only
    /// trustworthy source of width: measuring the grid would read back the
    /// grid's own (stale) width, because its minimum width is the sum of its
    /// columns.
    var columnWidth: CGFloat
    @State private var showSortMenu = false
    @State private var sortHovering = false
    /// Width the masonry lays itself out at. Held separately from the live
    /// column width so a window drag does not invalidate every card for every
    /// pixel; see `applyGridWidth`.
    @State private var gridWidth: CGFloat = 0
    @State private var pendingDeleteID: UUID?
    @State private var widthSettle = TaskSlot()

    /// Granularity while the window is being dragged. A drag only re-lays the
    /// gallery out once per step; the frames in between keep their cached
    /// sizes, and `scheduleWidthSettle` snaps to the exact width on release.
    private static let liveResizeQuantum: CGFloat = 16

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
                Text(T("The original image and its metadata will be removed from Lore."))
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
            .onAppear { applyGridWidth(columnWidth) }
            .onChange(of: columnWidth) { _, width in
                applyGridWidth(width)
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
        let measuredWidth = gridWidth > 0 ? gridWidth : columnWidth
        let available = max(measuredWidth - 68, 240)
        let columns = store.columns(forWidth: available)
        let spacing = store.cardColumnSpacing
        let cardWidth = MasonryComposer.columnWidth(
            availableWidth: available,
            columns: max(columns.count, 1),
            spacing: spacing
        )
        return MasonryColumns(
            columns: columns,
            columnWidth: cardWidth,
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
    }

    /// Coarsens the width the masonry reacts to while the window is moving,
    /// then snaps back to the exact width once it stops.
    ///
    /// A drag delivers a few dozen events per second; without this every one
    /// of them changes `columnWidth`, which invalidates the layout cache of
    /// every card in every column (the per-frame cost measured in
    /// `docs/GALLERY_RESIZE_PERF.md`). Quantising to 16 pt leaves the cached
    /// layout intact for the frames in between, so only one frame per step
    /// pays for the relayout. `widthSettle.pending` is what tells a drag from
    /// a settled relayout: it stays true while changes keep arriving.
    private func applyGridWidth(_ raw: CGFloat) {
        guard raw.isFinite, raw > 0 else { return }
        let quantum = widthSettle.pending ? Self.liveResizeQuantum : 1
        setGridWidth((raw / quantum).rounded(.down) * quantum)
        scheduleWidthSettle(raw)
    }

    private func setGridWidth(_ width: CGFloat) {
        guard abs(width - gridWidth) >= 0.5 else { return }
        Perf.gridRelayouts &+= 1
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) { gridWidth = width }
    }

    /// One relayout at the exact width, 140 ms after the last change. This
    /// removes the sub-quantum gap on the trailing edge and covers programmatic
    /// resizes (the title-bar zoom animation), which never look like a drag.
    private func scheduleWidthSettle(_ raw: CGFloat) {
        widthSettle.schedule(delay: 140_000_000) {
            setGridWidth(raw)
        }
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
            prefetchDetail: { store.prefetchDetail(id: $0) },
            boardNames: { store.allBoardNames },
            beginDrag: { store.beginPinDrag($0) }
        )
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
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
            ColorFilterControl()

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
            .background(Capsule().fill(sortHovering ? Theme.parchmentDeep : Theme.parchment))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PointerPlainButtonStyle())
        .focusEffectDisabled()
        .onHover { sortHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: sortHovering)
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
                        .menuRowHover(isSelected: store.sort == sort)
                    }
                    .buttonStyle(PointerPlainButtonStyle())
                }
            }
            .padding(6)
            .frame(width: 196)
        }
    }
}