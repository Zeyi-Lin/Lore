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

/// Serializes writes into the Canta library and performs the full ingest
/// pipeline: image validation, asset writes, atomic library.json update, and
/// an onLibraryChanged notification.
final class LibraryIngestor {
    let root: URL
    private let store: LibraryStore
    private let queue = DispatchQueue(label: "com.canta.agent-server.ingest")
    /// Invoked on the ingest queue after library.json has been written.
    var onLibraryChanged: (@Sendable () -> Void)?

    init(root: URL) {
        let standardizedRoot = root.standardizedFileURL
        self.root = standardizedRoot
        self.store = LibraryStore(root: standardizedRoot)
    }

    func createPin(_ request: NewPinRequest) throws -> CantaPinRecord {
        try queue.sync {
            try createPinLocked(request)
        }
    }

    private func createPinLocked(_ request: NewPinRequest) throws -> CantaPinRecord {
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
            throw PinIngestError.storageFailure("The Canta image directories could not be created: \(error.localizedDescription)")
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
        let record = CantaPinRecord(
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
            kind: Self.normalizedText(request.kind) ?? "screenshot"
        )

        do {
            try processed.originalData.write(to: imageURL, options: [.atomic])
        } catch {
            throw PinIngestError.storageFailure("The original image could not be written: \(error.localizedDescription)")
        }

        do {
            try processed.thumbnailJPEG.write(to: thumbnailURL, options: [.atomic])
            let updatedLibrary = CantaLibraryFile(version: library.version, pins: library.pins + [record])
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
