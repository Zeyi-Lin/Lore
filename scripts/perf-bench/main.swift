import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

setvbuf(stdout, nil, _IONBF, 0)
var globalChecksum = 0

// ============================================================================
// Canta interaction-cost benchmark — pre-optimization baseline.
//
// This harness preserves the v1 algorithms (filtering / summarising /
// persistence) verbatim so the before/after numbers in
// docs/PERFORMANCE_PLAN.md stay reproducible. The app no longer uses these
// paths: it now runs LibrarySnapshot + GalleryProjection. Run with
// `scripts/perf-bench/run.sh`.
//
// This measures the DATA LAYER only. SwiftUI body evaluation / layout cannot
// be measured from a CLI process; instrument those in the app (see
// docs/PERFORMANCE_PLAN.md §6).
// ============================================================================

func elapsedMS(_ block: () -> Void) -> Double {
    let start = Double(DispatchTime.now().uptimeNanoseconds)
    block()
    return (Double(DispatchTime.now().uptimeNanoseconds) - start) / 1_000_000
}

@discardableResult
func bench(_ label: String, iterations: Int = 11, _ block: () -> Void) -> Double {
    _ = elapsedMS(block)
    var best = Double.greatestFiniteMagnitude
    for _ in 0..<iterations { best = min(best, elapsedMS(block)) }
    let padded = label.count >= 62 ? label : label + String(repeating: " ", count: 62 - label.count)
    print("  " + padded + String(format: "%9.3f ms", best))
    return best
}

func section(_ title: String) { print("\n== \(title) ==") }

// ---------------------------------------------------------------------------
// Synthetic library with realistic field sizes
// ---------------------------------------------------------------------------

let boards = ["Web dashboards", "Mobile flows", "Landing pages", "Editorial", "Unsorted"]
let nameWords = ["Atlas", "Pulse", "Sable", "Miso", "Aurora", "Cadence", "Terrain", "Orbit",
                 "Tide", "Lumen", "Noema", "Sage", "Ledger", "Atelier", "Field notes",
                 "Harbor", "Quartz", "Vellum", "Cinder", "Marble"]
let adjectives = ["quiet", "warm", "editorial", "dense", "airy", "confident", "muted",
                  "structured", "soft", "graphic", "deep", "crisp"]
let nouns = ["dashboard", "onboarding flow", "pricing page", "analytics panel", "checkout",
             "settings sheet", "landing page", "gallery", "editor", "profile"]
let tagPool = ["glassmorphism", "gradient", "cards", "light ui", "dark ui", "typography",
               "fintech", "saas", "mobile", "desktop", "hero", "grid", "minimal",
               "notification", "table", "chart", "modal", "search", "filters", "avatar"]

