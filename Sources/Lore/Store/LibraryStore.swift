import SwiftUI
import AppKit
import Observation
import LoreAgentKit

/// What the current sidebar/gallery drag carries. Kept in memory instead of the
/// pasteboard so drop delegates can decide synchronously what an affordance
/// means.
enum DragPayload: Equatable {
    case pins([UUID])
    case board(parentKey: String, key: String)
}

@MainActor
@Observable
final class LibraryStore {
    let root: URL

    private(set) var pins: [Pin] = []
    var section: LibrarySection = .all
    var selectedBoard: String?
    private(set) var searchText: String = ""
    private(set) var searchQuery: String = ""
    var filter: GalleryFilter = .all
    var sort: PinSort = .recent
    var colorFamilyFilter: LoreColorFamily?
    var toneFilter: LoreColorTone?
    var selectedPinID: UUID?
    var isSelectingPins = false
    var selectedPinIDs: Set<UUID> = []
    var capturePresented = false
    var boardManagerPresented = false
    /// The "paste SVG code" sheet. Kept next to the capture sheet because both
    /// are modal capture surfaces.
    var svgPastePresented = false
    var isImporting = false
    var toast: ToastMessage?
    var startupError: String?

    private(set) var agentStatus: AgentServerStatus = .stopped
    private(set) var agentPort: UInt16
    private(set) var agentAPIEnabled: Bool
    /// Gates PATCH /api/v1/pins/{id}; the app's own editor is unaffected.
    private(set) var allowsAgentMetadataEdits: Bool

    private var storedDefaultBoard: String
    var defaultBoard: String {
        get { storedDefaultBoard }
        set {
            storedDefaultBoard = newValue
            UserDefaults.standard.set(newValue, forKey: Keys.defaultBoard)
        }
    }

    private enum Keys {
        static let agentPort = "lore.agent.port"
        static let agentEnabled = "lore.agent.enabled"
        static let agentMetadataEdits = "lore.agent.metadataEdits"
        static let defaultBoard = "lore.defaultBoard"
    }

    @ObservationIgnored private var agentServer: LoreAgentServer?
    @ObservationIgnored private var agentGeneration = 0
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    // Derived-data core. `snapshot` is replaced on every data mutation;
    // `projection` memoises queries against it.
    @ObservationIgnored private let writer: LibraryWriter
    @ObservationIgnored private(set) var snapshot: LibrarySnapshot
    @ObservationIgnored private let projection: GalleryProjection
    private var revision: UInt64
    @ObservationIgnored private var columnsMemo: (key: ColumnsKey, columns: [[PinCardModel]])?
    /// Sidebar ordering, persisted in `<library>/boards.json`. `library.json`
    /// keeps its format; see `BoardOrder`.
    private(set) var boardOrder: BoardOrder
    @ObservationIgnored private var orderRevision = 0
    @ObservationIgnored private var boardTreeMemo: (revision: UInt64, orderRevision: Int, tree: [BoardNode])?
    /// Set when a drag starts, cleared when it ends. Not observed: it changes
    /// on every drag and no view should re-render because of it.
    @ObservationIgnored var activeDragPayload: DragPayload?
    /// Observed by the sidebar so its footer can turn into a trash target as
    /// soon as a card drag starts, rather than only once the pointer reaches it.
    private(set) var isDraggingPins = false
    /// Guards delayed drag cleanup: a mouse-up from drag A must not clear the
    /// payload of drag B that started immediately afterwards.
    private(set) var dragSession = 0
    @ObservationIgnored private var recentCountMemo: (revision: UInt64, value: Int)?
    @ObservationIgnored private var didStartMaintenance = false
    @ObservationIgnored private var hasPendingWrite = false
    @ObservationIgnored private var searchDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var searchGeneration = 0

    /// Only the column *count* participates: the balance between columns is a
    /// greedy walk over aspect ratios, so it does not need to be recomputed
    /// for every pixel of a window resize. Keying by width used to turn every
    /// resize event into an O(N) split plus a brand-new `columns` array, which
    /// also forced `ForEach` to diff N identities per frame.
    private struct ColumnsKey: Hashable {
        var query: GalleryQuery
        var columns: Int
        /// How many cards the gallery asked for. The feed appends a page at a
        /// time, so the same query can be split at several prefixes; keying on
        /// the shown count means a growth step is one recompute and every
        /// other body pass in between is a cache hit.
        var shown: Int
    }


