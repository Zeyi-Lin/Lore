import SwiftUI

/// Lazy Pinterest-style masonry: one `LazyVStack` per column. Columns are
/// balanced from aspect ratios (see `MasonryComposer`) over the prefix the
/// feed has loaded, so neither the window opening nor a resize measures the
/// whole library. Each column ends in a tail marker that asks the feed for the
/// next page when it comes into view.
struct MasonryColumns<Card: View>: View {
    let columns: [[PinCardModel]]
    let columnWidth: CGFloat
    let spacing: CGFloat
    let rowSpacing: CGFloat
    /// Changes every time the feed grows. Re-identifying the column tails is
    /// what lets a tail that is still on screen schedule the next page: the
    /// old sentinel is replaced, and the new one reports its own appearance.
    let tailGeneration: Int
    /// Called when the end of any column comes into the lazy stack's window,
    /// i.e. when the user is close to the bottom of the loaded feed.
    let onReachTail: () -> Void
    private let card: (PinCardModel) -> Card

    init(
        columns: [[PinCardModel]],
        columnWidth: CGFloat,
        spacing: CGFloat,
        rowSpacing: CGFloat,
        tailGeneration: Int,
        onReachTail: @escaping () -> Void,
        @ViewBuilder card: @escaping (PinCardModel) -> Card
    ) {
        self.columns = columns
        self.columnWidth = columnWidth
        self.spacing = spacing
        self.rowSpacing = rowSpacing
        self.tailGeneration = tailGeneration
        self.onReachTail = onReachTail
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

                    // Zero-visual-cost end marker: `LazyVStack` only builds it
                    // when it approaches the viewport, which is exactly the
                    // moment to append the next page.
                    Color.clear
                        .frame(height: 1)
                        .id("gallery-tail-\(index)-\(tailGeneration)")
                        .onAppear(perform: onReachTail)
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
    /// How many cards the incremental feed has loaded. The grid only splits
    /// and lays out this prefix, so a large library opens at the cost of its
    /// first page instead of its whole contents; scrolling grows the prefix
    /// (see `GalleryPaging`).
    @State private var loadedCards = GalleryPaging.firstPage
    /// One append is already queued on the next runloop. Column tails can
    /// appear together (they are balanced to end at the same height), and each
    /// of them would otherwise schedule its own page.
    @State private var loadScheduled = false
    /// The query `loadedCards` belongs to. A board or search change is
    /// reflected in the body before `onChange` gets to reset the feed, so the
    /// grid checks this on the way in and opens the new list at its first page
    /// instead of briefly laying out the previous list's depth.
    @State private var feedIdentity = ""
    /// Bumped whenever the query changes, so an append queued for the previous
    /// list cannot land on the new one.
    @State private var feedGeneration = 0

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

    /// Why the grid is empty: no pins at all, a board that has not been filled
    /// yet, or a search/filter that matched nothing. The middle case is new —
    /// boards can be created empty — and it deserves its own copy and actions
    /// rather than "No pins match".
    private var emptyMode: EmptyMode {
        if store.pins.isEmpty { return .emptyLibrary }
        let scoped = store.selectedBoard != nil
            && store.searchText.isEmpty
            && store.searchQuery.isEmpty
            && store.filter == .all
            && !store.hasColorFilter
            && store.section == .all
        return scoped ? .emptyBoard : .noResults
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
                            EmptyStateView(mode: emptyMode)
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
            .onAppear {
                applyGridWidth(columnWidth)
                feedIdentity = store.currentListIdentity
            }
            .onChange(of: columnWidth) { _, width in
                applyGridWidth(width)
            }
            .onChange(of: store.currentListIdentity) { _, identity in
                resetFeed(identity: identity)
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

    /// Width the masonry lays itself out at: the content column minus the
    /// gallery's horizontal gutter, never below the narrowest usable grid.
    private var availableGridWidth: CGFloat {
        max((gridWidth > 0 ? gridWidth : columnWidth) - 68, 240)
    }

    private var grid: some View {
        let available = availableGridWidth
        // A query change lands one body pass before `onChange` runs. Reading
        // the feed through the identity it was loaded for keeps that pass at
        // the first page instead of measuring the previous board's depth.
        let shown = store.currentListIdentity == feedIdentity ? loadedCards : GalleryPaging.firstPage
        let limit = min(shown, store.visibleCards.count)
        let columns = store.columns(forWidth: available, limit: limit)
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
            rowSpacing: 28,
            tailGeneration: limit,
            onReachTail: scheduleNextPage
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

    /// Starts the feed over at the first page. Called whenever the query
    /// changes, so a new board or search result opens small rather than
    /// inheriting the previous list's loaded depth.
    private func resetFeed(identity: String) {
        feedGeneration &+= 1
        loadScheduled = false
        feedIdentity = identity
        loadedCards = GalleryPaging.firstPage
    }

    /// Queues the next page when the end of a column reaches the lazy stack's
    /// window. The append is deferred one runloop: the tail is discovered
    /// during layout, and growing the grid in the middle of that pass is both
    /// undefined behaviour and a chance to append several pages at once when
    /// the balanced columns end together.
    private func scheduleNextPage() {
        guard store.currentListIdentity == feedIdentity else { return }
        guard loadedCards < store.visibleCards.count, !loadScheduled else { return }
        // A live resize is about to re-lay the grid anyway; wait for the
        // settle so a drag does not pay for an append it will replace.
        guard !widthSettle.pending else { return }
        loadScheduled = true
        let generation = feedGeneration
        DispatchQueue.main.async {
            loadScheduled = false
            guard generation == feedGeneration else { return }
            appendNextPage()
        }
    }

    /// Allows the grid to lay out one more page. The cards are already on
    /// disk, so "loading" is only "measure more of what the library has"; the
    /// batch lands below the fold, which keeps the scroll position and every
    /// visible card perfectly still.
    private func appendNextPage() {
        let total = store.visibleCards.count
        guard loadedCards < total else { return }
        let columns = MasonryComposer.columnCount(
            width: availableGridWidth,
            spacing: store.cardColumnSpacing
        )
        let next = GalleryPaging.nextLimit(current: loadedCards, total: total, columns: columns)
        guard next > loadedCards else { return }
        loadedCards = next
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
            beginDrag: { store.beginPinDrag($0) },
            dragCount: { id in
                if store.isSelectingPins, store.selectedPinIDs.contains(id) {
                    return store.selectedPinIDs.count
                }
                return 1
            }
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
        // Counts describe the current board (and section/search), not the whole
        // library, so the chips agree with the header and the grid.
        let counts = store.scopeCounts
        return HStack(spacing: 8) {
            FilterChip(title: T("All"), count: counts.all, isSelected: store.filter == .all) {
                store.filter = .all
            }
            FilterChip(title: T("Screenshots"), count: counts.screenshots, isSelected: store.filter == .screenshots) {
                store.filter = .screenshots
            }
            FilterChip(title: T("Favorites"), count: counts.favorites, isSelected: store.filter == .favorites) {
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