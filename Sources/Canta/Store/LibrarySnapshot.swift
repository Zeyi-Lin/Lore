import Foundation
import Darwin

// MARK: - Card projection

/// Everything `PinCard` needs to draw one card. A value type: SwiftUI can
/// compare two of these cheaply and skip rebuilding unchanged cards.
struct PinCardModel: Identifiable, Equatable {
    let id: UUID
    let title: String
    let board: String
    let boardLabel: String
    let pixelLabel: String
    let aspectRatio: CGFloat
    let imageCandidates: [String]
    let isFavorite: Bool
    let kindIcon: String
    let hasSource: Bool
}

/// Identifies one gallery query. `revision` ties a cached result to the
/// snapshot it was computed from, so data mutations invalidate it for free.
struct GalleryQuery: Hashable {
    var sectionRaw: String
    var board: String?
    var filterRaw: String
    var sortRaw: String
    var needle: String
    var languageRaw: String
    var revision: UInt64
}

// MARK: - Snapshot

/// Immutable view of the library plus the aggregate indices that used to be
/// recomputed on every read (`boardSummaries`, counts, tag/board lookup).
final class LibrarySnapshot {
    let revision: UInt64
    let pins: [Pin]
    let indexByID: [UUID: Int]
    let favoriteCount: Int
    let screenshotCount: Int
    /// display name -> count, "Unsorted" for empty boards
    let boardCounts: [String: Int]
    /// lowercased board -> first pin index, for the sidebar representative
    let boardFirstIndex: [String: Int]
    /// non-empty board names in first-seen order, for menus
    let boardNamesInOrder: [String]
    /// tag -> count
    let tagCounts: [String: Int]

    private var cachedSearchKeys: [String]?
    private var cachedSearchKeyBytes: [[UInt8]]?
    private var cachedSearchLanguage: String?
    private var cachedBoardKeys: [String]?

    init(revision: UInt64, pins: [Pin]) {
        self.revision = revision
        self.pins = pins
        var index: [UUID: Int] = [:]
        index.reserveCapacity(pins.count)
        var favorites = 0
        var screenshots = 0
        var boards: [String: Int] = [:]
        var firstIndex: [String: Int] = [:]
        var boardNames: [String] = []
        var seenBoards = Set<String>()
        var tags: [String: Int] = [:]

        for (offset, pin) in pins.enumerated() {
            index[pin.id] = offset
            if pin.isFavorite { favorites += 1 }
            if pin.kind == .screenshot { screenshots += 1 }

            let trimmedBoard = pin.board.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayBoard = trimmedBoard.isEmpty ? "Unsorted" : trimmedBoard
            boards[displayBoard, default: 0] += 1
            let boardKey = trimmedBoard.lowercased()
            if firstIndex[boardKey] == nil {
                firstIndex[boardKey] = offset
            }
            if !trimmedBoard.isEmpty, seenBoards.insert(trimmedBoard).inserted {
                boardNames.append(trimmedBoard)
            }
            for tag in pin.tags where !tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                tags[tag, default: 0] += 1
            }
        }

        self.indexByID = index
        self.favoriteCount = favorites
        self.screenshotCount = screenshots
        self.boardCounts = boards
        self.boardFirstIndex = firstIndex
        self.boardNamesInOrder = boardNames
        self.tagCounts = tags
    }

    func pin(at index: Int) -> Pin { pins[index] }

    func pin(id: UUID) -> Pin? {
        guard let index = indexByID[id] else { return nil }
        return pins[index]
    }

    /// Lowercased search haystack per pin. Built lazily: a pure board switch
    /// should not pay for it.
    func searchKeys() -> [String] {
        let language = LanguageManager.shared.resolved.rawValue
        if let cachedSearchKeys, cachedSearchLanguage == language { return cachedSearchKeys }
        var keys: [String] = []
        keys.reserveCapacity(pins.count)
        for pin in pins {
            keys.append([
                pin.title,
                pin.note,
                pin.board,
                localizedBoard(pin.board),
                pin.sourceLabel ?? "",
                pin.tags.joined(separator: " "),
                pin.kind.label
            ].joined(separator: " ").lowercased().precomposedStringWithCanonicalMapping)
        }
        cachedSearchKeys = keys
        cachedSearchKeyBytes = nil
        cachedSearchLanguage = language
        return keys
    }

    /// UTF-8 bytes for the same keys, used by byte-level substring search.
    /// A byte match on valid UTF-8 is equivalent to a scalar substring match,
    /// and is much faster than `String.contains` for the candidate pass.
    func searchKeyBytes() -> [[UInt8]] {
        _ = searchKeys()
        if let cachedSearchKeyBytes { return cachedSearchKeyBytes }
        let bytes = (cachedSearchKeys ?? []).map { Array($0.utf8) }
        cachedSearchKeyBytes = bytes
        return bytes
    }

    func boardKeys() -> [String] {
        if let cachedBoardKeys { return cachedBoardKeys }
        let keys = pins.map { $0.board.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        cachedBoardKeys = keys
        return keys
    }
}

