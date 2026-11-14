import Foundation
import Darwin

// MARK: - Public constants

/// Identifiers and defaults for the embedded Canta Agent API.
public enum CantaAgentAPI {
    /// Product name reported by the health endpoint.
    public static let appName = "Canta"
    /// API generation reported by the health endpoint.
    public static let apiVersion = "v1"
    /// Version of the Agent API implementation.
    public static let version = "1.0.0"
    /// Default loopback port used by the Canta app.
    public static let defaultPort: UInt16 = 4242
    /// Maximum accepted request body for image ingestion (20 MiB).
    public static let maxUploadBytes = 20 * 1024 * 1024
}

// MARK: - Library file model

struct CantaLibraryFile: Codable {
    var version: Int
    var pins: [CantaPinRecord]

    enum CodingKeys: String, CodingKey {
        case version
        case pins
    }

    init(version: Int = 1, pins: [CantaPinRecord]) {
        self.version = version
        self.pins = pins
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(pins, forKey: .pins)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? container.decode(Int.self, forKey: .version)) ?? 1
        if container.contains(.pins) && (try? container.decodeNil(forKey: .pins)) == false {
            pins = try container.decode([CantaPinRecord].self, forKey: .pins)
        } else {
            pins = []
        }
    }
}

/// A pin exactly as persisted by the Canta app in library.json. All fields are
/// preserved for API output; only \`id\` is strictly required, so the kit can
/// tolerate additive schema changes from newer app versions.
struct CantaPinRecord: Codable {
    let id: String
    let title: String
    let note: String
    let image: String
    let thumbnail: String?
    let width: Int
    let height: Int
    let fileSize: Int
    let createdAt: String
    let updatedAt: String
    let tags: [String]
    let board: String
    let sourceURL: String?
    let sourceLabel: String?
    let colors: [String]
    let favorite: Bool
    let kind: String