func makePins(_ count: Int, seed: UInt64 = 0x9E3779B97F4A7C15) -> [Pin] {
    var state = seed
    func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
    func pick(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    var pins: [Pin] = []
    pins.reserveCapacity(count)
    let now = Date()
    for index in 0..<count {
        let width = 1200 + pick(2400)
        let height = 800 + pick(1800)
        let title = "\(adjectives[pick(adjectives.count)].capitalized) \(nouns[pick(nouns.count)]) — \(nameWords[pick(nameWords.count)])"
        let note = "Frosted glass panels float on a soft gradient; 12px borders and 28px blur keep the data friendly while one oversized metric anchors the eye. Version \(index)."
        var tags: [String] = []
        for _ in 0..<5 { tags.append(tagPool[pick(tagPool.count)]) }
        pins.append(Pin(
            id: UUID(),
            title: title,
            note: note,
            image: "Images/\(UUID().uuidString).png",
            thumbnail: "Thumbnails/\(UUID().uuidString).jpg",
            width: width,
            height: height,
            fileSize: 400_000 + pick(900_000),
            createdAt: now.addingTimeInterval(-Double(pick(90)) * 86_400),
            updatedAt: now,
            tags: tags,
            board: boards[pick(boards.count)],
            sourceLabel: "Imported",
            colors: ["#171412", "#FAF8F5", "#E60023", "#615C56", "#F3EFE9"],
            isFavorite: next() % 5 == 0,
            kind: .screenshot
        ))
    }
    return pins
}

// ---------------------------------------------------------------------------
// Pre-optimization LibraryStore.filteredPins (kept for comparison)
// ---------------------------------------------------------------------------

enum Section: String { case all, favorites, recent, agent }
enum Filter: String { case all, screenshots, favorites }

struct StoreLogic {
    var pins: [Pin]
    var section: Section = .all
    var selectedBoard: String? = nil
    var filter: Filter = .all
    var sort: Int = 0
    var searchText: String = ""
    static let suggestedBoards = boards

    var filteredPins: [Pin] {
        var result = pins
        switch section {
        case .favorites: result = result.filter(\.isFavorite)
        case .recent:
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
            result = result.filter { $0.createdAt >= cutoff }
        case .all, .agent: break
        }
        if let selectedBoard {
            result = result.filter { $0.board.caseInsensitiveCompare(selectedBoard) == .orderedSame }
        }
        switch filter {
        case .all: break
        case .screenshots: result = result.filter { $0.kind == .screenshot }
        case .favorites: result = result.filter(\.isFavorite)
        }
        let needle = searchText.trimmed.lowercased()
        if !needle.isEmpty {
            let tokens = needle.split(separator: " ").map(String.init)
            result = result.filter { pin in
                let haystack = [pin.title, pin.note, pin.board, localizedBoard(pin.board),
                                pin.sourceLabel ?? "", pin.tags.joined(separator: " "),
                                pin.kind.label].joined(separator: " ").lowercased()
                return tokens.allSatisfy { haystack.contains($0) }
            }
        }
        switch sort {
        case 1: result.sort { $0.createdAt < $1.createdAt }
        case 2: result.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        default: result.sort { $0.createdAt > $1.createdAt }
        }
        return result
    }

    var boardSummaries: [BoardSummary] {
        var counts: [String: Int] = [:]
        for pin in pins {
            let board = pin.board.trimmed.isEmpty ? "Unsorted" : pin.board
            counts[board, default: 0] += 1
        }
        let orderedNames = Self.suggestedBoards.filter { counts[$0] != nil }
        let extraNames = counts.keys.filter { !Self.suggestedBoards.contains($0) }.sorted()
        return (orderedNames + extraNames).map { BoardSummary(name: $0, count: counts[$0] ?? 0) }
    }

    var favoriteCount: Int { pins.filter(\.isFavorite).count }
    var screenshotCount: Int { pins.filter { $0.kind == .screenshot }.count }

    // SidebarView.swift:119 — per board row, per body pass
    func representative(for board: String) -> Pin? {
        pins.first { $0.board.caseInsensitiveCompare(board) == .orderedSame }
    }

    // LibraryStore.swift:261 showAdjacentPin + PinDetailView.swift:146
    func adjacentID(offset: Int, current: UUID?) -> UUID? {
        let list = filteredPins
        guard !list.isEmpty else { return nil }
        let currentIndex = list.firstIndex(where: { $0.id == current }) ?? -1
        let nextIndex = min(max(currentIndex + offset, 0), list.count - 1)
        guard nextIndex != currentIndex else { return nil }
        return list[nextIndex].id
    }
}

// ---------------------------------------------------------------------------
// Proposed data layer: one snapshot, precomputed keys, word index, memoised query
// ---------------------------------------------------------------------------

final class GalleryProjection {
    struct QueryKey: Hashable {
        var section: String
        var board: String?
        var filter: String
        var sort: String
        var needle: String
    }

    let pins: [Pin]
    private let searchKeys: [String]
    private let boardKeys: [String]
    private let favoriteIDs: [Int]
    private let screenshotIDs: [Int]
    private let byID: [UUID: Int]
    private let wordPostings: [String: [Int]]
    private var memo: [QueryKey: [Int]] = [:]

    init(pins: [Pin]) {
        var keys: [String] = []
        var boardKeys: [String] = []
        var favorites: [Int] = []
        var screenshots: [Int] = []
        var byID: [UUID: Int] = [:]
        var postings: [String: [Int]] = [:]
        keys.reserveCapacity(pins.count)
        byID.reserveCapacity(pins.count)
        for (i, pin) in pins.enumerated() {
            let key = [pin.title, pin.note, pin.board, localizedBoard(pin.board),
                       pin.sourceLabel ?? "", pin.tags.joined(separator: " "),
                       pin.kind.label].joined(separator: " ").lowercased()
            keys.append(key)
            boardKeys.append(pin.board.lowercased())
            if pin.isFavorite { favorites.append(i) }
            if pin.kind == .screenshot { screenshots.append(i) }
            byID[pin.id] = i
            var seen = Set<String>()
            for word in key.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) where word.count > 1 {
                let token = String(word)
                if seen.insert(token).inserted { postings[token, default: []].append(i) }
            }
        }
        self.pins = pins
        self.searchKeys = keys
        self.boardKeys = boardKeys
        self.favoriteIDs = favorites
        self.screenshotIDs = screenshots
        self.byID = byID
        self.wordPostings = postings
    }

    func orderedIDs(section: String, board: String?, filter: String, sort: String, needle rawNeedle: String) -> [Int] {
        let key = QueryKey(section: section, board: board, filter: filter, sort: sort, needle: rawNeedle)
        if let hit = memo[key] { return hit }

        var candidates: [Int]
        switch filter {
        case "screenshots": candidates = screenshotIDs
        case "favorites": candidates = favoriteIDs
        default:
            switch section {
            case "favorites": candidates = favoriteIDs
            default: candidates = Array(pins.indices)
            }
        }
        if let board {
            let wanted = board.lowercased()
            candidates = candidates.filter { boardKeys[$0] == wanted }
        }
        let needle = rawNeedle.trimmed.lowercased()
        if !needle.isEmpty {
            let tokens = needle.split(separator: " ").map(String.init)
            // Intersect postings by prefix, but post-filter with substring semantics
            // so behaviour matches the current `.contains` implementation.
            var narrowed = candidates
            if let first = tokens.first, let postings = wordPostings[first] {
                let set = Set(postings)
                narrowed = candidates.filter { set.contains($0) }
            } else {
                for token in tokens {
                    if let postings = wordPostings[token] {
                        let set = Set(postings)
                        narrowed = candidates.filter { set.contains($0) }
                        break
                    }
                }
            }
            candidates = narrowed.filter { index in
                let key = searchKeys[index]
                return tokens.allSatisfy { key.contains($0) }
            }
        }
        switch sort {
        case "oldest": candidates.sort { pins[$0].createdAt < pins[$1].createdAt }
        case "title": candidates.sort { pins[$0].title.localizedCaseInsensitiveCompare(pins[$1].title) == .orderedAscending }
        default: candidates.sort { pins[$0].createdAt > pins[$1].createdAt }
        }
        memo[key] = candidates
        return candidates
    }

    func index(of id: UUID) -> Int? { byID[id] }
    func id(at index: Int) -> UUID { pins[index].id }
}