    init(root: URL = LorePaths.dataRoot) {
        let resolvedRoot: URL
        if let debugHome = UserDefaults.standard.string(forKey: "lore.debugHome"), !debugHome.isEmpty {
            resolvedRoot = URL(fileURLWithPath: debugHome, isDirectory: true)
        } else {
            resolvedRoot = root
        }
        self.root = resolvedRoot

        let defaults = UserDefaults.standard
        let storedPort = defaults.integer(forKey: Keys.agentPort)
        self.agentPort = UInt16(clamping: storedPort > 1024 ? storedPort : 4242)
        if defaults.object(forKey: Keys.agentEnabled) == nil {
            self.agentAPIEnabled = true
        } else {
            self.agentAPIEnabled = defaults.bool(forKey: Keys.agentEnabled)
        }
        if defaults.object(forKey: Keys.agentMetadataEdits) == nil {
            self.allowsAgentMetadataEdits = true
        } else {
            self.allowsAgentMetadataEdits = defaults.bool(forKey: Keys.agentMetadataEdits)
        }
        self.storedDefaultBoard = defaults.string(forKey: Keys.defaultBoard) ?? "Unsorted"

        let writer = LibraryWriter(
            root: resolvedRoot,
            fileURL: LorePaths.libraryFile(root: resolvedRoot)
        )
        self.writer = writer

        var library = LoreLibrary()
        var loadError: String?
        do {
            // Single decode: seeding and loading share one read of library.json.
            library = try SeedLoader.loadOrInstall(root: resolvedRoot)
        } catch {
            loadError = TF("Lore couldn't read your library. New pins will start a fresh one. (%@)", error.localizedDescription)
        }

        self.revision = 1
        self.boardOrder = BoardOrderFile.load(root: resolvedRoot)
        self.pins = library.pins
        let snapshot = LibrarySnapshot(revision: 1, pins: library.pins)
        self.snapshot = snapshot
        self.projection = GalleryProjection(snapshot: snapshot, root: resolvedRoot)
        self.startupError = loadError

        writer.onError = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.showToast(TF("Couldn't save the library: %@", message), icon: "exclamationmark.triangle")
            }
        }
    }

    // MARK: - Derived collections

    private var currentQuery: GalleryQuery {
        GalleryQuery(
            sectionRaw: section.rawValue,
            board: selectedBoard?.trimmed.lowercased(),
            filterRaw: filter.rawValue,
            sortRaw: sort.rawValue,
            needle: searchQuery,
            colorRaw: colorFamilyFilter?.rawValue,
            toneRaw: toneFilter?.rawValue,
            languageRaw: LanguageManager.shared.resolved.rawValue,
            revision: revision
        )
    }

    /// The pins visible for the current query. Memoised: the five reads that
    /// used to happen per `LibraryView` body now cost a dictionary lookup.
    var filteredPins: [Pin] { projection.visiblePins(for: currentQuery) }

    /// Value projections consumed by the lazy grid; also memoised.
    var visibleCards: [PinCardModel] { projection.cards(for: currentQuery) }

    var selectedPin: Pin? {
        guard let selectedPinID else { return nil }
        _ = revision
        guard let index = snapshot.indexByID[selectedPinID] else { return nil }
        return pins[index]
    }

    var selectedPins: [Pin] {
        filteredPins.filter { selectedPinIDs.contains($0.id) }
    }

    var allVisibleSelected: Bool {
        let visible = filteredPins
        return !visible.isEmpty && visible.allSatisfy { selectedPinIDs.contains($0.id) }
    }

    var selectedPinsAreFavorites: Bool {
        let chosen = selectedPins
        return !chosen.isEmpty && chosen.allSatisfy(\.isFavorite)
    }

    var boardSummaries: [BoardSummary] {
        _ = revision
        return projection.boardSummaries()
    }

    /// Hierarchical board rows for the sidebar: `Linear/Settings` boards fold
    /// into a `Linear` group node.
    var boardTree: [BoardNode] {
        _ = revision
        let order = boardOrder.order
        if let memo = boardTreeMemo, memo.revision == revision, memo.orderRevision == orderRevision {
            return memo.tree
        }
        let tree = BoardTreeBuilder.build(boardCounts: snapshot.boardCounts, order: order)
        boardTreeMemo = (revision, orderRevision, tree)
        return tree
    }

    var allBoardNames: [String] {
        _ = revision
        return projection.allBoardNames()
    }

    var favoriteCount: Int {
        _ = revision
        return snapshot.favoriteCount
    }

    var screenshotCount: Int {
        _ = revision
        return snapshot.screenshotCount
    }

    var recentCount: Int {
        _ = revision
        if let recentCountMemo, recentCountMemo.revision == revision { return recentCountMemo.value }
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        let value = pins.filter { $0.createdAt >= cutoff }.count
        recentCountMemo = (revision, value)
        return value
    }

    var allTags: [(name: String, count: Int)] {
        _ = revision
        return projection.allTags()
    }

    /// Multi-membership hue counts. A teal-and-yellow reference counts in both,
    /// and `multicolor` counts pins with three or more named hues.
    var colorFamilyCounts: [LoreColorFamily: Int] {
        _ = revision
        return snapshot.colorFamilyCounts
    }

    var toneCounts: [LoreColorTone: Int] {
        _ = revision
        return snapshot.toneCounts
    }

    var hasColorFilter: Bool {
        colorFamilyFilter != nil || toneFilter != nil
    }

    func colorFamilyCount(_ family: LoreColorFamily) -> Int {
        colorFamilyCounts[family] ?? 0
    }

    func toneCount(_ tone: LoreColorTone) -> Int {
        toneCounts[tone] ?? 0
    }

    /// Clicking a family in the gallery filter toggles it; `nil` clears.
    func setColorFamilyFilter(_ family: LoreColorFamily?) {
        colorFamilyFilter = family
    }

    func setToneFilter(_ tone: LoreColorTone?) {
        toneFilter = tone
    }

    func clearColorFilters() {
        colorFamilyFilter = nil
        toneFilter = nil
    }

    /// Used by the detail view's colour chips to jump straight into a facet.
    func applyColorFilter(family: LoreColorFamily? = nil, tone: LoreColorTone? = nil) {
        if let family { colorFamilyFilter = family }
        if let tone { toneFilter = tone }
    }

    var pageTitle: String {
        switch section {
        case .all:
            return selectedBoard.map(localizedBoard) ?? T("All pins")
        case .favorites:
            return T("Favorites")
        case .recent:
            return T("Recent captures")
        case .agent:
            return T("Agent access")
        }
    }

    var pageSubtitle: String {
        switch section {
        case .all:
            if let selectedBoard {
                let count = boardSummaries.first(where: { $0.name == selectedBoard })?.count ?? 0
                return TF("%ld pins curated in this board", count)
            }
            return TF("%ld pins · a small, searchable visual memory for building interfaces", pins.count)
        case .favorites:
            return TF("%ld hand-picked references", favoriteCount)
        case .recent:
            return TF("%ld pins added in the last 30 days", recentCount)
        case .agent:
            return T("Give your coding agent eyes for good design")
        }
    }

    var currentListIdentity: String {
        "\(section.rawValue)|\(selectedBoard ?? "")|\(filter.rawValue)|\(sort.rawValue)|\(colorFamilyFilter?.rawValue ?? "")|\(toneFilter?.rawValue ?? "")|\(searchQuery)"
    }

    var dataFolderPath: String { root.path }
    var libraryFileURL: URL { LorePaths.libraryFile(root: root) }

    func pin(id: UUID) -> Pin? { snapshot.pin(id: id) }

    func representativePin(forBoard board: String) -> Pin? {
        _ = revision
        return projection.representativePin(forBoard: board)
    }

    func originalURL(for pin: Pin) -> URL { root.appendingPathComponent(pin.image) }

    /// No `fileExists` here any more: a missing thumbnail makes the loader fall
    /// back to the next candidate, so the file system is not hit from `body`.
    func thumbnailURL(for pin: Pin) -> URL {
        if let thumbnail = pin.thumbnail {
            return root.appendingPathComponent(thumbnail)
        }
        return originalURL(for: pin)
    }

    /// Grid candidates: 640 px derivative → 1200 px thumbnail → original.
    func cardImageCandidates(for pin: Pin) -> [String] {
        let rootPath = root.path
        var candidates: [String] = []
        candidates.reserveCapacity(3)
        candidates.append(rootPath + "/Cards/" + pin.id.uuidString + ".jpg")
        if let thumbnail = pin.thumbnail {
            candidates.append(rootPath + "/" + thumbnail)
        }
        candidates.append(rootPath + "/" + pin.image)
        return candidates
    }

    /// Detail candidates: the original first so a large pane can decode at its
    /// full display size, then the 1200 px thumbnail as a cheap fallback.
    func detailImageCandidates(for pin: Pin) -> [String] {
        var candidates: [String] = []
        candidates.append(root.path + "/" + pin.image)
        if let thumbnail = pin.thumbnail {
            candidates.append(root.path + "/" + thumbnail)
        }
        return candidates
    }

    /// Native-size original, used only by the large-image mode.
    func largeImageCandidates(for pin: Pin) -> [String] {
        [root.path + "/" + pin.image]
    }

    /// Column partitions for the masonry grid, balanced from aspect ratios
    /// alone. Cached per query + column count + shown cardinality, so a width
    /// change inside the same column band reuses the partition instead of
    /// rebalancing N cards, and the incremental feed only pays for the page it
    /// just appended.
    ///
    /// `limit` is the number of cards the gallery has loaded so far. The split
    /// is greedy over the prefix, so appending a page never moves a card that
    /// was already placed: the first `limit` assignments are the same on every
    /// growth step.
    func columns(
        forWidth width: CGFloat,
        spacing: CGFloat = 20,
        rowSpacing: CGFloat = 28,
        limit: Int = .max
    ) -> [[PinCardModel]] {
        let count = MasonryComposer.columnCount(width: width, spacing: spacing)
        let query = currentQuery
        let models = projection.cards(for: query)
        let shown = limit >= models.count ? models : Array(models.prefix(max(0, limit)))
        let key = ColumnsKey(query: query, columns: count, shown: shown.count)
        if let columnsMemo, columnsMemo.key == key { return columnsMemo.columns }
        let columns = MasonryComposer.split(
            models: shown,
            columns: count,
            availableWidth: width,
            spacing: spacing,
            rowSpacing: rowSpacing
        )
        self.columnsMemo = (key, columns)
        return columns
    }

    /// Rows are the same height for every card because the title reserves two
    /// lines; used by the grid's width math.
    var cardColumnSpacing: CGFloat { 20 }

    // MARK: - Search

    /// Updates the field immediately; the query is applied on a short debounce
    /// for larger libraries so each keystroke does not rescan the library.
    func updateSearchText(_ value: String) {
        searchText = value
        searchGeneration &+= 1
        let generation = searchGeneration
        searchDebounceTask?.cancel()

        let needle = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .precomposedStringWithCanonicalMapping
        guard !needle.isEmpty else {
            applySearchQuery("")
            return
        }
        guard pins.count > 4_000 else {
            applySearchQuery(needle)
            return
        }
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 40_000_000)
            guard let self, !Task.isCancelled, self.searchGeneration == generation else { return }
            self.applySearchQuery(needle)
        }
    }

    func clearSearch() {
        searchGeneration &+= 1
        searchDebounceTask?.cancel()
        searchText = ""
        applySearchQuery("")
    }

    private func applySearchQuery(_ needle: String) {
        guard searchQuery != needle else { return }
        searchQuery = needle
    }

    // MARK: - Navigation

    func select(section newSection: LibrarySection) {
        endSelection()
        section = newSection
        if newSection != .all || selectedBoard != nil {
            selectedBoard = nil
        }
        if newSection == .favorites { filter = .all }
    }

    func select(board: String) {
        endSelection()
        // Board switching should be immediate: no animated upward scroll or
        // card reflow. Search remains the only gallery change we animate.
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            section = .all
            selectedBoard = board
            filter = .all
        }
    }

    func openDetail(_ pin: Pin) {
        if isSelectingPins { endSelection() }
        selectedPinID = pin.id
        prefetchNeighbors(around: pin)
    }

    func openDetail(id: UUID) {
        guard let pin = pin(id: id) else { return }
        openDetail(pin)
    }

    func dismissDetail() {
        // Leaving the detail is a natural save point for debounced edits.
        flushPersistence()
        selectedPinID = nil
    }

    func showAdjacentPin(offset: Int) {
        let list = filteredPins
        guard !list.isEmpty else { return }
        let currentIndex = list.firstIndex(where: { $0.id == selectedPinID }) ?? -1
        let nextIndex = min(max(currentIndex + offset, 0), list.count - 1)
        guard nextIndex != currentIndex else { return }
        let next = list[nextIndex]
        selectedPinID = next.id
        prefetchNeighbors(around: next)
    }

    /// Re-reads the library after an external writer (the Agent API) changes it.
    /// Decoding happens off the main actor; only the swap is done on main.
    func reloadFromDisk(announceNewPins: Bool = true) {
        let url = LorePaths.libraryFile(root: root)
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let data = try? Data(contentsOf: url),
                  let library = try? LoreJSON.makeDecoder().decode(LoreLibrary.self, from: data) else {
                return
            }
            await MainActor.run { [weak self] in
                self?.applyExternalReload(library, announceNewPins: announceNewPins)
            }
        }
    }

    private func applyExternalReload(_ library: LoreLibrary, announceNewPins: Bool) {
        let existingIDs = Set(pins.map(\.id))
        let added = library.pins.filter { !existingIDs.contains($0.id) }
        pins = library.pins
        refreshSnapshot()
        let validIDs = Set(pins.map(\.id))
        if let selectedPinID, !validIDs.contains(selectedPinID) {
            self.selectedPinID = nil
        }
        selectedPinIDs.formIntersection(validIDs)
        if !added.isEmpty {
            let root = self.root
            Task.detached(priority: .utility) {
                let fm = FileManager.default
                for pin in added {
                    var source = root.appendingPathComponent(pin.image)
                    if let thumbnail = pin.thumbnail {
                        let candidate = root.appendingPathComponent(thumbnail)
                        if fm.fileExists(atPath: candidate.path) { source = candidate }
                    }
                    _ = ImageProcessor.writeCardThumbnail(sourcePath: source.path, root: root, id: pin.id)
                }
            }
            // Older agents write no colour or animation analysis; classify
            // those pins in the background without blocking the reload.
            backfillColorProfiles(added)
            backfillAnimationMetadata(added)
        }
        if announceNewPins, !added.isEmpty {
            let message = added.count == 1
                ? TF("An agent added %ld pin", added.count)
                : TF("An agent added %ld pins", added.count)
            showToast(message, icon: "sparkles")
        }
    }

    // MARK: - Batch selection

    func beginSelection() {
        withAnimation(.snappy(duration: 0.24)) {
            isSelectingPins = true
            selectedPinIDs.removeAll()
            selectedPinID = nil
        }
    }

    func endSelection() {
        guard isSelectingPins || !selectedPinIDs.isEmpty else { return }
        withAnimation(.snappy(duration: 0.24)) {
            isSelectingPins = false
            selectedPinIDs.removeAll()
        }
    }

    func toggleSelection(_ pinID: UUID) {
        withAnimation(.snappy(duration: 0.18)) {
            if selectedPinIDs.contains(pinID) {
                selectedPinIDs.remove(pinID)
            } else {
                selectedPinIDs.insert(pinID)
            }
        }
    }

    func selectAllVisible() {
        withAnimation(.snappy(duration: 0.2)) {
            selectedPinIDs = Set(filteredPins.map(\.id))
        }
    }

    func clearSelection() {
        withAnimation(.snappy(duration: 0.18)) {
            selectedPinIDs.removeAll()
        }
    }

    func setFavorite(_ favorite: Bool, for pinIDs: Set<UUID>) {
        var changed = 0
        for index in pins.indices where pinIDs.contains(pins[index].id) {
            if pins[index].isFavorite != favorite {
                pins[index].isFavorite = favorite
                pins[index].updatedAt = Date()
                changed += 1
            }
        }
        guard changed > 0 else {
            showToast(favorite ? T("Saved to favorites") : T("Removed from favorites"), icon: favorite ? "heart.fill" : "heart")
            return
        }
        refreshSnapshot()
        persist(debounce: 0.25)
        let message = favorite
            ? TF("%ld pins added to favorites", changed)
            : TF("%ld pins removed from favorites", changed)
        showToast(message, icon: favorite ? "heart.fill" : "heart")
    }

    func toggleSelectedFavorites() {
        guard !selectedPins.isEmpty else { return }
        setFavorite(!selectedPinsAreFavorites, for: selectedPinIDs)
    }

    func moveSelectedPins(toBoard board: String) {
        let ids = selectedPinIDs
        guard !ids.isEmpty else { return }
        movePins(Array(ids), toBoard: board)
        endSelection()
    }

    func deleteSelectedPins() {
        let ids = selectedPinIDs
        let targets = pins.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }
        let fm = FileManager.default
        for pin in targets {
            try? fm.removeItem(at: root.appendingPathComponent(pin.image))
            if let thumbnail = pin.thumbnail {
                try? fm.removeItem(at: root.appendingPathComponent(thumbnail))
            }
            try? fm.removeItem(at: LorePaths.cardsDirectory(root: root)
                .appendingPathComponent("\(pin.id.uuidString).jpg"))
        }
        pins.removeAll { ids.contains($0.id) }
        if let selectedPinID, ids.contains(selectedPinID) { self.selectedPinID = nil }
        refreshSnapshot()
        persist(debounce: 0.1)
        showToast(TF("%ld pins deleted", targets.count), icon: "trash")
        endSelection()
    }

    /// Deletes exactly the pins carried by a drag, leaving any other selection
    /// untouched unless everything selected was removed.
    func deletePins(ids: [UUID]) {
        let targets = pins.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }
        let fm = FileManager.default
        for pin in targets {
            try? fm.removeItem(at: root.appendingPathComponent(pin.image))
            if let thumbnail = pin.thumbnail {
                try? fm.removeItem(at: root.appendingPathComponent(thumbnail))
            }
            try? fm.removeItem(at: LorePaths.cardsDirectory(root: root)
                .appendingPathComponent("\(pin.id.uuidString).jpg"))
        }
        pins.removeAll { ids.contains($0.id) }
        selectedPinIDs.subtract(ids)
        if let selectedPinID, ids.contains(selectedPinID) { self.selectedPinID = nil }
        refreshSnapshot()
        persist(debounce: 0.1)
        showToast(targets.count == 1 ? T("Pin deleted") : TF("%ld pins deleted", targets.count),
                  icon: "trash")
        if isSelectingPins, selectedPinIDs.isEmpty {
            endSelection()
        }
    }

    func copySelectedAgentContext() {
        let chosen = selectedPins
        guard !chosen.isEmpty else { return }
        copyText(
            agentContext(includePins: chosen),
            message: TF("%ld pins copied as agent context", chosen.count),
            icon: "sparkles"
        )
    }

    // MARK: - Mutations

    func updatePin(id: UUID, _ mutate: (inout Pin) -> Void) {
        guard let index = snapshot.indexByID[id] else { return }
        var pin = pins[index]
        mutate(&pin)
        pin.updatedAt = Date()
        pins[index] = pin
        refreshSnapshot()
        persist(debounce: 0.45)
    }

    func toggleFavorite(_ pin: Pin) {
        updatePin(id: pin.id) { $0.isFavorite.toggle() }
        let favorite = self.pin(id: pin.id)?.isFavorite ?? false
        showToast(favorite ? T("Saved to favorites") : T("Removed from favorites"), icon: favorite ? "heart.fill" : "heart")
    }

    func addTag(_ rawTag: String, to pinID: UUID) {
        var tag = rawTag.trimmed.lowercased()
        if tag.hasPrefix("#") { tag.removeFirst() }
        guard !tag.isEmpty else { return }
        updatePin(id: pinID) { pin in
            if !pin.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                pin.tags.append(tag)
            }
        }
    }

    func removeTag(_ tag: String, from pinID: UUID) {
        updatePin(id: pinID) { $0.tags.removeAll { $0 == tag } }
    }

    func movePin(_ pinID: UUID, toBoard board: String) {
        let clean = board.trimmed.nilIfEmpty ?? "Unsorted"
        updatePin(id: pinID) { $0.board = clean }
    }

    /// Moves a whole drag in one pass: one snapshot rebuild and one debounced
    /// write, no matter how many pins were dropped.
    func movePins(_ pinIDs: [UUID], toBoard board: String) {
        let clean = board.trimmed.nilIfEmpty ?? "Unsorted"
        let targets = Set(pinIDs)
        var changed = 0
        for index in pins.indices where targets.contains(pins[index].id) {
            guard pins[index].board != clean else { continue }
            pins[index].board = clean
            pins[index].updatedAt = Date()
            changed += 1
        }
        guard changed > 0 else { return }
        refreshSnapshot()
        persist(debounce: 0.3)
        let label = localizedBoard(clean)
        showToast(changed == 1 ? TF("Moved to %@", label) : TF("%ld pins moved to %@", changed, label),
                  icon: "tray.and.arrow.down.fill")
    }

    // MARK: - Sidebar drags

    /// Starts a pin drag. Dragging a selected card moves the whole selection,
    /// which is what the selection mode implies. Returns the pasteboard marker
    /// for the drag preview; the payload itself stays in `activeDragPayload`.
    func beginPinDrag(_ pinID: UUID) -> String {
        let ids: [UUID]
        if isSelectingPins, selectedPinIDs.contains(pinID) {
            ids = Array(selectedPinIDs)
        } else {
            ids = [pinID]
        }
        dragSession += 1
        activeDragPayload = .pins(ids)
        isDraggingPins = !ids.isEmpty
        return "lore.pins:\(ids.count)"
    }

    func beginBoardDrag(parentKey: String, key: String) -> String {
        dragSession += 1
        activeDragPayload = .board(parentKey: parentKey, key: key)
        isDraggingPins = false
        return "lore.board:\(key)"
    }

    /// `session` is supplied by the delayed mouse-up cleanup so an old drag
    /// cannot cancel a newer one started in the meantime.
    func finishDrag(session: Int? = nil) {
        if let session, session != dragSession { return }
        activeDragPayload = nil
        isDraggingPins = false
    }

    /// Reorders one sidebar row inside its own group. `key`, `target` and their
    /// siblings are lowercased path keys (see `BoardNode.id`).
    func moveBoardNode(_ key: String, in parentKey: String, relativeTo targetKey: String, after: Bool) {
        let siblings = childKeys(ofParentKey: parentKey)
        var order = boardOrder
        guard order.move(key, in: parentKey, relativeTo: targetKey, after: after, current: siblings) else {
            return
        }
        applyBoardOrder(order)
    }

    private func childKeys(ofParentKey parentKey: String) -> [String] {
        guard !parentKey.isEmpty else { return boardTree.map(\.id) }
        func find(_ nodes: [BoardNode]) -> BoardNode? {
            for node in nodes {
                if node.id == parentKey { return node }
                if let match = find(node.children) { return match }
            }
            return nil
        }
        return find(boardTree)?.children.map(\.id) ?? []
    }

    private func applyBoardOrder(_ order: BoardOrder) {
        guard order != boardOrder else { return }
        boardOrder = order
        orderRevision &+= 1
        BoardOrderFile.save(order, root: root)
    }


    // MARK: - Board management

    /// Renames a board across every pin. A path rename carries the whole
    /// subtree with it (`Studio/Home` under `Studio` becomes `Suite/Home`),
    /// and renaming onto an existing board merges the two. Returns false when
    /// the name is empty or would nest a board under itself.
    @discardableResult
    func renameBoard(_ rawName: String, to rawNewName: String) -> Bool {
        let oldParts = BoardPath.segments(rawName)
        let newParts = BoardPath.segments(rawNewName)
        guard !oldParts.isEmpty, !newParts.isEmpty else { return false }
        guard BoardPath.key(oldParts.joined(separator: "/")) != "unsorted" else { return false }
        guard !BoardPath.isDescendant(newParts.joined(separator: "/"),
                                      of: oldParts.joined(separator: "/")) else { return false }

        let oldKey = BoardPath.key(oldParts.joined(separator: "/"))
        let newKey = BoardPath.key(newParts.joined(separator: "/"))
        let targetExists = newKey != oldKey && boardPathExists(newKey)

        var changed = 0
        for index in pins.indices {
            guard let rebuilt = BoardPath.replacingPrefix(
                in: pins[index].board, old: oldParts, new: newParts
            ) else { continue }
            guard rebuilt != pins[index].board else { continue }
            pins[index].board = rebuilt
            pins[index].updatedAt = Date()
            changed += 1
        }

        if let selected = selectedBoard,
           let moved = BoardPath.replacingPrefix(in: selected, old: oldParts, new: newParts) {
            selectedBoard = moved
        }
        if let moved = BoardPath.replacingPrefix(in: defaultBoard, old: oldParts, new: newParts) {
            defaultBoard = moved
        }

        guard changed > 0 else { return true }
        // Keep a reordered board where the user put it instead of dropping it
        // back to the alphabetical slot.
        var order = boardOrder
        order.remap(old: oldKey, new: newKey)
        applyBoardOrder(order)
        refreshSnapshot()
        persist(debounce: 0.2)
        let display = localizedBoard(newParts.joined(separator: "/"))
        showToast(
            targetExists ? TF("Board merged into %@.", display) : TF("Board renamed to %@.", display),
            icon: "folder"
        )
        return true
    }

    /// Removes a board (or a whole `/` group) and re-files its pins under
    /// Unsorted. Images and metadata are kept; only the board assignment
    /// changes. "Unsorted" itself is the fallback inbox and cannot be removed.
    func deleteBoard(_ rawName: String) {
        let parts = BoardPath.segments(rawName)
        guard !parts.isEmpty else { return }
        guard BoardPath.key(parts.joined(separator: "/")) != "unsorted" else { return }

        var moved = 0
        for index in pins.indices {
            guard BoardPath.segmentsHasPrefix(BoardPath.segments(pins[index].board), parts) else { continue }
            pins[index].board = "Unsorted"
            pins[index].updatedAt = Date()
            moved += 1
        }

        if let selected = selectedBoard,
           BoardPath.segmentsHasPrefix(BoardPath.segments(selected), parts) {
            selectedBoard = nil
            section = .all
        }
        if BoardPath.segmentsHasPrefix(BoardPath.segments(defaultBoard), parts) {
            defaultBoard = "Unsorted"
        }

        guard moved > 0 else { return }
        var order = boardOrder
        order.removeSubtree(BoardPath.key(parts.joined(separator: "/")))
        applyBoardOrder(order)
        refreshSnapshot()
        persist(debounce: 0.2)
        showToast(TF("%ld pins moved to Unsorted.", moved), icon: "tray")
    }

    /// True when any pin sits on this path or on one of its descendants.
    private func boardPathExists(_ key: String) -> Bool {
        for pin in pins {
            let parts = BoardPath.segments(pin.board)
            for depth in 1...max(parts.count, 1) {
                if parts.prefix(depth).joined(separator: "/").lowercased() == key {
                    return true
                }
            }
        }
        return false
    }

    func deletePin(_ pin: Pin) {
        let fm = FileManager.default
        try? fm.removeItem(at: root.appendingPathComponent(pin.image))
        if let thumbnail = pin.thumbnail {
            try? fm.removeItem(at: root.appendingPathComponent(thumbnail))
        }
        try? fm.removeItem(at: LorePaths.cardsDirectory(root: root)
            .appendingPathComponent("\(pin.id.uuidString).jpg"))
        pins.removeAll { $0.id == pin.id }
        selectedPinIDs.remove(pin.id)
        if selectedPinID == pin.id { selectedPinID = nil }
        refreshSnapshot()
        persist(debounce: 0.1)
        showToast(T("Pin deleted"), icon: "trash")
    }

    // MARK: - Import

    func addFiles(_ urls: [URL], sourceLabel: String = "Imported", preferredTitle: String? = nil, board explicitBoard: String? = nil) async {
        guard !urls.isEmpty else { return }
        guard !isImporting else {
            showToast(T("Lore is still importing"), icon: "hourglass")
            return
        }

        isImporting = true
        defer { isImporting = false }

        let targetBoard = (explicitBoard ?? selectedBoard ?? defaultBoard).trimmed.nilIfEmpty ?? "Unsorted"
        var created: [Pin] = []
        var failure: String?

        for (index, url) in urls.enumerated() {
            let id = UUID()
            do {
                let processed = try await Task.detached(priority: .userInitiated) {
                    try ImageProcessor.process(fileURL: url, root: self.root, id: id)
                }.value

                let baseTitle = urls.count == 1 ? (preferredTitle ?? Self.defaultTitle(for: url)) : Self.defaultTitle(for: url)
                let pin = Pin(
                    id: id,
                    title: index == 0 && preferredTitle != nil ? preferredTitle! : baseTitle,
                    note: "",
                    image: processed.image,
                    thumbnail: processed.thumbnail,
                    width: processed.width,
                    height: processed.height,
                    fileSize: processed.fileSize,
                    createdAt: Date(),
                    updatedAt: Date(),
                    tags: [],
                    board: targetBoard,
                    sourceURL: nil,
                    sourceLabel: sourceLabel,
                    colors: processed.colors,
                    isFavorite: false,
                    kind: processed.kind,
                    colorFamilies: processed.colorFamilies,
                    colorTone: processed.colorTone,
                    isAnimated: processed.isAnimated,
                    frameCount: processed.frameCount
                )
                created.append(pin)
            } catch {
                failure = error.localizedDescription
            }
        }

        guard !created.isEmpty else {
            showToast(failure ?? T("Couldn't add that image"), icon: "exclamationmark.triangle")
            return
        }

        pins.append(contentsOf: created)
        refreshSnapshot()
        persist(debounce: 0.05)
        revealFreshlyAdded(board: targetBoard)

        let localizedTargetBoard = localizedBoard(targetBoard)
        if let failure {
            let countLabel = created.count == 1 ? TF("%ld pin", created.count) : TF("%ld pins", created.count)
            showToast(TF("%@ added · %@", countLabel, failure), icon: "exclamationmark.circle")
        } else if created.count == 1 {
            showToast(TF("%ld pin added to %@", created.count, localizedTargetBoard), icon: "pin.fill")
        } else {
            showToast(TF("%ld pins added to %@", created.count, localizedTargetBoard), icon: "pin.fill")
        }
    }

    func addImageData(_ data: Data, preferredExtension: String? = nil, sourceLabel: String = "Clipboard", title: String? = nil, board: String? = nil) async {
        // `image/svg+xml` payloads arrive through the same drop/paste channels
        // as bitmaps; route them to the vector importer so the pin gets the
        // right kind, badge and message.
        if preferredExtension?.caseInsensitiveCompare("svg") == .orderedSame || SVGRasterizer.isSVG(data: data) {
            await addSVGData(data, title: title, sourceLabel: sourceLabel, board: board)
            return
        }
        guard !isImporting else {
            showToast(T("Lore is still importing"), icon: "hourglass")
            return
        }
        isImporting = true
        defer { isImporting = false }

        let targetBoard = (board ?? selectedBoard ?? defaultBoard).trimmed.nilIfEmpty ?? "Unsorted"
        let id = UUID()
        do {
            let processed = try await Task.detached(priority: .userInitiated) {
                try ImageProcessor.process(data: data, preferredExtension: preferredExtension, root: self.root, id: id)
            }.value
            let pin = Pin(
                id: id,
                title: title ?? TF("Pasted screenshot · %@", Self.captureStamp()),
                image: processed.image,
                thumbnail: processed.thumbnail,
                width: processed.width,
                height: processed.height,
                fileSize: processed.fileSize,
                tags: [],
                board: targetBoard,
                sourceLabel: sourceLabel,
                colors: processed.colors,
                kind: processed.kind,
                colorFamilies: processed.colorFamilies,
                colorTone: processed.colorTone,
                isAnimated: processed.isAnimated,
                frameCount: processed.frameCount
            )
            pins.append(pin)
            refreshSnapshot()
            persist(debounce: 0.05)
            revealFreshlyAdded(board: targetBoard)
            showToast(
                processed.isAnimated
                    ? TF("GIF added to %@", localizedBoard(targetBoard))
                    : TF("Screenshot added to %@", localizedBoard(targetBoard)),
                icon: processed.isAnimated ? "play.rectangle.fill" : "pin.fill"
            )
        } catch {
            showToast(error.localizedDescription, icon: "exclamationmark.triangle")
        }
    }

    /// Adds a pin from SVG markup. `code` may be a full document copied out of
    /// an editor; it is normalised (BOM/prolog stripped) before storage so the
    /// file always starts at the root element.
    @discardableResult
    func addSVGCode(
        _ code: String,
        title: String? = nil,
        sourceLabel: String = "SVG code",
        board: String? = nil
    ) async -> Bool {
        guard let markup = SVGRasterizer.normalizedMarkup(code),
              let data = markup.data(using: .utf8) else {
            showToast(T("That isn't a valid SVG document."), icon: "exclamationmark.triangle")
            return false
        }
        return await addSVGData(data, title: title, sourceLabel: sourceLabel, board: board)
    }

    /// Adds a pin from raw SVG bytes — a dropped `.svg`, an SVG pasteboard
    /// payload, or markup already normalised by `addSVGCode`.
    @discardableResult
    func addSVGData(
        _ data: Data,
        title: String? = nil,
        sourceLabel: String = "SVG code",
        board explicitBoard: String? = nil
    ) async -> Bool {
        guard !isImporting else {
            showToast(T("Lore is still importing"), icon: "hourglass")
            return false
        }
        isImporting = true
        defer { isImporting = false }

        let targetBoard = (explicitBoard ?? selectedBoard ?? defaultBoard).trimmed.nilIfEmpty ?? "Unsorted"
        let id = UUID()
        do {
            let processed = try await Task.detached(priority: .userInitiated) {
                try ImageProcessor.process(
                    svgData: data,
                    root: self.root,
                    id: id,
                    displayName: T("SVG code")
                )
            }.value
            let pin = Pin(
                id: id,
                title: title?.trimmed.nilIfEmpty ?? TF("SVG · %@", Self.captureStamp()),
                image: processed.image,
                thumbnail: processed.thumbnail,
                width: processed.width,
                height: processed.height,
                fileSize: processed.fileSize,
                tags: [],
                board: targetBoard,
                sourceLabel: sourceLabel,
                colors: processed.colors,
                kind: processed.kind,
                colorFamilies: processed.colorFamilies,
                colorTone: processed.colorTone,
                isAnimated: false,
                frameCount: 1
            )
            pins.append(pin)
            refreshSnapshot()
            persist(debounce: 0.05)
            revealFreshlyAdded(board: targetBoard)
            showToast(TF("SVG added to %@", localizedBoard(targetBoard)), icon: PinKind.svg.icon)
            return true
        } catch {
            showToast(error.localizedDescription, icon: "exclamationmark.triangle")
            return false
        }
    }

    @discardableResult
    func pasteFromClipboard(board: String? = nil) async -> Bool {
        let pasteboard = NSPasteboard.general

        if let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            let urls = objects.compactMap { ($0 as? NSURL) as URL? }
            let imageURLs = urls.filter { Clipboard.isLikelyImage($0) }
            if !imageURLs.isEmpty {
                await addFiles(imageURLs, sourceLabel: "Clipboard", board: board)
                return true
            }
        }

        // Copied markup before the bitmap types: a vector copied from a code
        // editor only advertises text, and a browser copy of an SVG page often
        // carries a raster fallback that would otherwise win.
        if let markup = Clipboard.svgCode() {
            await addSVGData(
                Data(markup.utf8),
                title: TF("Pasted SVG · %@", Self.captureStamp()),
                sourceLabel: "Clipboard",
                board: board
            )
            return true
        }

        // Prefer GIF bytes before PNG/TIFF: browsers expose a static PNG
        // representation too, and copying from the wrong one would drop the
        // animation. Both the classic and modern pasteboard identifiers exist.
        for type in Clipboard.gifTypes {
            if let gif = pasteboard.data(forType: type) {
                await addImageData(
                    gif,
                    preferredExtension: "gif",
                    sourceLabel: "Clipboard",
                    title: TF("Pasted GIF · %@", Self.captureStamp()),
                    board: board
                )
                return true
            }
        }

        if let png = pasteboard.data(forType: .png) {
            await addImageData(png, preferredExtension: "png", sourceLabel: "Clipboard", title: TF("Pasted screenshot · %@", Self.captureStamp()), board: board)
            return true
        }
        if let tiff = pasteboard.data(forType: .tiff), let png = ImageProcessor.pngData(fromTIFF: tiff) {
            await addImageData(png, preferredExtension: "png", sourceLabel: "Clipboard", title: TF("Pasted screenshot · %@", Self.captureStamp()))
            return true
        }
        if let jpeg = pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")) {
            await addImageData(jpeg, preferredExtension: "jpg", sourceLabel: "Clipboard", title: TF("Pasted screenshot · %@", Self.captureStamp()), board: board)
            return true
        }

        showToast("No image on the clipboard", icon: "doc.on.clipboard")
        return false
    }

    func captureScreenshot(board: String? = nil) async {
        guard !isImporting else {
            showToast(T("Lore is still importing"), icon: "hourglass")
            return
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lore-Screen-\(UUID().uuidString).png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", tempURL.path]

        let succeeded: Bool = await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }

        guard succeeded, FileManager.default.fileExists(atPath: tempURL.path) else {
            try? FileManager.default.removeItem(at: tempURL)
            return
        }

        await addFiles(
            [tempURL],
            sourceLabel: "Screen capture",
            preferredTitle: TF("Screen capture · %@", Self.captureStamp()),
            board: board
        )
        try? FileManager.default.removeItem(at: tempURL)
    }

    private func revealFreshlyAdded(board: String) {
        // All Pins already contains the new pin; jumping into its board (often
        // "Unsorted") just because of a paste is disorienting. Everywhere else
        // keep the existing behavior of revealing the board that received it.
        let staysInAllPins = section == .all && selectedBoard == nil
        withAnimation(.snappy(duration: 0.3)) {
            section = .all
            selectedBoard = staysInAllPins ? nil : board
            filter = .all
            colorFamilyFilter = nil
            toneFilter = nil
            clearSearch()
        }
    }

    // MARK: - Id-based actions (cards carry values, not the store)

    func toggleFavorite(id: UUID) {
        guard let pin = pin(id: id) else { return }
        toggleFavorite(pin)
    }

    func copyAgentSnippet(id: UUID) {
        guard let pin = pin(id: id) else { return }
        copyAgentSnippet(for: pin)
    }

    func copyImage(id: UUID) {
        guard let pin = pin(id: id) else { return }
        copyImage(pin)
    }

    func openOriginal(id: UUID) {
        guard let pin = pin(id: id) else { return }
        openOriginal(pin)
    }

    func revealPin(id: UUID) {
        guard let pin = pin(id: id) else { return }
        revealPin(pin)
    }

    func openSource(id: UUID) {
        guard let pin = pin(id: id) else { return }
        openSource(pin)
    }

    // MARK: - Sharing / clipboard

    var agentBaseURL: String { "http://127.0.0.1:\(agentPort)" }

    /// One short brief for any coding agent: what Lore is, and where to read the API.
    /// Everything else (endpoints, filters, uploads) lives in the docs, so we don't restate it here.
    var agentBrief: String {
        let base = agentBaseURL
        return """
        Lore is a local visual reference library on this Mac — UI screenshots filed into boards, with tags, notes and palettes.
        Docs: \(base)/docs
        llms.txt: \(base)/llms.txt
        Read the docs to learn how to query the library or add new screenshots.
        """
    }
    var agentDocsURL: URL? { URL(string: agentBaseURL + "/docs") }
    var agentContextURL: URL? { URL(string: agentBaseURL + "/api/v1/context") }
    var agentManifestURL: URL? { URL(string: agentBaseURL + "/llms.txt") }

    func apiImageURL(for pin: Pin) -> String {
        agentBaseURL + "/api/v1/pins/\(pin.id.uuidString)/image"
    }

    func agentSnippet(for pin: Pin) -> String {
        var lines: [String] = []
        lines.append("### \(pin.title)")
        lines.append("")
        lines.append("![Lore reference: \(pin.title)](\(apiImageURL(for: pin)))")
        lines.append("")
        lines.append("- Board: \(pin.board)")
        if !pin.tags.isEmpty { lines.append("- Tags: " + pin.tags.map { "#\($0)" }.joined(separator: " ")) }
        lines.append("- Pixels: \(pin.pixelLabel)")
        if pin.isGIF {
            lines.append(pin.frameCount > 1
                ? "- Format: GIF · \(pin.frameCount) frames"
                : "- Format: GIF")
        } else if pin.isSVG {
            lines.append("- Format: SVG · vector (scales without loss)")
        }
        if !pin.colors.isEmpty { lines.append("- Palette: " + pin.colors.joined(separator: ", ")) }
        let profile = pin.colorProfile
        var colorLine = "- Color: " + profile.families.map(\.rawValue).joined(separator: " / ") + " · \(profile.tone.rawValue)"
        if profile.isMulticolor { colorLine += " · multicolor" }
        lines.append(colorLine)
        if !pin.note.isEmpty { lines.append("- Design note: \(pin.note)") }
        lines.append("- Captured: \(pin.createdAt.loreTime)")
        return lines.joined(separator: "\n")
    }

    func agentContext(includePins subset: [Pin]? = nil) -> String {
        let chosen = subset ?? filteredPins
        var lines: [String] = [agentBrief, ""]
        lines.append("## References in this context (\(chosen.count))")
        lines.append("")
        for pin in chosen {
            lines.append(agentSnippet(for: pin))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    func copyAgentSnippet(for pin: Pin) {
        copyText(agentSnippet(for: pin), message: T("Agent snippet copied"), icon: "sparkles")
    }

    func copyAgentContext() {
        copyText(agentBrief, message: T("Prompt copied"), icon: "sparkles")
    }

    func copyPinJSON(_ pin: Pin) {
        let profile = pin.colorProfile
        let payload: [String: Any] = [
            "id": pin.id.uuidString,
            "title": pin.title,
            "note": pin.note,
            "board": pin.board,
            "tags": pin.tags,
            "kind": pin.kind.rawValue,
            "width": pin.width,
            "height": pin.height,
            "colors": pin.colors,
            "animated": pin.isAnimated,
            "frameCount": pin.frameCount,
            "colorFamily": profile.family.rawValue,
            "colorFamilies": profile.families.map(\.rawValue),
            "colorTone": profile.tone.rawValue,
            "favorite": pin.isFavorite,
            "image": pin.image,
            "imageURL": apiImageURL(for: pin),
            "sourceLabel": pin.sourceLabel ?? NSNull(),
            "sourceURL": pin.sourceURL ?? NSNull()
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            copyText(string, message: T("Pin JSON copied"), icon: "curlybraces")
        }
    }

    func copyText(_ text: String, message: String? = nil, icon: String = "doc.on.doc") {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        showToast(message ?? T("Copied"), icon: icon)
    }

    func copyImage(_ pin: Pin) {
        copyImage(pin, fullResolution: false)
    }

    /// `fullResolution` copies the original file instead of the thumbnail. The
    /// large-image viewer uses it so the clipboard matches what is on screen;
    /// the grid and detail menus keep the cheaper thumbnail copy.
    func copyImage(_ pin: Pin, fullResolution: Bool) {
        let thumbnail = thumbnailURL(for: pin)
        let original = originalURL(for: pin)
        let candidates = fullResolution ? [original, thumbnail] : [thumbnail, original]
        guard let loaded = candidates.lazy.compactMap({ NSImage(contentsOf: $0) }).first else {
            showToast(T("Couldn't load that image"), icon: "exclamationmark.triangle")
            return
        }
        let image = loaded
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        showToast(T("Image copied"), icon: "photo.on.rectangle")
    }

    func openOriginal(_ pin: Pin) {
        NSWorkspace.shared.open(originalURL(for: pin))
    }

    func revealPin(_ pin: Pin) {
        NSWorkspace.shared.activateFileViewerSelecting([originalURL(for: pin)])
    }

    func openSource(_ pin: Pin) {
        guard let source = pin.sourceURL, let url = URL(string: source) else { return }
        NSWorkspace.shared.open(url)
    }

    func openAgentDocs() {
        if let agentDocsURL { NSWorkspace.shared.open(agentDocsURL) }
    }

    func openAgentContext() {
        if let agentContextURL { NSWorkspace.shared.open(agentContextURL) }
    }

    func openAgentManifest() {
        if let agentManifestURL { NSWorkspace.shared.open(agentManifestURL) }
    }

    func openDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([libraryFileURL])
    }

    // MARK: - Agent server

    func startAgentServerIfNeeded() {
        guard agentAPIEnabled, agentServer == nil else { return }

        agentGeneration += 1
        let generation = agentGeneration
        let server = LoreAgentServer(
            config: AgentServerConfig(
                port: agentPort,
                libraryRoot: root,
                allowsMetadataEdits: allowsAgentMetadataEdits
            )
        )
        server.onStatusChange = { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self, self.agentGeneration == generation else { return }
                self.agentStatus = status
            }
        }
        server.onLibraryChanged = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.agentGeneration == generation else { return }
                self.reloadFromDisk(announceNewPins: true)
            }
        }
        agentServer = server
        agentStatus = .starting
        server.start()
    }

    func stopAgentServer() {
        agentGeneration += 1
        agentServer?.onStatusChange = nil
        agentServer?.onLibraryChanged = nil
        agentServer?.stop()
        agentServer = nil
        agentStatus = .stopped
    }

    func restartAgentServer() {
        stopAgentServer()
        if agentAPIEnabled { startAgentServerIfNeeded() }
    }

    func setAgentEnabled(_ enabled: Bool) {
        agentAPIEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.agentEnabled)
        if enabled {
            startAgentServerIfNeeded()
        } else {
            stopAgentServer()
        }
    }

    func setAgentMetadataEdits(_ enabled: Bool) {
        guard allowsAgentMetadataEdits != enabled else { return }
        allowsAgentMetadataEdits = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.agentMetadataEdits)
        if agentServer != nil || agentStatus.isRunning {
            restartAgentServer()
        }
    }

    func setAgentPort(_ port: UInt16) {
        guard port >= 1024 else { return }
        agentPort = port
        UserDefaults.standard.set(Int(port), forKey: Keys.agentPort)
        if agentServer != nil || agentStatus.isRunning {
            restartAgentServer()
        }
    }

    var agentStatusLabel: String {
        switch agentStatus {
        case .stopped: return T(agentAPIEnabled ? "API stopped" : "API off")
        case .starting: return T("API starting…")
        case .running: return T("Agent API live")
        case .failed: return T("API unavailable")
        }
    }

    var agentStatusDetail: String? {
        switch agentStatus {
        case .failed(let message): return message
        default: return nil
        }
    }

    // MARK: - Utilities

    func showToast(_ text: String, icon: String = "checkmark") {
        let message = ToastMessage(text: text, icon: icon)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            toast = message
        }
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            guard let self, self.toast?.id == message.id else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.toast = nil
            }
        }
    }

    /// Debounced, off-main write. Callers pass a longer window for typing and
    /// a short one for destructive operations.
    private func persist(debounce: TimeInterval = 0.4) {
        hasPendingWrite = true
        writer.schedule(pins: pins, debounce: debounce)
    }

    /// Fire-and-forget flush; used when leaving an editing context.
    func flushPersistence() {
        guard hasPendingWrite else { return }
        hasPendingWrite = false
        writer.flush(pins: pins)
    }

    /// Bounded blocking flush; used on app termination.
    func flushPersistenceAndWait() {
        guard hasPendingWrite else { return }
        hasPendingWrite = false
        writer.flushAndWait(pins: pins)
    }

    private func refreshSnapshot() {
        revision &+= 1
        let snapshot = LibrarySnapshot(revision: revision, pins: pins)
        self.snapshot = snapshot
        projection.update(snapshot: snapshot)
        columnsMemo = nil
        recentCountMemo = nil
    }

    /// One-time background generation of 640 px grid derivatives for libraries
    /// created before `Cards/` existed.
    func startBackgroundMaintenance() {
        guard !didStartMaintenance else { return }
        didStartMaintenance = true
        let root = self.root
        let pins = self.pins
        Task.detached(priority: .utility) {
            await CardThumbnailBackfill.run(root: root, pins: pins)
        }
        backfillColorProfiles(pins)
        backfillAnimationMetadata(pins)
    }

    /// Image-level colour analysis for pins that predate the taxonomy. The UI
    /// already works from the palette fallback; this upgrades the stored value
    /// once per pin and persists it, so the Agent API and filters agree.
    func backfillColorProfiles(_ candidates: [Pin]) {
        guard !candidates.isEmpty else { return }
        let root = self.root
        Task.detached(priority: .utility) { [weak self] in
            let profiles = await ColorProfileBackfill.run(root: root, pins: candidates)
            guard !profiles.isEmpty else { return }
            await MainActor.run { [weak self] in
                self?.applyColorProfiles(profiles)
            }
        }
    }

    /// Corrects `animated`/`frameCount` for GIFs written before the app could
    /// play them. Like colour analysis this is derived data: `updatedAt` is not
    /// touched, and only pins still missing a frame count are updated.
    func backfillAnimationMetadata(_ candidates: [Pin]) {
        guard candidates.contains(where: { $0.isGIF && $0.frameCount <= 1 }) else { return }
        let root = self.root
        Task.detached(priority: .utility) { [weak self] in
            let detected = await AnimationMetadataBackfill.run(root: root, pins: candidates)
            guard !detected.isEmpty else { return }
            await MainActor.run { [weak self] in
                self?.applyAnimationMetadata(detected)
            }
        }
    }

    private func applyAnimationMetadata(_ detected: [UUID: LoreImageAnimation]) {
        var changed = 0
        for index in pins.indices {
            guard let animation = detected[pins[index].id],
                  pins[index].frameCount <= 1,
                  animation.isAnimated else { continue }
            pins[index].isAnimated = true
            pins[index].frameCount = animation.frameCount
            changed += 1
        }
        guard changed > 0 else { return }
        refreshSnapshot()
        persist(debounce: 0.6)
    }

    private func applyColorProfiles(_ profiles: [UUID: LoreColorProfile]) {
        var changed = 0
        for index in pins.indices {
            guard let profile = profiles[pins[index].id] else { continue }
            let needsFamilies = pins[index].colorFamilies?.isEmpty ?? true
            guard needsFamilies || pins[index].colorTone == nil else { continue }
            pins[index].colorFamilies = profile.families
            pins[index].colorTone = profile.tone
            changed += 1
        }
        guard changed > 0 else { return }
        refreshSnapshot()
        persist(debounce: 0.6)
    }

    /// Warm a single detail image when the pointer rests on a card, so the
    /// first paint after the click uses an already-decoded image.
    func prefetchDetail(id: UUID) {
        guard let pin = pin(id: id) else { return }
        let candidates = detailImageCandidates(for: pin)
        Task.detached(priority: .utility) {
            _ = await ImageLoader.shared.image(paths: candidates, maxPixel: ImageLoader.detailMaxPixel)
        }
    }

    /// Warm the neighbouring detail images so ←/→ is a cache hit.
    func prefetchNeighbors(around pin: Pin, radius: Int = 1) {
        let list = filteredPins
        guard list.count > 1, let index = list.firstIndex(where: { $0.id == pin.id }) else { return }
        var requests: [(paths: [String], maxPixel: Int)] = []
        for offset in -radius...radius where offset != 0 {
            let neighborIndex = index + offset
            guard neighborIndex >= 0, neighborIndex < list.count else { continue }
            requests.append((paths: detailImageCandidates(for: list[neighborIndex]), maxPixel: ImageLoader.detailMaxPixel))
        }
        guard !requests.isEmpty else { return }
        Task.detached(priority: .utility) {
            await ImageLoader.shared.prefetch(requests)
        }
    }

    private static func defaultTitle(for url: URL) -> String {
        let raw = url.deletingPathExtension().lastPathComponent
        let cleaned = raw
            .replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression)
            .trimmed
        let lower = cleaned.lowercased()
        if lower.contains("screenshot") || lower.contains("screen shot") || lower.contains("screencapture") || lower.contains("截屏") {
            return TF("Screenshot · %@", captureStamp())
        }
        if cleaned.count < 3 { return T("Untitled capture") }
        return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }

    private static func captureStamp() -> String {
        Date().loreTime
    }

}