    enum CodingKeys: String, CodingKey {
        case id, title, note, image, thumbnail, width, height, fileSize
        case createdAt, updatedAt, tags, board, sourceURL, sourceLabel, colors
        case favorite, kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawID = try container.decode(String.self, forKey: .id)
        let trimmedID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Pin id must not be empty.")
        }
        id = trimmedID
        title = Self.string(container, .title)
        note = Self.string(container, .note)
        image = Self.string(container, .image)
        thumbnail = Self.optionalString(container, .thumbnail)
        width = Self.integer(container, .width)
        height = Self.integer(container, .height)
        fileSize = Self.integer(container, .fileSize)
        createdAt = Self.string(container, .createdAt)
        updatedAt = Self.string(container, .updatedAt)
        tags = Self.stringArray(container, .tags)
        board = Self.string(container, .board)
        sourceURL = Self.optionalString(container, .sourceURL)
        sourceLabel = Self.optionalString(container, .sourceLabel)
        colors = Self.stringArray(container, .colors)
        favorite = (try? container.decode(Bool.self, forKey: .favorite)) ?? false
        kind = Self.string(container, .kind, default: "screenshot")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(note, forKey: .note)
        try container.encode(image, forKey: .image)
        try container.encode(thumbnail, forKey: .thumbnail)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(fileSize, forKey: .fileSize)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(tags, forKey: .tags)
        try container.encode(board, forKey: .board)
        try container.encode(sourceURL, forKey: .sourceURL)
        try container.encode(sourceLabel, forKey: .sourceLabel)
        try container.encode(colors, forKey: .colors)
        try container.encode(favorite, forKey: .favorite)
        try container.encode(kind, forKey: .kind)
    }

    init(
        id: String,
        title: String,
        note: String,
        image: String,
        thumbnail: String?,
        width: Int,
        height: Int,
        fileSize: Int,
        createdAt: String,
        updatedAt: String,
        tags: [String],
        board: String,
        sourceURL: String?,
        sourceLabel: String?,
        colors: [String],
        favorite: Bool,
        kind: String
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.image = image
        self.thumbnail = thumbnail
        self.width = width
        self.height = height
        self.fileSize = fileSize
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
        self.board = board
        self.sourceURL = sourceURL
        self.sourceLabel = sourceLabel
        self.colors = colors
        self.favorite = favorite
        self.kind = kind
    }

    private static func string(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys, default defaultValue: String = "") -> String {
        (try? container.decode(String.self, forKey: key)) ?? defaultValue
    }

    private static func optionalString(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        guard let value = try? container.decodeIfPresent(String.self, forKey: key) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }

    private static func integer(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int {
        (try? container.decode(Int.self, forKey: key)) ?? 0
    }

    private static func stringArray(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [String] {
        (try? container.decode([String].self, forKey: key)) ?? []
    }

    var createdDate: Date? {
        Timestamp.date(from: createdAt)
    }

    var updatedDate: Date? {
        Timestamp.date(from: updatedAt)
    }

    func originalImageURL(baseURL: String) -> String? {
        guard !image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return baseURL + "/api/v1/pins/" + PercentCoding.encodePathSegment(id) + "/image?variant=original"
    }

    func thumbnailImageURL(baseURL: String) -> String? {
        guard let thumbnail, !thumbnail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return baseURL + "/api/v1/pins/" + PercentCoding.encodePathSegment(id) + "/image?variant=thumb"
    }

    func enriched(baseURL: String) -> EnrichedPin {
        EnrichedPin(
            id: id,
            title: title,
            note: note,
            image: image,
            thumbnail: thumbnail,
            width: width,
            height: height,
            fileSize: fileSize,
            createdAt: createdAt,
            updatedAt: updatedAt,
            tags: tags,
            board: board,
            sourceURL: sourceURL,
            sourceLabel: sourceLabel,
            colors: colors,
            favorite: favorite,
            kind: kind,
            imageURL: originalImageURL(baseURL: baseURL),
            thumbnailURL: thumbnailImageURL(baseURL: baseURL)
        )
    }
}

/// A pin as returned by the API: every persisted field plus absolute,
/// loopback-only image URLs resolved against the actual bound port.
struct EnrichedPin: Encodable {
    let id: String
    let title: String
    let note: String
    let image: String
    let thumbnail: String?
    let width: Int
    let height: Int
    let fileSize: Int
    let createdAt: String
    let updatedAt: String
    let tags: [String]
    let board: String
    let sourceURL: String?
    let sourceLabel: String?
    let colors: [String]
    let favorite: Bool
    let kind: String
    let imageURL: String?
    let thumbnailURL: String?

    enum CodingKeys: String, CodingKey {
        case id, title, note, image, thumbnail, width, height, fileSize
        case createdAt, updatedAt, tags, board, sourceURL, sourceLabel, colors
        case favorite, kind, imageURL, thumbnailURL
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(note, forKey: .note)
        try container.encode(image, forKey: .image)
        try container.encode(thumbnail, forKey: .thumbnail)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(fileSize, forKey: .fileSize)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(tags, forKey: .tags)
        try container.encode(board, forKey: .board)
        try container.encode(sourceURL, forKey: .sourceURL)
        try container.encode(sourceLabel, forKey: .sourceLabel)
        try container.encode(colors, forKey: .colors)
        try container.encode(favorite, forKey: .favorite)
        try container.encode(kind, forKey: .kind)
        try container.encode(imageURL, forKey: .imageURL)
        try container.encode(thumbnailURL, forKey: .thumbnailURL)
    }
}

// MARK: - Aggregates and API envelopes

struct LibraryStats: Codable, Equatable {
    let pins: Int
    let boards: Int
    let tags: Int
    let favorites: Int
    let images: Int

    init(pins: [CantaPinRecord]) {
        self.pins = pins.count
        self.boards = Set(pins.map { $0.board.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).count
        self.tags = Set(pins.flatMap { $0.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }.filter { !$0.isEmpty }).count
        self.favorites = pins.filter { $0.favorite }.count
        self.images = pins.filter { !$0.image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }
}

struct NamedCount: Codable, Equatable {
    let name: String
    let count: Int
}

struct HealthResponse: Encodable {
    let status: String
    let app: String
    let api: String
    let version: String
    let pinCount: Int
    let port: Int
}

struct LibraryResponse: Encodable {
    let app: String
    let version: String
    let generatedAt: String
    let stats: LibraryStats
    let boards: [NamedCount]
    let tags: [NamedCount]
    let pins: [EnrichedPin]
}

struct PinListResponse: Encodable {
    let count: Int
    let total: Int
    let offset: Int
    let limit: Int
    let pins: [EnrichedPin]
}

struct BoardsResponse: Encodable {
    let boards: [NamedCount]
}

struct TagsResponse: Encodable {
    let tags: [NamedCount]
}

// MARK: - Query model

enum PinSort: String {
    case recent
    case oldest
    case title
}

struct PinQuery {
    var search: String?
    var tag: String?
    var board: String?
    var favorite: Bool?
    var kind: String?
    var sort: PinSort = .recent
    var limit: Int = 50
    var offset: Int = 0
}

// MARK: - Store

enum LibraryStoreError: Error {
    case unavailable(String)
    case corrupt(String)
    case imageNotFound(String)
    case forbidden(String)
}

enum ImageVariant: String {
    case original
    case thumb
}

struct ResolvedImage {
    let data: Data
    let contentType: String
}

struct LibraryFileStamp: Equatable, Sendable {
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let inode: UInt64
}

/// Reads the Canta library from disk. Requests within the same file version
/// reuse a decoded snapshot; any write (atomic replace, app edit, Agent POST)
/// changes the stat stamp and forces a fresh decode.
final class LibraryStore {
    let root: URL

    private let cacheLock = NSLock()
    private var cachedStamp: LibraryFileStamp?
    private var cachedLibrary: CantaLibraryFile?

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    var libraryFileURL: URL {
        root.appendingPathComponent("library.json", isDirectory: false)
    }

    func libraryFileStamp() -> LibraryFileStamp? {
        var fileInfo = stat()
        let status = libraryFileURL.path.withCString { path in
            stat(path, &fileInfo)
        }
        guard status == 0 else { return nil }
        return LibraryFileStamp(
            size: Int64(fileInfo.st_size),
            modifiedSeconds: Int64(fileInfo.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(fileInfo.st_mtimespec.tv_nsec),
            inode: UInt64(fileInfo.st_ino)
        )
    }

    func loadLibrary() throws -> CantaLibraryFile {
        let fileURL = libraryFileURL
        guard let stamp = libraryFileStamp() else {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                throw LibraryStoreError.unavailable("The Canta library file was not found. Open Canta and save at least one pin, then try again.")
            }
            throw LibraryStoreError.unavailable("Canta could not read library.json.")
        }

        cacheLock.lock()
        if cachedStamp == stamp, let cachedLibrary {
            let library = cachedLibrary
            cacheLock.unlock()
            return library
        }
        cacheLock.unlock()

        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        } catch {
            throw LibraryStoreError.unavailable("Canta could not read library.json: \(error.localizedDescription)")
        }
        do {
            let library = try JSONDecoder().decode(CantaLibraryFile.self, from: data)
            cacheLock.lock()
            cachedStamp = stamp
            cachedLibrary = library
            cacheLock.unlock()
            return library
        } catch let error as DecodingError {
            invalidateCache()
            throw LibraryStoreError.corrupt("library.json is not valid: \(Self.describe(error))")
        } catch {
            invalidateCache()
            throw LibraryStoreError.corrupt("library.json could not be decoded: \(error.localizedDescription)")
        }
    }

    private func invalidateCache() {
        cacheLock.lock()
        cachedStamp = nil
        cachedLibrary = nil
        cacheLock.unlock()
    }

    func enrichedPins(baseURL: String) throws -> [EnrichedPin] {
        try loadLibrary().pins.map { $0.enriched(baseURL: baseURL) }
    }

    func stats() throws -> LibraryStats {
        LibraryStats(pins: try loadLibrary().pins)
    }

    func boardCounts() throws -> [NamedCount] {
        Self.boardCounts(for: try loadLibrary().pins)
    }

    func tagCounts() throws -> [NamedCount] {
        Self.tagCounts(for: try loadLibrary().pins)
    }

    static func boardCounts(for pins: [CantaPinRecord]) -> [NamedCount] {
        countValues(pins.map { $0.board })
    }

    static func tagCounts(for pins: [CantaPinRecord]) -> [NamedCount] {
        countValues(pins.flatMap { $0.tags })
    }

    func searchPins(matching query: PinQuery) throws -> [CantaPinRecord] {
        Self.searchPins(in: try loadLibrary().pins, matching: query)
    }

    static func searchPins(in allPins: [CantaPinRecord], matching query: PinQuery) -> [CantaPinRecord] {
        let search = query.search?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tag = query.tag?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let board = query.board?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let kind = query.kind?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filtered = allPins.filter { pin in
            if let search, !search.isEmpty {
                let haystack = [
                    pin.title,
                    pin.note,
                    pin.board,
                    pin.sourceLabel ?? "",
                    pin.kind,
                    pin.tags.joined(separator: " "),
                    pin.colors.joined(separator: " ")
                ].joined(separator: " ").lowercased()
                if !haystack.contains(search) { return false }
            }
            if let tag, !tag.isEmpty {
                if !pin.tags.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == tag }) { return false }
            }
            if let board, !board.isEmpty {
                if pin.board.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != board { return false }
            }
            if let favorite = query.favorite, pin.favorite != favorite { return false }
            if let kind, !kind.isEmpty {
                if pin.kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != kind { return false }
            }
            return true
        }
        return Self.sorted(filtered, by: query.sort)
    }

    func imageData(for pin: CantaPinRecord, variant: ImageVariant) throws -> ResolvedImage {
        switch variant {
        case .original:
            guard !pin.image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LibraryStoreError.imageNotFound("This pin has no original image.")
            }
            return try loadImage(relativePath: pin.image)
        case .thumb:
            if let thumbnail = pin.thumbnail, !thumbnail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let image = try? loadImage(relativePath: thumbnail) {
                    return image
                }
            }
            guard !pin.image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LibraryStoreError.imageNotFound("This pin has neither a thumbnail nor an original image.")
            }
            return try loadImage(relativePath: pin.image)
        }
    }

    /// Resolves a library-relative asset path, guaranteeing that the real file
    /// stays inside the configured library root (after symlink resolution).
    func resolveAssetPath(_ relativePath: String) throws -> URL {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LibraryStoreError.imageNotFound("The pin has no image path.")
        }
        guard !trimmed.hasPrefix("/") else {
            throw LibraryStoreError.forbidden("Absolute image paths are not allowed.")
        }
        guard !trimmed.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw LibraryStoreError.forbidden("Image paths may not contain NUL bytes.")
        }
        let rootStandard = root.standardizedFileURL
        let candidate = rootStandard.appendingPathComponent(trimmed).standardizedFileURL
        guard Self.isContained(candidate, in: rootStandard) else {
            throw LibraryStoreError.forbidden("Image paths may not escape the Canta library root.")
        }
        let rootResolved = rootStandard.resolvingSymlinksInPath()
        let resolvedCandidate = candidate.resolvingSymlinksInPath()
        guard Self.isContained(resolvedCandidate, in: rootResolved) else {
            throw LibraryStoreError.forbidden("Image paths may not escape the Canta library root through symbolic links.")
        }
        return resolvedCandidate
    }

    private func loadImage(relativePath: String) throws -> ResolvedImage {
        let fileURL = try resolveAssetPath(relativePath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw LibraryStoreError.imageNotFound("No image file exists for this pin.")
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        } catch {
            throw LibraryStoreError.imageNotFound("The pin image could not be read.")
        }
        guard !data.isEmpty else {
            throw LibraryStoreError.imageNotFound("The pin image is empty.")
        }
        let contentType = ImageType.detect(pathExtension: fileURL.pathExtension, data: data)
        return ResolvedImage(data: data, contentType: contentType)
    }

    private static func isContained(_ candidate: URL, in root: URL) -> Bool {
        let rootPath = root.path
        let candidatePath = candidate.path
        if candidatePath == rootPath { return true }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return candidatePath.hasPrefix(prefix)
    }

    private static func sorted(_ pins: [CantaPinRecord], by sort: PinSort) -> [CantaPinRecord] {
        switch sort {
        case .recent:
            let dates = creationDates(pins)
            return pins.sorted { lhs, rhs in
                let left = dates[lhs.id] ?? .distantPast
                let right = dates[rhs.id] ?? .distantPast
                if left != right { return left > right }
                return lhs.id < rhs.id
            }
        case .oldest:
            let dates = creationDates(pins)
            return pins.sorted { lhs, rhs in
                let left = dates[lhs.id] ?? .distantPast
                let right = dates[rhs.id] ?? .distantPast
                if left != right { return left < right }
                return lhs.id < rhs.id
            }
        case .title:
            return pins.sorted { lhs, rhs in
                let left = lhs.title.lowercased()
                let right = rhs.title.lowercased()
                if left != right { return left < right }
                return lhs.id < rhs.id
            }
        }
    }

    private static func creationDates(_ pins: [CantaPinRecord]) -> [String: Date] {
        var result: [String: Date] = [:]
        for pin in pins {
            if let date = pin.createdDate {
                result[pin.id] = date
            }
        }
        return result
    }

    private static func countValues(_ values: [String]) -> [NamedCount] {
        var counts: [String: Int] = [:]
        var displayName: [String: String] = [:]
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            counts[key, default: 0] += 1
            if displayName[key] == nil { displayName[key] = trimmed }
        }
        return counts.keys.compactMap { key -> NamedCount? in
            guard let name = displayName[key], let count = counts[key] else { return nil }
            return NamedCount(name: name, count: count)
        }.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.name.lowercased() < rhs.name.lowercased()
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        let path: String
        let detail: String
        switch error {
        case .keyNotFound(let key, let context):
            path = context.codingPath.map(\.stringValue).joined(separator: ".")
            detail = "missing required field \"\(key.stringValue)\" at \(path.isEmpty ? "root" : path)"
        case .typeMismatch(let type, let context):
            path = context.codingPath.map(\.stringValue).joined(separator: ".")
            detail = "expected \(type) at \(path.isEmpty ? "root" : path)"
        case .valueNotFound(let type, let context):
            path = context.codingPath.map(\.stringValue).joined(separator: ".")
            detail = "missing \(type) value at \(path.isEmpty ? "root" : path)"
        case .dataCorrupted(let context):
            path = context.codingPath.map(\.stringValue).joined(separator: ".")
            detail = "\(context.debugDescription) at \(path.isEmpty ? "root" : path)"
        @unknown default:
            detail = "unknown decoding error"
        }
        return detail
    }
}