// ---------------------------------------------------------------------------
// Persistence, verbatim encoder settings (CantaPaths.swift:45)
// ---------------------------------------------------------------------------

let iso8601: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
}()
let prettyEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .custom { date, encoder in
        var c = encoder.singleValueContainer(); try c.encode(iso8601.string(from: date))
    }
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    return e
}()

func measurePersistence(_ pins: [Pin]) {
    section("Persistence — runs on the main actor on every mutation AND every keystroke")
    let library = CantaLibrary(version: 1, pins: pins)
    var data = Data()
    let encode = bench("JSONEncoder (.prettyPrinted + .sortedKeys), N=\(pins.count)") {
        data = (try? prettyEncoder.encode(library)) ?? Data()
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("canta-bench-library.json")
    let write = bench("Data.write(.atomic)") { try? data.write(to: url, options: .atomic) }
    bench("full persist() = encode + atomic write") {
        if let encoded = try? prettyEncoder.encode(library) { try? encoded.write(to: url, options: .atomic) }
    }
    print(String(format: "    library.json: %.1f MB while typing, %.1f ms blocked per keystroke",
                 Double(data.count) / 1_048_576, encode + write))
    try? FileManager.default.removeItem(at: url)
}

func measureKeystroke(_ pins: [Pin]) {
    section("Typing into search / title — one keystroke at N=\(pins.count)")
    var store = StoreLogic(pins: pins)
    store.searchText = "dark ui"
    let filter = bench("filteredPins(search) per keystroke") { _ = store.filteredPins }
    let library = CantaLibrary(version: 1, pins: pins)
    let persist = bench("persist() per keystroke") {
        if let data = try? prettyEncoder.encode(library) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/canta-keystroke.json"), options: .atomic)
        }
    }
    print(String(format: "    search keystroke: %.1f ms data work (before SwiftUI re-renders N cards)", filter))
    print(String(format: "    title/note keystroke: %.1f ms MAIN-THREAD disk write (before re-render)", persist))
    try? FileManager.default.removeItem(atPath: "/tmp/canta-keystroke.json")
}

let realDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        if let date = iso8601.date(from: string) { return date }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "bad date")
    }
    return d
}()

func measureDecode(_ pins: [Pin]) {
    section("Load / reload — CantaJSON.decoder on the main actor (launch, agent writes)")
    let data = (try? prettyEncoder.encode(CantaLibrary(version: 1, pins: pins))) ?? Data()
    bench("JSONDecoder, N=\(pins.count) (\(data.count / 1024) KB)") {
        _ = try? realDecoder.decode(CantaLibrary.self, from: data)
    }
    bench("ISO8601DateFormatter parse × \(pins.count * 2) dates") {
        for _ in 0..<(pins.count * 2) { _ = iso8601.date(from: "2026-11-13T09:12:00Z") }
    }
}

func measureThumbnailURL(_ pins: [Pin]) {
    section("Card body plumbing — thumbnailURL(for:) is computed per card, per body pass")
    let root = URL(fileURLWithPath: "/Users/zeyilin/Library/Application Support/Canta", isDirectory: true)
    let fm = FileManager.default
    bench("fileExists + URL path × \(pins.count)") {
        for pin in pins {
            let url = root.appendingPathComponent(pin.thumbnail ?? pin.image)
            if fm.fileExists(atPath: url.path) { _ = url.path }
        }
    }
}

func measureStat() {
    section("thumbnailURL(for:) — FileManager.fileExists on every access, main thread")
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("canta-stat-bench", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var urls: [URL] = []
    for i in 0..<2000 {
        let url = dir.appendingPathComponent("t\(i).jpg")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data([0xFF, 0xD8]))
        }
        urls.append(url)
    }
    let fm = FileManager.default
    bench("fileExists × 100") { for url in urls.prefix(100) { _ = fm.fileExists(atPath: url.path) } }
    bench("fileExists × 1000") { for url in urls.prefix(1000) { _ = fm.fileExists(atPath: url.path) } }
    bench("fileExists × 5000") { for url in urls.prefix(5000) { _ = fm.fileExists(atPath: url.path) } }
    try? FileManager.default.removeItem(at: dir)
}

// ---------------------------------------------------------------------------
// Images
// ---------------------------------------------------------------------------

func residentMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
}

func makePhotoLikePNG(pixelWidth: Int, pixelHeight: Int, url: URL) {
    guard !FileManager.default.fileExists(atPath: url.path) else { return }
    // Raw noise => incompressible, like a real screenshot/photo. Encodes slowly,
    // but reproduces realistic decode cost (this is the 4K original case).
    let bytesPerRow = pixelWidth * 4
    var pixels = [UInt8](repeating: 255, count: bytesPerRow * pixelHeight)
    var state: UInt64 = 0x2545F4914F6CDD1D
    pixels.withUnsafeMutableBufferPointer { buffer in
        guard let base = buffer.baseAddress else { return }
        for y in 0..<pixelHeight {
            for x in 0..<pixelWidth {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let noise = UInt8(truncatingIfNeeded: state >> 33)
                let offset = y * bytesPerRow + x * 4
                let band = UInt8(truncatingIfNeeded: (y / 90) * 37 + (x / 120) * 11)
                base[offset] = band &+ noise &>> 3
                base[offset + 1] = band &+ noise &>> 2
                base[offset + 2] = (255 &- band) &+ noise &>> 3
                base[offset + 3] = 255
            }
        }
    }
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    let image = CGImage(width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bitsPerPixel: 32,
                        bytesPerRow: bytesPerRow, space: colorSpace,
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

func makeJPEG(pixelWidth: Int, pixelHeight: Int, url: URL, quality: Double = 0.82) {
    guard !FileManager.default.fileExists(atPath: url.path) else { return }
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                            bytesPerRow: pixelWidth * 4, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    var state: UInt64 = 0x2545F4914F6CDD1D
    for band in 0..<40 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        context.setFillColor(red: CGFloat((state >> 33) & 0xFF) / 255,
                             green: CGFloat((state >> 41) & 0xFF) / 255,
                             blue: CGFloat((state >> 49) & 0xFF) / 255, alpha: 1)
        context.fill(CGRect(x: 0, y: CGFloat(band) / 40 * CGFloat(pixelHeight),
                            width: CGFloat(pixelWidth), height: CGFloat(pixelHeight) / 40))
    }
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.7))
    for row in stride(from: 40, to: pixelHeight - 40, by: 22) {
        context.fill(CGRect(x: 60, y: row, width: pixelWidth - 120, height: 3))
    }
    let image = context.makeImage()!
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    CGImageDestinationFinalize(destination)
}

