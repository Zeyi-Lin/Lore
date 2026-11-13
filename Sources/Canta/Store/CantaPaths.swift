import Foundation

enum CantaPaths {
    static var dataRoot: URL {
        if let override = ProcessInfo.processInfo.environment["CANTA_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Canta", isDirectory: true)
    }

    static func imagesDirectory(root: URL) -> URL {
        root.appendingPathComponent("Images", isDirectory: true)
    }

    static func thumbnailsDirectory(root: URL) -> URL {
        root.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    static func libraryFile(root: URL) -> URL {
        root.appendingPathComponent("library.json")
    }

    static func ensureDirectories(root: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: imagesDirectory(root: root), withIntermediateDirectories: true)
        try fm.createDirectory(at: thumbnailsDirectory(root: root), withIntermediateDirectories: true)
    }
}

enum CantaJSON {
    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = iso8601.date(from: string) ?? iso8601Fractional.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(string)")
        }
        return decoder
    }()
}
