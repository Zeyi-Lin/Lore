import SwiftUI
import AppKit
import Observation
import CantaAgentKit

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
    var selectedPinID: UUID?
    var isSelectingPins = false
    var selectedPinIDs: Set<UUID> = []
    var capturePresented = false
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
        static let agentPort = "canta.agent.port"
        static let agentEnabled = "canta.agent.enabled"
        static let agentMetadataEdits = "canta.agent.metadataEdits"
        static let defaultBoard = "canta.defaultBoard"
    }

    @ObservationIgnored private var agentServer: CantaAgentServer?
    @ObservationIgnored private var agentGeneration = 0
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    // Derived-data core. `snapshot` is replaced on every data mutation;
    // `projection` memoises queries against it.
    @ObservationIgnored private let writer: LibraryWriter
    @ObservationIgnored private(set) var snapshot: LibrarySnapshot
    @ObservationIgnored private let projection: GalleryProjection
    private var revision: UInt64
    @ObservationIgnored private var columnsMemo: (key: ColumnsKey, columns: [[PinCardModel]])?
    @ObservationIgnored private var recentCountMemo: (revision: UInt64, value: Int)?
    @ObservationIgnored private var didStartMaintenance = false
    @ObservationIgnored private var hasPendingWrite = false
    @ObservationIgnored private var searchDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var searchGeneration = 0

    private struct ColumnsKey: Hashable {
        var query: GalleryQuery
        var width: CGFloat
        var columns: Int
    }


    init(root: URL = CantaPaths.dataRoot) {
        let resolvedRoot: URL
        if let debugHome = UserDefaults.standard.string(forKey: "canta.debugHome"), !debugHome.isEmpty {
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
            fileURL: CantaPaths.libraryFile(root: resolvedRoot)
        )
        self.writer = writer

        var library = CantaLibrary()
        var loadError: String?
        do {
            // Single decode: seeding and loading share one read of library.json.
            library = try SeedLoader.loadOrInstall(root: resolvedRoot)
        } catch {
            loadError = TF("Canta couldn't read your library. New pins will start a fresh one. (%@)", error.localizedDescription)
        }

        self.revision = 1
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
        return projection.boardTree()
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
        "\(section.rawValue)|\(selectedBoard ?? "")|\(filter.rawValue)|\(sort.rawValue)|\(searchQuery)"
    }

    var dataFolderPath: String { root.path }
    var libraryFileURL: URL { CantaPaths.libraryFile(root: root) }

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

    /// Detail candidates: the 1200 px thumbnail first, the original as fallback.
    func detailImageCandidates(for pin: Pin) -> [String] {
        var candidates: [String] = []
        if let thumbnail = pin.thumbnail {
            candidates.append(root.path + "/" + thumbnail)
        }
        candidates.append(root.path + "/" + pin.image)
        return candidates
    }

    /// Native-size original, used only by the large-image mode.
    func largeImageCandidates(for pin: Pin) -> [String] {
        [root.path + "/" + pin.image]
    }

    /// Column partitions for the masonry grid, balanced from aspect ratios
    /// alone. Cached per query + measured width.
    func columns(
        forWidth width: CGFloat,
        spacing: CGFloat = 20,
        rowSpacing: CGFloat = 28
    ) -> [[PinCardModel]] {
        let count = MasonryComposer.columnCount(width: width, spacing: spacing)
        let key = ColumnsKey(query: currentQuery, width: width.rounded(), columns: count)
        if let columnsMemo, columnsMemo.key == key { return columnsMemo.columns }
        let columns = MasonryComposer.split(
            models: visibleCards,
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
        let url = CantaPaths.libraryFile(root: root)
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let data = try? Data(contentsOf: url),
                  let library = try? CantaJSON.makeDecoder().decode(CantaLibrary.self, from: data) else {
                return
            }
            await MainActor.run { [weak self] in
                self?.applyExternalReload(library, announceNewPins: announceNewPins)
            }
        }
    }

    private func applyExternalReload(_ library: CantaLibrary, announceNewPins: Bool) {
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
        let clean = board.trimmed.nilIfEmpty ?? "Unsorted"
        var changed = 0
        for index in pins.indices where ids.contains(pins[index].id) {
            pins[index].board = clean
            pins[index].updatedAt = Date()
            changed += 1
        }
        refreshSnapshot()
        persist(debounce: 0.1)
        showToast(TF("%ld pins moved to %@", changed, localizedBoard(clean)), icon: "folder")
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
            try? fm.removeItem(at: CantaPaths.cardsDirectory(root: root)
                .appendingPathComponent("\(pin.id.uuidString).jpg"))
        }
        pins.removeAll { ids.contains($0.id) }
        if let selectedPinID, ids.contains(selectedPinID) { self.selectedPinID = nil }
        refreshSnapshot()
        persist(debounce: 0.1)
        showToast(TF("%ld pins deleted", targets.count), icon: "trash")
        endSelection()
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

    func deletePin(_ pin: Pin) {
        let fm = FileManager.default
        try? fm.removeItem(at: root.appendingPathComponent(pin.image))
        if let thumbnail = pin.thumbnail {
            try? fm.removeItem(at: root.appendingPathComponent(thumbnail))
        }
        try? fm.removeItem(at: CantaPaths.cardsDirectory(root: root)
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
            showToast(T("Canta is still importing"), icon: "hourglass")
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
                    kind: processed.kind
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
        guard !isImporting else {
            showToast(T("Canta is still importing"), icon: "hourglass")
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
                kind: .screenshot
            )
            pins.append(pin)
            refreshSnapshot()
            persist(debounce: 0.05)
            revealFreshlyAdded(board: targetBoard)
            showToast(TF("Screenshot added to %@", localizedBoard(targetBoard)), icon: "pin.fill")
        } catch {
            showToast(error.localizedDescription, icon: "exclamationmark.triangle")
        }
    }

    @discardableResult
    func pasteFromClipboard(board: String? = nil) async -> Bool {
        let pasteboard = NSPasteboard.general

        if let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            let urls = objects.compactMap { ($0 as? NSURL) as URL? }
            let imageURLs = urls.filter { Self.isLikelyImage($0) }
            if !imageURLs.isEmpty {
                await addFiles(imageURLs, sourceLabel: "Clipboard", board: board)
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
            showToast(T("Canta is still importing"), icon: "hourglass")
            return
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Canta-Screen-\(UUID().uuidString).png")

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
        withAnimation(.snappy(duration: 0.3)) {
            section = .all
            selectedBoard = board
            filter = .all
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

    /// One short brief for any coding agent: what Canta is, and where to read the API.
    /// Everything else (endpoints, filters, uploads) lives in the docs, so we don't restate it here.
    var agentBrief: String {
        let base = agentBaseURL
        return """
        Canta is a local visual reference library on this Mac — UI screenshots filed into boards, with tags, notes and palettes.
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
        lines.append("![Canta reference: \(pin.title)](\(apiImageURL(for: pin)))")
        lines.append("")
        lines.append("- Board: \(pin.board)")
        if !pin.tags.isEmpty { lines.append("- Tags: " + pin.tags.map { "#\($0)" }.joined(separator: " ")) }
        lines.append("- Pixels: \(pin.pixelLabel)")
        if !pin.colors.isEmpty { lines.append("- Palette: " + pin.colors.joined(separator: ", ")) }
        if !pin.note.isEmpty { lines.append("- Design note: \(pin.note)") }
        lines.append("- Captured: \(pin.createdAt.cantaTime)")
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
        let candidates = [thumbnailURL(for: pin)] + [originalURL(for: pin)]
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
        let server = CantaAgentServer(
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
    }

    /// Warm a single detail image when the pointer rests on a card, so the
    /// first paint after the click uses an already-decoded 1200 px image.
    func prefetchDetail(id: UUID) {
        guard let pin = pin(id: id) else { return }
        let candidates = detailImageCandidates(for: pin)
        Task.detached(priority: .utility) {
            _ = await ImageLoader.shared.image(paths: candidates, maxPixel: 1200)
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
            requests.append((paths: detailImageCandidates(for: list[neighborIndex]), maxPixel: 1200))
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
        Date().cantaTime
    }

    private static func isLikelyImage(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "webp", "gif", "bmp"].contains(ext)
    }
}