// MARK: - Projection

/// Memoised query evaluation. Every gallery read goes through here, so one
/// interaction recomputes the visible set at most once instead of once per
/// view body pass.
final class GalleryProjection {
    private var snapshot: LibrarySnapshot
    private let root: URL
    private var pinsMemo: [GalleryQuery: [Pin]] = [:]
    private var modelsMemo: [GalleryQuery: [PinCardModel]] = [:]
    private var recentOrder: [Int]?
    private var oldestOrder: [Int]?
    private var titleOrder: [Int]?

    init(snapshot: LibrarySnapshot, root: URL) {
        self.snapshot = snapshot
        self.root = root
    }

    func update(snapshot: LibrarySnapshot) {
        guard snapshot.revision != self.snapshot.revision else { return }
        self.snapshot = snapshot
        pinsMemo.removeAll(keepingCapacity: true)
        modelsMemo.removeAll(keepingCapacity: true)
        recentOrder = nil
        oldestOrder = nil
        titleOrder = nil
    }

    var currentSnapshot: LibrarySnapshot { snapshot }

    func visiblePins(for query: GalleryQuery) -> [Pin] {
        if let cached = pinsMemo[query] { return cached }
        let result = Perf.interval("gallery.query") { compute(query) }
        if pinsMemo.count > 32 { pinsMemo.removeAll(keepingCapacity: true) }
        pinsMemo[query] = result
        return result
    }

    func cards(for query: GalleryQuery) -> [PinCardModel] {
        if let cached = modelsMemo[query] { return cached }
        let pins = visiblePins(for: query)
        let rootPath = root.path
        let models = Perf.interval("gallery.models") { () -> [PinCardModel] in
            var built: [PinCardModel] = []
            built.reserveCapacity(pins.count)
            for pin in pins {
                var candidates: [String] = []
                candidates.reserveCapacity(3)
                candidates.append(rootPath + "/Cards/" + pin.id.uuidString + ".jpg")
                if let thumbnail = pin.thumbnail {
                    candidates.append(rootPath + "/" + thumbnail)
                }
                candidates.append(rootPath + "/" + pin.image)
                built.append(PinCardModel(
                    id: pin.id,
                    title: pin.title,
                    board: pin.board,
                    boardLabel: localizedBoard(pin.board),
                    pixelLabel: pin.pixelLabel,
                    aspectRatio: pin.aspectRatio,
                    imageCandidates: candidates,
                    isFavorite: pin.isFavorite,
                    kindIcon: pin.kind.icon,
                    hasSource: pin.sourceURL != nil
                ))
            }
            return built
        }
        modelsMemo[query] = models
        return models
    }

    func boardSummaries() -> [BoardSummary] {
        let counts = snapshot.boardCounts
        let ordered = Self.suggestedBoards.filter { counts[$0] != nil }
        let extras = counts.keys.filter { !Self.suggestedBoards.contains($0) }.sorted()
        return (ordered + extras).map { BoardSummary(name: $0, count: counts[$0] ?? 0) }
    }

    func allBoardNames() -> [String] {
        var names = Self.suggestedBoards
        for board in snapshot.boardNamesInOrder where !names.contains(board) {
            names.append(board)
        }
        return names
    }

    func allTags() -> [(name: String, count: Int)] {
        snapshot.tagCounts
            .map { (name: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.name < rhs.name }
                return lhs.count > rhs.count
            }
    }

    func representativePin(forBoard boardName: String) -> Pin? {
        let key = boardName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let index = snapshot.boardFirstIndex[key] else { return nil }
        return snapshot.pin(at: index)
    }

    // MARK: Query evaluation

