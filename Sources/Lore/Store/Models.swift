import Foundation
import LoreAgentKit

enum PinKind: String, Codable, CaseIterable {
    case screenshot
    case image
    case svg

    var label: String {
        switch self {
        case .screenshot: return T("Screenshot")
        case .image: return T("Image")
        case .svg: return T("SVG")
        }
    }

    var icon: String {
        switch self {
        case .screenshot: return "macwindow"
        case .image: return "photo"
        case .svg: return "chevron.left.forwardslash.chevron.right"
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
    /// Auto-detected hue families, ordered by coverage. Nil means the pin
    /// predates colour analysis; `colorProfile` falls back to the palette.
    var colorFamilies: [LoreColorFamily]?
    var colorTone: LoreColorTone?
    /// True when the original image has multiple frames (a GIF today).
    var isAnimated: Bool
    var frameCount: Int

    enum CodingKeys: String, CodingKey {
        case id, title, note, image, thumbnail, width, height, fileSize, createdAt, updatedAt
        case tags, board, sourceURL, sourceLabel, colors, kind
        case colorFamilies, colorTone, frameCount
        case isAnimated = "animated"
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
        kind: PinKind = .screenshot,
        colorFamilies: [LoreColorFamily]? = nil,
        colorTone: LoreColorTone? = nil,
        isAnimated: Bool = false,
        frameCount: Int = 1
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
        self.colorFamilies = colorFamilies
        self.colorTone = colorTone
        self.isAnimated = isAnimated
        self.frameCount = max(frameCount, 1)
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
        colorFamilies = try container.decodeIfPresent([String].self, forKey: .colorFamilies)?
            .compactMap(LoreColorFamily.parse)
            .filter { $0 != .multicolor }
        colorTone = try container.decodeIfPresent(String.self, forKey: .colorTone)
            .flatMap(LoreColorTone.parse)
        isAnimated = try container.decodeIfPresent(Bool.self, forKey: .isAnimated) ?? false
        frameCount = max(try container.decodeIfPresent(Int.self, forKey: .frameCount) ?? 1, 1)
    }

    var aspectRatio: CGFloat {
        CGFloat(width) / CGFloat(max(height, 1))
    }

    /// Stored image analysis, or a palette-derived estimate for pins created
    /// before colour families existed. The real image-based value lands via
    /// `ColorProfileBackfill` shortly after launch.
    var colorProfile: LoreColorProfile {
        if let colorFamilies, !colorFamilies.isEmpty {
            // Backfilled pins pay no palette work on the read path. A missing
            // tone (older Agent write) still falls back to the palette.
            return LoreColorProfile(
                families: colorFamilies,
                tone: colorTone ?? LoreColorAnalyzer.classify(palette: colors).tone
            )
        }
        let analyzed = LoreColorAnalyzer.classify(palette: colors)
        guard let colorTone else { return analyzed }
        return LoreColorProfile(
            families: analyzed.families,
            tone: colorTone,
            neutralShare: analyzed.neutralShare,
            accentChroma: analyzed.accentChroma,
            confidence: analyzed.confidence
        )
    }

    var pixelLabel: String { "\(width) × \(height)" }

    var isGIF: Bool {
        (image as NSString).pathExtension.caseInsensitiveCompare("gif") == .orderedSame
    }

    /// True when the stored original is vector markup. Extension-based so pins
    /// written by an older app or the Agent API still get the vector treatment.
    var isSVG: Bool {
        (image as NSString).pathExtension.caseInsensitiveCompare("svg") == .orderedSame
    }

    /// Icon/label for the image type badge. GIFs win over screenshot/image so
    /// animated references are recognisable at a glance.
    var mediaIcon: String {
        if isGIF { return "play.rectangle.fill" }
        if isSVG { return PinKind.svg.icon }
        return kind.icon
    }

    var mediaLabel: String {
        if isGIF {
            return frameCount > 1 ? TF("GIF · %ld frames", frameCount) : T("GIF")
        }
        if isSVG { return T("SVG") }
        return kind.label
    }

    var byteLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }

    var displayTypeLabel: String {
        if let sourceLabel, !sourceLabel.isEmpty {
            return sourceLabel == "Lore Seed" ? T("Lore Seed") : sourceLabel
        }
        return kind.label
    }
}

struct LoreLibrary: Codable {
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

/// What a board's sidebar/header logo should draw right now. `paths` are image
/// candidates in the same order `LibraryImage` expects; `isCustom` tells the
/// badge whether to crop the image (a pin thumbnail fills a square) or fit it
/// with breathing room (an uploaded wordmark usually should not be cropped).
struct BoardLogoDisplay: Equatable {
    var paths: [String]
    var isCustom: Bool
    var pinID: UUID?
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
        case .all: return T("All pins")
        case .favorites: return T("Favorites")
        case .recent: return T("Recent")
        case .agent: return T("Agent access")
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
        case .all: return T("All")
        case .screenshots: return T("Screenshots")
        case .favorites: return T("Favorites")
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
        case .recent: return T("Recently added")
        case .oldest: return T("Oldest first")
        case .title: return T("A–Z")
        }
    }
}