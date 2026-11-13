import Foundation

enum PinKind: String, Codable, CaseIterable {
    case screenshot
    case image

    var label: String {
        switch self {
        case .screenshot: return "Screenshot"
        case .image: return "Image"
        }
    }

    var icon: String {
        switch self {
        case .screenshot: return "macwindow"
        case .image: return "photo"
        }
    }
}

struct Pin: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var note: String
    var image: String
    var thumbnail: String?
    var width: Int
    var height: Int
    var fileSize: Int
    var createdAt: Date
    var updatedAt: Date
    var tags: [String]
    var board: String
    var sourceURL: String?
    var sourceLabel: String?
    var colors: [String]
    var isFavorite: Bool
    var kind: PinKind

    enum CodingKeys: String, CodingKey {
        case id, title, note, image, thumbnail, width, height, fileSize, createdAt, updatedAt
        case tags, board, sourceURL, sourceLabel, colors, kind
        case isFavorite = "favorite"
    }

    init(
        id: UUID = UUID(),
        title: String,
        note: String = "",
        image: String,
        thumbnail: String? = nil,
        width: Int,
        height: Int,
        fileSize: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        tags: [String] = [],
        board: String = "Unsorted",
        sourceURL: String? = nil,
        sourceLabel: String? = nil,
        colors: [String] = [],
        isFavorite: Bool = false,
        kind: PinKind = .screenshot
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.image = image
        self.thumbnail = thumbnail
        self.width = max(width, 1)
        self.height = max(height, 1)
        self.fileSize = fileSize
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
        self.board = board
        self.sourceURL = sourceURL
        self.sourceLabel = sourceLabel
        self.colors = colors
        self.isFavorite = isFavorite
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled pin"
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        image = try container.decode(String.self, forKey: .image)
        thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
        width = max(try container.decodeIfPresent(Int.self, forKey: .width) ?? 1200, 1)
        height = max(try container.decodeIfPresent(Int.self, forKey: .height) ?? 800, 1)
        fileSize = try container.decodeIfPresent(Int.self, forKey: .fileSize) ?? 0
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        board = try container.decodeIfPresent(String.self, forKey: .board) ?? "Unsorted"
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        sourceLabel = try container.decodeIfPresent(String.self, forKey: .sourceLabel)
        colors = try container.decodeIfPresent([String].self, forKey: .colors) ?? []
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        kind = try container.decodeIfPresent(PinKind.self, forKey: .kind) ?? .screenshot
    }

    var aspectRatio: CGFloat {
        CGFloat(width) / CGFloat(max(height, 1))
    }

    var pixelLabel: String { "\(width) × \(height)" }

    var byteLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }

    var displayTypeLabel: String {
        if let sourceLabel, !sourceLabel.isEmpty { return sourceLabel }
        return kind.label
    }
}

struct CantaLibrary: Codable {
    var version: Int
    var pins: [Pin]

    init(version: Int = 1, pins: [Pin] = []) {
        self.version = version
        self.pins = pins
    }
}

struct BoardSummary: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let count: Int
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var icon: String = "checkmark"
}

enum LibrarySection: String, CaseIterable, Identifiable {
    case all
    case favorites
    case recent
    case agent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All pins"
        case .favorites: return "Favorites"
        case .recent: return "Recent"
        case .agent: return "Agent access"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .favorites: return "heart"
        case .recent: return "clock"
        case .agent: return "sparkles"
        }
    }
}

enum GalleryFilter: String, CaseIterable, Identifiable {
    case all
    case screenshots
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .screenshots: return "Screenshots"
        case .favorites: return "Favorites"
        }
    }
}

enum PinSort: String, CaseIterable, Identifiable {
    case recent
    case oldest
    case title

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return "Recently added"
        case .oldest: return "Oldest first"
        case .title: return "A–Z"
        }
    }
}
