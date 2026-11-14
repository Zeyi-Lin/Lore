import Foundation

/// Errors raised while validating or persisting an uploaded pin. They map to
/// precise JSON error responses in AgentRouter.
enum PinIngestError: Error {
    case malformedJSON(String)
    case missingImage(String)
    case invalidImageData(String)
    case invalidMetadata(String)
    case unsupportedMediaType(String)
    case storageFailure(String)
    case pinNotFound(String)
}

/// A validated upload request, independent of HTTP representation.
struct NewPinRequest {
    var imageData: Data
    var declaredMimeType: String?
    var title: String?
    var note: String?
    var board: String?
    var tags: [String]
    var sourceURL: String?
    var sourceLabel: String?
    var kind: String?
    var favorite: Bool?
}

/// One field of a metadata update: either a new value, or an explicit clear
/// (JSON null) for nullable fields.
enum PatchValue<Value> {
    case set(Value)
    case clear
}

/// A partial pin metadata update. Every property is `nil` when the field was
/// absent from the request, so a PATCH only touches what it names.
struct PinMetadataPatch {
    var title: String?
    var note: PatchValue<String>?
    var board: PatchValue<String>?
    var tags: PatchValue<[String]>?
    var sourceURL: PatchValue<String>?
    var sourceLabel: PatchValue<String>?
    var favorite: Bool?
    var kind: String?
}

/// Serializes writes into the Lore library and performs the full ingest
/// pipeline: image validation, asset writes, atomic library.json update, and
/// an onLibraryChanged notification.
final class LibraryIngestor {
    let root: URL
    private let store: LibraryStore
    private let queue = DispatchQueue(label: "com.lore.agent-server.ingest")
    /// Invoked on the ingest queue after library.json has been written.
    var onLibraryChanged: (@Sendable () -> Void)?

    init(root: URL) {
        let standardizedRoot = root.standardizedFileURL
        self.root = standardizedRoot
        self.store = LibraryStore(root: standardizedRoot)
    }

    func createPin(_ request: NewPinRequest) throws -> LorePinRecord {
        try queue.sync {
            try createPinLocked(request)
        }
    }

    /// Applies a partial metadata update to an existing pin and rewrites
    /// library.json atomically. Only metadata is touched: image assets,
    /// dimensions, palette, id, and createdAt are preserved.
    func updatePin(id: String, patch: PinMetadataPatch) throws -> LorePinRecord {
        try queue.sync {
            let library = try store.loadLibrary()
            guard let index = library.pins.firstIndex(where: { $0.id == id }) else {
                throw PinIngestError.pinNotFound(id)
            }
            var pins = library.pins
            let updated = Self.applying(patch, to: pins[index])
            pins[index] = updated
            let updatedLibrary = LoreLibraryFile(version: library.version, pins: pins)
            do {
                let encoded = try JSONCoding.encodePretty(updatedLibrary)
                try encoded.write(to: store.libraryFileURL, options: [.atomic])
            } catch {
                throw PinIngestError.storageFailure("The pin metadata could not be saved: \(error.localizedDescription)")
            }
            onLibraryChanged?()
            return updated
        }
    }

    private static func applying(_ patch: PinMetadataPatch, to pin: LorePinRecord) -> LorePinRecord {
        let title = patch.title.flatMap(normalizedText) ?? pin.title
        let note: String
        switch patch.note {
        case .none: note = pin.note
        case .clear: note = ""
        case .set(let value): note = normalizedText(value) ?? ""
        }
        let board: String
        switch patch.board {
        case .none: board = pin.board
        case .clear: board = "Unsorted"
        case .set(let value): board = normalizedText(value) ?? "Unsorted"
        }
        let tags: [String]
        switch patch.tags {
        case .none: tags = pin.tags
        case .clear: tags = []
        case .set(let values): tags = normalizedTags(values)
        }
        let sourceURL: String?
        switch patch.sourceURL {
        case .none: sourceURL = pin.sourceURL
        case .clear: sourceURL = nil
        case .set(let value): sourceURL = normalizedText(value)
        }
        let sourceLabel: String?
        switch patch.sourceLabel {
        case .none: sourceLabel = pin.sourceLabel
        case .clear: sourceLabel = nil
        case .set(let value): sourceLabel = normalizedText(value)
        }
        return LorePinRecord(
            id: pin.id,
            title: title,
            note: note,
            image: pin.image,
            thumbnail: pin.thumbnail,
            width: pin.width,
            height: pin.height,
            fileSize: pin.fileSize,
            createdAt: pin.createdAt,
            updatedAt: Timestamp.nowString(),
            tags: tags,
            board: board,
            sourceURL: sourceURL,
            sourceLabel: sourceLabel,
            colors: pin.colors,
            favorite: patch.favorite ?? pin.favorite,
            kind: patch.kind ?? pin.kind,
            colorFamilies: pin.colorFamilies,
            colorTone: pin.colorTone,
            isAnimated: pin.isAnimated,
            frameCount: pin.frameCount
        )
    }

