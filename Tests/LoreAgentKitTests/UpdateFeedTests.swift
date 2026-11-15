import Testing
import Foundation
@testable import LoreAgentKit

@Suite
struct UpdateFeedTests {

    @Test func parsesReleaseTags() throws {
        let tagged = try #require(SemanticVersion("v1.2.3"))
        #expect(tagged == SemanticVersion(major: 1, minor: 2, patch: 3))
        #expect(tagged.description == "1.2.3")

        let short = try #require(SemanticVersion("2.4"))
        #expect(short == SemanticVersion(major: 2, minor: 4, patch: 0))

        let prerelease = try #require(SemanticVersion("1.2.3-beta.2"))
        #expect(prerelease.prerelease == ["beta", "2"])

        let metadata = try #require(SemanticVersion("v1.2.3+42"))
        #expect(metadata == SemanticVersion(major: 1, minor: 2, patch: 3))
    }

    @Test func rejectsNonVersions() {
        for raw in ["", "v", "latest", "1.x.0", "1.2.3.4", "1..2", "1.2.3-", "release-1.2"] {
            #expect(SemanticVersion(raw) == nil, "\(raw) must not parse as a version")
        }
    }

    @Test func ordersVersions() throws {
        func version(_ raw: String) throws -> SemanticVersion {
            try #require(SemanticVersion(raw))
        }
        #expect(try version("1.2.0") < version("1.10.0"))
        #expect(try version("1.9.9") < version("1.10.0"))
        #expect(try version("1.2.0-beta.1") < version("1.2.0"))
        #expect(try version("1.2.0-beta.1") < version("1.2.0-beta.2"))
        #expect(try version("1.2.0-alpha.10") > version("1.2.0-alpha.2"))
        #expect(try version("1.2.0-beta") < version("1.2.0-beta.1"))
        #expect(try version("1.0.0") == version("v1.0.0+build.7"))
    }

    @Test func decodesLatestRelease() throws {
        let release = try UpdateFeed.decodeLatestRelease(Data(UpdateFixture.latestReleaseJSON.utf8))
        #expect(release.tag == "v1.2.0")
        #expect(release.version == SemanticVersion(major: 1, minor: 2, patch: 0))
        #expect(release.title == "Lore v1.2.0")
        #expect(release.notes.contains("Gallery polish"))
        #expect(release.pageURL.absoluteString == "https://github.com/Zeyi-Lin/Lore/releases/tag/v1.2.0")
        #expect(release.publishedAt != nil)
        #expect(release.installerAsset?.name == "Lore-v1.2.0.dmg")
        #expect(release.installerAsset?.kind == .diskImage)
        #expect(release.installerAsset?.byteCount == 6_946_762)
    }

    @Test func installerPrefersDiskImageThenZip() throws {
        let dmg = UpdateAsset(
            name: "Lore-v1.2.0.dmg",
            downloadURL: URL(string: "https://github.com/Zeyi-Lin/Lore/releases/download/v1.2.0/Lore-v1.2.0.dmg")!
        )
        let zip = UpdateAsset(
            name: "Lore-v1.2.0.zip",
            downloadURL: URL(string: "https://github.com/Zeyi-Lin/Lore/releases/download/v1.2.0/Lore-v1.2.0.zip")!
        )
        let notes = UpdateAsset(
            name: "SHA256SUMS",
            downloadURL: URL(string: "https://github.com/Zeyi-Lin/Lore/releases/download/v1.2.0/SHA256SUMS")!
        )
        #expect(UpdateRelease(tag: "v1.2.0", version: SemanticVersion(major: 1, minor: 2, patch: 0),
                              title: "Lore", pageURL: UpdateFeed.latestReleaseURL,
                              assets: [notes, zip, dmg]).installerAsset == dmg)
        #expect(UpdateRelease(tag: "v1.2.0", version: SemanticVersion(major: 1, minor: 2, patch: 0),
                              title: "Lore", pageURL: UpdateFeed.latestReleaseURL,
                              assets: [notes, zip]).installerAsset == zip)
        #expect(UpdateRelease(tag: "v1.2.0", version: SemanticVersion(major: 1, minor: 2, patch: 0),
                              title: "Lore", pageURL: UpdateFeed.latestReleaseURL,
                              assets: [notes]).installerAsset == nil)
    }

    @Test func comparesAgainstInstalledVersion() throws {
        let release = try UpdateFeed.decodeLatestRelease(Data(UpdateFixture.latestReleaseJSON.utf8))
        #expect(release.isNewer(than: try #require(SemanticVersion("1.1.0"))))
        #expect(!release.isNewer(than: try #require(SemanticVersion("1.2.0"))))
        #expect(!release.isNewer(than: try #require(SemanticVersion("1.3.0"))))
    }

    @Test func rejectsUnparsableTag() {
        let json = #"{"tag_name":"latest","name":"Lore","html_url":"https://github.com/Zeyi-Lin/Lore/releases","assets":[]}"#
        #expect(throws: UpdateFeedError.self) {
            try UpdateFeed.decodeLatestRelease(Data(json.utf8))
        }
    }

    @Test func readsLocalFeedPayload() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lore-update-\(UUID().uuidString).json")
        try Data(UpdateFixture.latestReleaseJSON.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let release = try await UpdateFeed.fetchLatest(from: url)
        #expect(release.version == SemanticVersion(major: 1, minor: 2, patch: 0))
        #expect(release.installerAsset?.name == "Lore-v1.2.0.dmg")
    }
}

// MARK: - Fixture

enum UpdateFixture {
    static let latestReleaseJSON = """
    {
      "tag_name": "v1.2.0",
      "name": "Lore v1.2.0",
      "body": "## Gallery polish\\n- Faster grid\\n- Fixed zoom",
      "html_url": "https://github.com/Zeyi-Lin/Lore/releases/tag/v1.2.0",
      "published_at": "2026-11-15T07:21:19Z",
      "assets": [
        {
          "name": "Lore-v1.2.0.dmg",
          "browser_download_url": "https://github.com/Zeyi-Lin/Lore/releases/download/v1.2.0/Lore-v1.2.0.dmg",
          "size": 6946762
        },
        {
          "name": "SHA256SUMS.txt",
          "browser_download_url": "https://github.com/Zeyi-Lin/Lore/releases/download/v1.2.0/SHA256SUMS.txt",
          "size": 120
        }
      ]
    }
    """
}