func draw(_ image: NSImage, width: Int, height: Int) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
}

func measureImages() {
    section("Image pipeline")
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("canta-image-bench", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let pngURL = dir.appendingPathComponent("original-3200x2400.png")
    let jpgURL = dir.appendingPathComponent("thumb-1200x900.jpg")
    for stale in ["original-4000x3000.png", "original-3200x2400.png"] {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(stale))
    }
    print("  preparing fixtures (one-time)…")
    makePhotoLikePNG(pixelWidth: 3200, pixelHeight: 2400, url: pngURL)
    makeJPEG(pixelWidth: 1200, pixelHeight: 900, url: jpgURL)
    let pngBytes = (try? Data(contentsOf: pngURL).count) ?? 0
    let jpgBytes = (try? Data(contentsOf: jpgURL).count) ?? 0
    print(String(format: "    original: 3200×2400 PNG %.1f MB   stored thumbnail: 1200×900 JPEG %.0f KB",
                 Double(pngBytes) / 1_048_576, Double(jpgBytes) / 1024))
    print(String(format: "    decoded bitmap cost: original %.0f MB   stored 1200px thumb %.1f MB   card-sized 476px %.2f MB",
                 Double(3200 * 2400 * 4) / 1_048_576,
                 Double(1200 * 900 * 4) / 1_048_576,
                 Double(476 * 357 * 4) / 1_048_576))

    bench("NSImage(contentsOfFile:) — returns before decode") {
        _ = NSImage(contentsOfFile: pngURL.path)
    }
    bench("first draw of a fresh NSImage (decode on caller)") {
        let image = NSImage(contentsOfFile: pngURL.path)!
        draw(image, width: 476, height: 357)
    }
    let warm = NSImage(contentsOfFile: pngURL.path)!
    _ = { draw(warm, width: 476, height: 357) }()
    bench("second draw of the same NSImage (cached)") {
        draw(warm, width: 476, height: 357)
    }

    bench("CGImageSource full decode 3200×2400") {
        let source = CGImageSourceCreateWithURL(pngURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)!
        _ = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
    bench("CGImageSource thumbnail 476px from 3200×2400") {
        let source = CGImageSourceCreateWithURL(pngURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)!
        _ = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 476,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
    bench("CGImageSource full decode of stored 1200×900 JPEG (card path)") {
        let source = CGImageSourceCreateWithURL(jpgURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)!
        _ = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
    bench("CGImageSource thumbnail 476px from 1200×900 JPEG") {
        let source = CGImageSourceCreateWithURL(jpgURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)!
        _ = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 476,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    // Memory: hold decoded bitmaps the way ImageCache holds NSImages.
    section("Resident memory — decoded bitmaps held by an image cache")
    // Own the backing buffers so the numbers are deterministic: w × h × 4 bytes.
    func hold(width: Int, height: Int, count: Int, from url: URL) -> (Double, Double) {
        let base = residentMB()
        var contexts: [CGContext] = []
        var source: CGImageSource?
        for _ in 0..<count {
            if source == nil {
                source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
            }
            let image = CGImageSourceCreateImageAtIndex(source!, 0, nil)!
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            contexts.append(context)
        }
        _ = contexts.map { $0.data }
        let delta = residentMB() - base
        contexts.removeAll()
        return (delta, delta / Double(count))
    }
    let full = hold(width: 3200, height: 2400, count: 6, from: pngURL)
    print(String(format: "  6 × original-sized bitmaps (3200×2400): +%.0f MB (%.0f MB each)", full.0, full.1))
    let mid = hold(width: 476, height: 357, count: 200, from: jpgURL)
    print(String(format: "  200 × card-sized bitmaps (476×357):     +%.0f MB (%.2f MB each)", mid.0, mid.1))
    let small = hold(width: 240, height: 180, count: 200, from: jpgURL)
    print(String(format: "  200 × small bitmaps (240×180):          +%.0f MB (%.2f MB each)", small.0, small.1))

    for url in [pngURL, jpgURL] { try? FileManager.default.removeItem(at: url) }
}

// ---------------------------------------------------------------------------
// Run
// ---------------------------------------------------------------------------

print("Canta interaction-cost benchmark — \(ProcessInfo.processInfo.operatingSystemVersionString)")
print("synthetic library; per-call best-of-11; 16.7 ms = one 60 Hz frame\n")

section("Current filteredPins — computed property re-read several times per body pass")
print("  (N = pins in the library)")
var cached: [Int: StoreLogic] = [:]
for n in [200, 1000, 3000, 5000] {
    let pins = makePins(n)
    var store = StoreLogic(pins: pins)
    cached[n] = store

    _ = bench("N=\(n)  filteredPins (all · recent sort)") { _ = store.filteredPins }
    store.selectedBoard = "Web dashboards"
    _ = bench("N=\(n)  filteredPins (board filter)") { _ = store.filteredPins }
    store.selectedBoard = nil
    store.searchText = "dark ui pricing"
    _ = bench("N=\(n)  filteredPins (search, 3 tokens)") { _ = store.filteredPins }
    store.searchText = ""

    let bodyPass = bench("N=\(n)  one LibraryView body pass (data layer only)") {
        var total = 0
        total += store.filteredPins.count   // if store.filteredPins.isEmpty
        total += store.filteredPins.count   // ForEach(store.filteredPins)
        total += store.filteredPins.count   // "%ld shown"
        total += store.favoriteCount
        total += store.screenshotCount
        total += store.boardSummaries.count
        for board in store.boardSummaries { _ = store.representative(for: board.name) }
        if total < 0 { print(total) }
    }
    let switchBoard = bench("N=\(n)  board switch (data work only)") {
        var s = store
        s.selectedBoard = "Mobile flows"
        _ = s.filteredPins.count
        _ = s.boardSummaries.count
    }
    let arrowKey = bench("N=\(n)  ← / → adjacent pin (data work only)") {
        _ = store.adjacentID(offset: 1, current: pins[0].id)
    }
    print(String(format: "    body pass %.1f ms · board switch %.1f ms · arrow key %.1f ms",
                 bodyPass, switchBoard, arrowKey))
}

section("Proposed snapshot projection — O(1) reads, memoised query")
for n in [200, 1000, 3000, 5000] {
    let pins = makePins(n)
    var projection: GalleryProjection!
    let build = bench("N=\(n)  build projection (once, at load)") { projection = GalleryProjection(pins: pins) }
    _ = bench("N=\(n)  first query with search text (cold)") {
        globalChecksum &+= projection.orderedIDs(section: "all", board: nil, filter: "all", sort: "recent", needle: "dark ui pricing").count
    }
    _ = bench("N=\(n)  repeat same query (memo hit, what body reads)") {
        globalChecksum &+= projection.orderedIDs(section: "all", board: nil, filter: "all", sort: "recent", needle: "dark ui pricing").count
    }
    _ = bench("N=\(n)  board switch (cold, distinct query)") {
        globalChecksum &+= projection.orderedIDs(section: "all", board: "Mobile flows", filter: "all", sort: "recent", needle: "").count
    }
    _ = bench("N=\(n)  board switch (memo hit)") {
        globalChecksum &+= projection.orderedIDs(section: "all", board: "Mobile flows", filter: "all", sort: "recent", needle: "").count
    }
    for typing in ["d", "da", "dar", "dark", "dark ", "dark u", "dark ui"] {
        globalChecksum &+= projection.orderedIDs(section: "all", board: nil, filter: "all", sort: "recent", needle: typing).count
    }
    let keystroke = bench("N=\(n)  typing one more character (distinct query)") {
        globalChecksum &+= projection.orderedIDs(section: "all", board: nil, filter: "all", sort: "recent", needle: "dark uix").count
    }
    _ = bench("N=\(n)  selected pin lookup by UUID") { globalChecksum &+= projection.index(of: pins[n / 2].id) ?? 0 }
    print(String(format: "    build once %.1f ms · keystroke %.2f ms", build, keystroke))
}

let pins1000 = makePins(1000)
measureKeystroke(pins1000)
measurePersistence(pins1000)
measurePersistence(makePins(3000))
measureDecode(makePins(1000))
measureDecode(makePins(3000))
measureThumbnailURL(makePins(1000))
measureStat()
measureImages()

print("\nchecksum \(globalChecksum)")
print("done")

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