    private func compute(_ query: GalleryQuery) -> [Pin] {
        let pins = snapshot.pins
        let order = orderedIndices(for: query.sortRaw)
        let cutoff: Date? = query.sectionRaw == "recent"
            ? Calendar.current.date(byAdding: .day, value: -30, to: Date())
            : nil
        let boardKey = query.board
        let boardKeys = boardKey != nil ? snapshot.boardKeys() : nil
        let tokens: [String]? = query.needle.isEmpty
            ? nil
            : query.needle.split(separator: " ").map(String.init)
        let searchKeyBytes = tokens != nil ? snapshot.searchKeyBytes() : nil
        let needleBytes: [[UInt8]] = tokens?.map { Array($0.utf8) } ?? []

        var result: [Pin] = []
        result.reserveCapacity(min(order.count, pins.count))
        for index in order {
            let pin = pins[index]

            switch query.sectionRaw {
            case "favorites":
                guard pin.isFavorite else { continue }
            case "recent":
                if let cutoff, pin.createdAt < cutoff { continue }
            default:
                break
            }

            if let boardKey, let boardKeys, boardKeys[index] != boardKey { continue }

            switch query.filterRaw {
            case "screenshots":
                guard pin.kind == .screenshot else { continue }
            case "favorites":
                guard pin.isFavorite else { continue }
            default:
                break
            }

            if let searchKeyBytes {
                let haystack = searchKeyBytes[index]
                var matched = true
                for needle in needleBytes where !Self.byteContains(haystack, needle) {
                    matched = false
                    break
                }
                if !matched { continue }
            }

            result.append(pin)
        }
        return result
    }

    private static func byteContains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        if needle.isEmpty { return true }
        if needle.count > haystack.count { return false }
        return haystack.withUnsafeBufferPointer { haystackBuffer in
            needle.withUnsafeBufferPointer { needleBuffer in
                guard let haystackBase = haystackBuffer.baseAddress,
                      let needleBase = needleBuffer.baseAddress else { return false }
                return memmem(haystackBase, haystackBuffer.count, needleBase, needleBuffer.count) != nil
            }
        }
    }

    private func orderedIndices(for sortRaw: String) -> [Int] {
        switch sortRaw {
        case "oldest":
            if let oldestOrder { return oldestOrder }
            let order = recentIndices().reversed()
            let result = Array(order)
            oldestOrder = result
            return result
        case "title":
            if let titleOrder { return titleOrder }
            let pins = snapshot.pins
            let result = pins.indices.sorted {
                pins[$0].title.localizedCaseInsensitiveCompare(pins[$1].title) == .orderedAscending
            }
            titleOrder = result
            return result
        default:
            return recentIndices()
        }
    }

    private func recentIndices() -> [Int] {
        if let recentOrder { return recentOrder }
        let pins = snapshot.pins
        let result = pins.indices.sorted { pins[$0].createdAt > pins[$1].createdAt }
        recentOrder = result
        return result
    }

    static let suggestedBoards = ["Web dashboards", "Mobile flows", "Landing pages", "Editorial", "Unsorted"]
}

// MARK: - Masonry composition

enum MasonryComposer {
    static func columnCount(
        width: CGFloat,
        minColumnWidth: CGFloat = 238,
        maxColumns: Int = 5,
        spacing: CGFloat = 20
    ) -> Int {
        guard width.isFinite, width > 0 else { return 2 }
        let count = Int((width + spacing) / (minColumnWidth + spacing))
        return max(2, min(maxColumns, count))
    }

    static func columnWidth(availableWidth: CGFloat, columns: Int, spacing: CGFloat) -> CGFloat {
        guard columns > 0 else { return availableWidth }
        return (availableWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
    }

    /// Heights come from the image aspect ratio plus a fixed caption height
    /// (the title reserves two lines), so balancing is pure arithmetic and
    /// needs no per-card text measurement.
    static func split(
        models: [PinCardModel],
        columns: Int,
        availableWidth: CGFloat,
        spacing: CGFloat,
        rowSpacing: CGFloat = 28,
        captionHeight: CGFloat = 58
    ) -> [[PinCardModel]] {
        let count = max(1, columns)
        let width = columnWidth(availableWidth: availableWidth, columns: count, spacing: spacing)
        var heights = [CGFloat](repeating: 0, count: count)
        var buckets = [[PinCardModel]](repeating: [], count: count)
        buckets.reserveCapacity(count)
        for model in models {
            var target = 0
            var shortest = heights[0]
            for index in 1..<count where heights[index] < shortest {
                shortest = heights[index]
                target = index
            }
            buckets[target].append(model)
            heights[target] += width / max(model.aspectRatio, 0.2) + captionHeight + rowSpacing
        }
        return buckets
    }
}