// MARK: - Image typing

enum ImageType {
    static func detect(pathExtension: String, data: Data) -> String {
        if let magic = magicType(data) { return magic }
        switch pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic", "heif": return "image/heic"
        case "avif": return "image/avif"
        case "tif", "tiff": return "image/tiff"
        case "bmp": return "image/bmp"
        case "svg": return "image/svg+xml"
        case "ico": return "image/x-icon"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }

    private static func magicType(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(16))
        if bytes.count >= 8, bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47, bytes[4] == 0x0D, bytes[5] == 0x0A, bytes[6] == 0x1A, bytes[7] == 0x0A {
            return "image/png"
        }
        if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
            return "image/jpeg"
        }
        if bytes.count >= 6, bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x38 {
            return "image/gif"
        }
        if bytes.count >= 12, bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46, bytes[8] == 0x57, bytes[9] == 0x45, bytes[10] == 0x42, bytes[11] == 0x50 {
            return "image/webp"
        }
        if bytes.count >= 12, bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 {
            let brand = String(decoding: bytes[8..<12], as: UTF8.self)
            switch brand {
            case "avif", "avis": return "image/avif"
            case "heic", "heix", "hevc", "hevx", "mif1", "msf1": return "image/heic"
            default: break
            }
        }
        if bytes.count >= 4, bytes[0] == 0x49, bytes[1] == 0x49, bytes[2] == 0x2A, bytes[3] == 0x00 {
            return "image/tiff"
        }
        if bytes.count >= 4, bytes[0] == 0x4D, bytes[1] == 0x4D, bytes[2] == 0x00, bytes[3] == 0x2A {
            return "image/tiff"
        }
        if bytes.count >= 2, bytes[0] == 0x42, bytes[1] == 0x4D {
            return "image/bmp"
        }
        if bytes.count >= 4, bytes[0] == 0x25, bytes[1] == 0x50, bytes[2] == 0x44, bytes[3] == 0x46 {
            return "application/pdf"
        }
        return nil
    }
}
