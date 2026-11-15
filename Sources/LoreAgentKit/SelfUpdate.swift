import Foundation

// MARK: - Semantic version

/// A deliberately small semver reader: the updater only needs to answer "is the
/// latest GitHub tag newer than the version this app is running?". It accepts
/// the tag shapes maintainers actually type — `v1.2.0`, `1.2`, `1.2.3+build`,
/// `1.2.3-beta.1` — and keeps prerelease ordering so a beta can never mask the
/// final build of the same version.
public struct SemanticVersion: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: [String]

    public init(major: Int, minor: Int, patch: Int, prerelease: [String] = []) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// Parses a release tag or bundle version. Returns `nil` for anything that
    /// is not a dotted numeric version, so a mistyped tag fails loudly instead
    /// of silently comparing as 0.0.0.
    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }
        // Build metadata is irrelevant to ordering; GitHub tags rarely carry it,
        // but `1.2.3+4` should still parse.
        if let plus = text.firstIndex(of: "+") {
            text = String(text[..<plus])
        }
        var prerelease: [String] = []
        if let dash = text.firstIndex(of: "-") {
            let suffix = String(text[text.index(after: dash)...])
            text = String(text[..<dash])
            guard !suffix.isEmpty else { return nil }
            prerelease = suffix.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard prerelease.allSatisfy({ !$0.isEmpty }) else { return nil }
        }

        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(pieces.count) else { return nil }
        var numbers: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty,
                  piece.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(piece) else { return nil }
            numbers.append(value)
        }
        while numbers.count < 3 { numbers.append(0) }
        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2], prerelease: prerelease)
    }

    public var description: String {
        var text = "\(major).\(minor).\(patch)"
        if !prerelease.isEmpty {
            text += "-" + prerelease.joined(separator: ".")
        }
        return text
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        // Precedence per semver §11: a prerelease sorts before the release, then
        // numeric identifiers compare numerically and lowercase identifiers
        // compare lexically (numeric always sorts first).
        if lhs.prerelease.isEmpty != rhs.prerelease.isEmpty {
            return !lhs.prerelease.isEmpty
        }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            let leftNumber = Int(left)
            let rightNumber = Int(right)
            switch (leftNumber, rightNumber) {
            case let (leftNumber?, rightNumber?):
                return leftNumber < rightNumber
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return left < right
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}

// MARK: - Release metadata

public struct UpdateAsset: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case diskImage
        case zip
        case other
    }

    public let name: String
    public let downloadURL: URL
    public let byteCount: Int

    public init(name: String, downloadURL: URL, byteCount: Int = 0) {
        self.name = name
        self.downloadURL = downloadURL
        self.byteCount = byteCount
    }

    public var kind: Kind {
        let lower = name.lowercased()
        if lower.hasSuffix(".dmg") { return .diskImage }
        if lower.hasSuffix(".zip") { return .zip }
        return .other
    }
}

public struct UpdateRelease: Sendable, Equatable {
    public let tag: String
    public let version: SemanticVersion
    public let title: String
    public let notes: String
    public let pageURL: URL
    public let publishedAt: Date?
    public let assets: [UpdateAsset]

    public init(
        tag: String,
        version: SemanticVersion,
        title: String,
        notes: String = "",
        pageURL: URL,
        publishedAt: Date? = nil,
        assets: [UpdateAsset] = []
    ) {
        self.tag = tag
        self.version = version
        self.title = title
        self.notes = notes
        self.pageURL = pageURL
        self.publishedAt = publishedAt
        self.assets = assets
    }

    /// DMG first because the installer can hand it to `hdiutil` without an
    /// intermediate extraction step; the zip keeps app-only releases working.
    public var installerAsset: UpdateAsset? {
        assets.first(where: { $0.kind == .diskImage })
            ?? assets.first(where: { $0.kind == .zip })
    }

    public func isNewer(than current: SemanticVersion) -> Bool {
        version > current
    }
}

// MARK: - Feed

public enum UpdateFeedError: Error, Equatable, LocalizedError {
    case network(String)
    case httpStatus(Int)
    case malformedRelease(String)

    public var errorDescription: String? {
        switch self {
        case .network(let detail): return detail
        case .httpStatus(let code): return "GitHub returned HTTP \(code)."
        case .malformedRelease(let detail): return "Unexpected release payload: \(detail)"
        }
    }
}

/// Reads the repository's latest published GitHub release.
///
/// The endpoint `releases/latest` already excludes drafts and prereleases; the
/// decoder still validates the tag so a hand-made feed used by the update smoke
/// test cannot smuggle in an unparsable version.
public enum UpdateFeed {
    public static let repository = "Zeyi-Lin/Lore"

    public static var latestReleaseURL: URL {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            preconditionFailure("The GitHub API URL must stay valid.")
        }
        return url
    }

    /// `url` may be a `file://` URL: the app's `LORE_UPDATE_FEED` override and
    /// the tests use a local payload to exercise the full update flow offline.
    public static func fetchLatest(
        from url: URL = latestReleaseURL,
        userAgent: String = "Lore",
        session: URLSession = .shared
    ) async throws -> UpdateRelease {
        let data: Data
        if url.isFileURL {
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw UpdateFeedError.network(error.localizedDescription)
            }
        } else {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            do {
                let (payload, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw UpdateFeedError.httpStatus(http.statusCode)
                }
                data = payload
            } catch let error as UpdateFeedError {
                throw error
            } catch {
                throw UpdateFeedError.network(error.localizedDescription)
            }
        }
        return try decodeLatestRelease(data)
    }

    public static func decodeLatestRelease(_ data: Data) throws -> UpdateRelease {
        let payload: ReleasePayload
        do {
            payload = try JSONDecoder().decode(ReleasePayload.self, from: data)
        } catch {
            throw UpdateFeedError.malformedRelease(error.localizedDescription)
        }
        guard let version = SemanticVersion(payload.tagName) else {
            throw UpdateFeedError.malformedRelease("tag_name '\(payload.tagName)' is not a version.")
        }
        let pageURL = URL(string: payload.htmlURL) ?? URL(string: "https://github.com/\(repository)/releases")!
        let assets = (payload.assets ?? []).compactMap { asset -> UpdateAsset? in
            guard let url = URL(string: asset.downloadURL) else { return nil }
            return UpdateAsset(name: asset.name, downloadURL: url, byteCount: asset.size ?? 0)
        }
        return UpdateRelease(
            tag: payload.tagName,
            version: version,
            title: payload.name?.isEmpty == false ? payload.name! : payload.tagName,
            notes: payload.body ?? "",
            pageURL: pageURL,
            publishedAt: payload.publishedAt.flatMap(parseDate),
            assets: assets
        )
    }

    private static func parseDate(_ string: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: string) { return date }
        plain.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return plain.date(from: string)
    }

    private struct ReleasePayload: Decodable {
        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: String
        let publishedAt: String?
        let assets: [AssetPayload]?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case body
            case htmlURL = "html_url"
            case publishedAt = "published_at"
            case assets
        }
    }

    private struct AssetPayload: Decodable {
        let name: String
        let downloadURL: String
        let size: Int?

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
            case size
        }
    }
}