    private func createPinLocked(_ request: NewPinRequest) throws -> LorePinRecord {
        // Validate and process the image entirely in memory first.
        let processed = try ImageIngestProcessor.process(request.imageData, declaredMimeType: request.declaredMimeType)

        // Load the current library before writing assets so a missing or
        // corrupt library cannot leave orphan image files behind.
        let library = try store.loadLibrary()

        let fileManager = FileManager.default
        let imagesDirectory = root.appendingPathComponent("Images", isDirectory: true)
        let thumbnailsDirectory = root.appendingPathComponent("Thumbnails", isDirectory: true)
        do {
            try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        } catch {
            throw PinIngestError.storageFailure("The Lore image directories could not be created: \(error.localizedDescription)")
        }

        let identifier = UUID().uuidString
        let imageRelativePath = "Images/\(identifier).\(processed.fileExtension)"
        let thumbnailRelativePath = "Thumbnails/\(identifier).jpg"
        let imageURL = root.appendingPathComponent(imageRelativePath)
        let thumbnailURL = root.appendingPathComponent(thumbnailRelativePath)
        guard Self.isContained(imageURL, in: root), Self.isContained(thumbnailURL, in: root) else {
            throw PinIngestError.storageFailure("The generated asset paths were invalid.")
        }

        let timestamp = Timestamp.nowString()
        let record = LorePinRecord(
            id: identifier,
            title: Self.normalizedTitle(request.title),
            note: Self.normalizedText(request.note) ?? "",
            image: imageRelativePath,
            thumbnail: thumbnailRelativePath,
            width: processed.width,
            height: processed.height,
            fileSize: processed.originalData.count,
            createdAt: timestamp,
            updatedAt: timestamp,
            tags: Self.normalizedTags(request.tags),
            board: Self.normalizedText(request.board) ?? "Unsorted",
            sourceURL: Self.normalizedText(request.sourceURL),
            sourceLabel: Self.normalizedText(request.sourceLabel) ?? "Agent API",
            colors: processed.colors,
            favorite: request.favorite ?? false,
            kind: Self.normalizedText(request.kind) ?? (processed.isAnimated ? "image" : "screenshot"),
            colorFamilies: processed.colorFamilies,
            colorTone: processed.colorTone,
            isAnimated: processed.isAnimated,
            frameCount: processed.frameCount
        )

        do {
            try processed.originalData.write(to: imageURL, options: [.atomic])
        } catch {
            throw PinIngestError.storageFailure("The original image could not be written: \(error.localizedDescription)")
        }

        do {
            try processed.thumbnailJPEG.write(to: thumbnailURL, options: [.atomic])
            let updatedLibrary = LoreLibraryFile(version: library.version, pins: library.pins + [record])
            let encoded = try JSONCoding.encodePretty(updatedLibrary)
            try encoded.write(to: store.libraryFileURL, options: [.atomic])
        } catch {
            try? fileManager.removeItem(at: imageURL)
            try? fileManager.removeItem(at: thumbnailURL)
            if let ingestError = error as? PinIngestError {
                throw ingestError
            }
            throw PinIngestError.storageFailure("The pin could not be saved: \(error.localizedDescription)")
        }

        onLibraryChanged?()
        return record
    }

    // MARK: - Metadata normalization

    private static let defaultTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static func normalizedTitle(_ title: String?) -> String {
        if let title = normalizedText(title) {
            return title
        }
        return "Agent capture · " + defaultTitleFormatter.string(from: Date())
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, normalized.count <= 64 else { continue }
            if seen.insert(normalized).inserted {
                result.append(normalized)
            }
            if result.count >= 50 { break }
        }
        return result
    }

    private static func isContained(_ candidate: URL, in root: URL) -> Bool {
        let rootPath = root.path
        let candidatePath = candidate.path
        if candidatePath == rootPath { return true }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return candidatePath.hasPrefix(prefix)
    }
}
