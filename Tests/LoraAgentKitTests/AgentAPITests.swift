import Testing
import Foundation
@testable import LoraAgentKit

@Suite(.serialized)
final class AgentAPITests: RunningServerSuite {

    // MARK: - Health

    @Test func healthReportsBindPortAndPinCount() throws {
        let health = try expectJSON(try client.get("/health"))
        #expect(health["status"] as? String == "ok")
        #expect(health["app"] as? String == "Lora")
        #expect(health["api"] as? String == "v1")
        #expect(health["version"] as? String == "1.0.0")
        #expect(health["pinCount"] as? Int == 4)
        #expect(health["port"] as? Int == Int(port))
    }

    @Test func versionedHealthAliasMatches() throws {
        let plain = try client.get("/health")
        let versioned = try client.get("/api/v1/health")
        #expect(versioned.status == 200)
        #expect(plain.text == versioned.text)
    }

    // MARK: - Library

    @Test func libraryShapeAndEnrichment() throws {
        let result = try client.get("/api/v1/library")
        let library = try expectJSON(result)
        #expect(library["app"] as? String == "Lora")
        #expect(library["version"] as? String == "1.0.0")
        #expect(library["generatedAt"] as? String != nil)

        let stats = try #require(library["stats"] as? [String: Any])
        #expect(stats["pins"] as? Int == 4)
        #expect(stats["boards"] as? Int == 4)
        #expect(stats["tags"] as? Int == 9)
        #expect(stats["favorites"] as? Int == 1)
        #expect(stats["images"] as? Int == 4)

        let boards = try #require(library["boards"] as? [[String: Any]])
        #expect(boards.count == 4)
        #expect(boards.map { $0["name"] as? String } == ["Editorial", "Landing pages", "Mobile flows", "Web dashboards"])

        let tags = try #require(library["tags"] as? [[String: Any]])
        #expect(tags.count == 9)
        #expect(tags.allSatisfy { ($0["count"] as? Int) == 1 })

        let pins = try #require(library["pins"] as? [[String: Any]])
        #expect(pins.count == 4)

        let aurora = pins[0]
        #expect(aurora["id"] as? String == Fixture.auroraID)
        #expect(aurora["title"] as? String == "Aurora analytics overview")
        #expect(aurora["board"] as? String == "Web dashboards")
        #expect(aurora["favorite"] as? Bool == true)
        #expect(aurora["tags"] as? [String] == ["dashboard", "analytics", "dark"])
        #expect(aurora["colors"] as? [String] == ["#0E1117", "#E60023", "#F5F5F7"])
        #expect(aurora["image"] as? String == "Images/aurora.png")
        #expect(aurora["thumbnail"] as? String == "Thumbnails/aurora.jpg")
        #expect(aurora["width"] as? Int == 1440)
        #expect(aurora["height"] as? Int == 900)
        #expect(aurora["sourceURL"] as? String == "https://dribbble.com/shots/1")
        #expect(aurora["sourceLabel"] as? String == "Dribbble")
        #expect(aurora["kind"] as? String == "screenshot")

        let expectedOriginal = "\(baseURL)/api/v1/pins/\(Fixture.auroraID)/image?variant=original"
        let expectedThumb = "\(baseURL)/api/v1/pins/\(Fixture.auroraID)/image?variant=thumb"
        #expect(aurora["imageURL"] as? String == expectedOriginal)
        #expect(aurora["thumbnailURL"] as? String == expectedThumb)

        let ledger = pins[1]
        #expect(ledger["thumbnailURL"] is NSNull)
        #expect(ledger["thumbnail"] is NSNull)
        #expect(ledger["sourceURL"] is NSNull)

        #expect(!result.text.contains(root.path), "response must not expose filesystem paths")
        #expect(!result.text.contains(root.deletingLastPathComponent().path))
    }

    @Test func libraryIsReloadedForEveryRequest() throws {
        var single = PinFixture(id: Fixture.auroraID, title: "Aurora analytics overview")
        single.image = "Images/aurora.png"
        try scenario.writeLibrary([single.json()])

        var library = try expectJSON(try client.get("/api/v1/library"))
        #expect((library["pins"] as? [[String: Any]])?.count == 1)
        var health = try expectJSON(try client.get("/health"))
        #expect(health["pinCount"] as? Int == 1)

        var second = PinFixture(id: Fixture.ledgerID, title: "Ledger onboarding")
        second.image = "Images/ledger.png"
        second.board = "Mobile flows"
        try scenario.writeLibrary([single.json(), second.json()])

        library = try expectJSON(try client.get("/api/v1/library"))
        #expect((library["pins"] as? [[String: Any]])?.count == 2)
        health = try expectJSON(try client.get("/health"))
        #expect(health["pinCount"] as? Int == 2)
    }

    @Test func missingAndCorruptLibraryErrors() throws {
        try scenario.writeRawLibrary("{ not valid json")
        try expectError(try client.get("/api/v1/library"), status: 500, code: "library_corrupt")
        let health = try expectJSON(try client.get("/health"))
        #expect(health["pinCount"] as? Int == 0)
        #expect(health["status"] as? String == "ok")

        try scenario.removeLibraryFile()
        try expectError(try client.get("/api/v1/library"), status: 500, code: "library_unavailable")
        try expectError(try client.get("/api/v1/pins"), status: 500, code: "library_unavailable")
        try expectError(try client.get("/api/v1/boards"), status: 500, code: "library_unavailable")
    }

    // MARK: - Filters and sorting

    @Test func pinFilters() throws {
        try assertPins("?q=dashboard", total: 1, ids: [Fixture.auroraID])
        try assertPins("?q=DASHBOARD", total: 1, ids: [Fixture.auroraID])
        try assertPins("?q=magenta", total: 1, ids: [Fixture.auroraID])
        try assertPins("?tag=mobile", total: 1, ids: [Fixture.ledgerID])
        try assertPins("?tag=MOBILE", total: 1, ids: [Fixture.ledgerID])
        try assertPins("?board=Web%20dashboards", total: 1, ids: [Fixture.auroraID])
        try assertPins("?board=web%20DASHBOARDS", total: 1, ids: [Fixture.auroraID])
        try assertPins("?favorite=true", total: 1, ids: [Fixture.auroraID])
        try assertPins("?favorite=false", total: 3, ids: nil)
        try assertPins("?kind=screenshot", total: 4, ids: nil)
        try assertPins("?tag=landing&favorite=false", total: 1, ids: [Fixture.zephyrID])
        try assertPins("?q=noema&board=Editorial", total: 1, ids: [Fixture.noemaID])
        try assertPins("?q=does-not-exist", total: 0, ids: [])
    }

    @Test func pinSorting() throws {
        var result = try expectJSON(try client.get("/api/v1/pins?sort=title"))
        var pins = try pinsFromList(result)
        #expect(pins.compactMap { $0["title"] as? String } == [
            "Aurora analytics overview",
            "Ledger onboarding",
            "Noema field notes",
            "Zephyr pricing page"
        ])

        result = try expectJSON(try client.get("/api/v1/pins?sort=recent"))
        pins = try pinsFromList(result)
        #expect(pins.compactMap { $0["title"] as? String } == [
            "Zephyr pricing page",
            "Noema field notes",
            "Ledger onboarding",
            "Aurora analytics overview"
        ])

        result = try expectJSON(try client.get("/api/v1/pins?sort=oldest"))
        pins = try pinsFromList(result)
        #expect(pins.compactMap { $0["title"] as? String } == [
            "Aurora analytics overview",
            "Ledger onboarding",
            "Noema field notes",
            "Zephyr pricing page"
        ])
    }

    @Test func paginationEnvelope() throws {
        var result = try expectJSON(try client.get("/api/v1/pins?limit=2&offset=1"))
        #expect(result["count"] as? Int == 2)
        #expect(result["total"] as? Int == 4)
        #expect(result["offset"] as? Int == 1)
        #expect(result["limit"] as? Int == 2)
        var pins = try pinsFromList(result)
        #expect(pins.count == 2)
        #expect(pins.compactMap { $0["title"] as? String } == ["Noema field notes", "Ledger onboarding"])

        result = try expectJSON(try client.get("/api/v1/pins?offset=10"))
        #expect(result["count"] as? Int == 0)
        #expect(result["total"] as? Int == 4)
        pins = try pinsFromList(result)
        #expect(pins.isEmpty)

        result = try expectJSON(try client.get("/api/v1/pins?limit=200"))
        #expect(result["count"] as? Int == 4)
        #expect(result["limit"] as? Int == 200)
    }

    @Test func invalidQueryParametersReturn400() throws {
        for query in ["?limit=0", "?limit=201", "?limit=abc", "?offset=-1", "?offset=abc", "?sort=sideways", "?favorite=maybe"] {
            try expectError(try client.get("/api/v1/pins" + query), status: 400, code: "invalid_parameter", query)
        }
        try expectError(try client.get("/api/v1/pins/\(Fixture.auroraID)/image?variant=huge"), status: 400, code: "invalid_parameter", "variant=huge")
        try expectError(try client.get("/api/v1/context?limit=0"), status: 400, code: "invalid_parameter", "context limit=0")
        // URLSession normalizes invalid percent escapes; send the raw request instead.
        let rawPercent = try RawHTTP.send(port: port, "GET /api/v1/pins?tag=%ZZ HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
        try expectError(rawPercent, status: 400, code: "invalid_percent_encoding", "tag=%ZZ")
    }

    private func assertPins(_ query: String, total: Int, ids: [String]?) throws {
        let result = try expectJSON(try client.get("/api/v1/pins" + query), query)
        #expect(result["total"] as? Int == total, "unexpected total for \(query)")
        let pins = try pinsFromList(result)
        #expect(pins.count == total, "unexpected count for \(query)")
        if let ids {
            #expect(pins.compactMap { $0["id"] as? String } == ids, "unexpected ids for \(query)")
        }
    }

    // MARK: - Pin detail

    @Test func pinDetail() throws {
        let pin = try expectJSON(try client.get("/api/v1/pins/\(Fixture.auroraID)"))
        #expect(pin["id"] as? String == Fixture.auroraID)
        #expect(pin["imageURL"] as? String == "\(baseURL)/api/v1/pins/\(Fixture.auroraID)/image?variant=original")
        #expect(pin["note"] as? String == "Dark analytics dashboard with magenta highlights and dense KPI cards.")

        try expectError(try client.get("/api/v1/pins/not-a-real-pin"), status: 404, code: "pin_not_found")
        try expectError(try client.get("/api/v1/pins/00000000-0000-4000-8000-000000000000"), status: 404, code: "pin_not_found")
    }

    // MARK: - Images

    @Test func imageOriginalAndThumbnail() throws {
        let original = try client.get("/api/v1/pins/\(Fixture.auroraID)/image")
        #expect(original.status == 200)
        #expect(original.header("content-type") == "image/png")
        #expect(original.header("cache-control") == "no-cache")
        #expect(original.body == Fixture.pngData)
        #expect(original.header("content-length") == String(Fixture.pngData.count))

        let thumbnail = try client.get("/api/v1/pins/\(Fixture.auroraID)/image?variant=thumb")
        #expect(thumbnail.status == 200)
        #expect(thumbnail.header("content-type") == "image/jpeg")
        #expect(thumbnail.body == Fixture.jpegData)

        let noemaThumbnail = try client.get("/api/v1/pins/\(Fixture.noemaID)/image?variant=thumb")
        #expect(noemaThumbnail.header("content-type") == "image/jpeg")
        #expect(noemaThumbnail.body == Fixture.jpegData)
    }

    @Test func thumbnailFallsBackToOriginal() throws {
        let fallback = try client.get("/api/v1/pins/\(Fixture.ledgerID)/image?variant=thumb")
        #expect(fallback.status == 200)
        #expect(fallback.header("content-type") == "image/png")
        #expect(fallback.body == Fixture.pngData)
    }

    @Test func headImageReturnsHeadersWithoutBody() throws {
        let head = try client.head("/api/v1/pins/\(Fixture.auroraID)/image")
        #expect(head.status == 200)
        #expect(head.header("content-type") == "image/png")
        #expect(head.header("content-length") == String(Fixture.pngData.count))
        #expect(head.body.isEmpty)

        let headThumb = try client.head("/api/v1/pins/\(Fixture.auroraID)/image?variant=thumb")
        #expect(headThumb.status == 200)
        #expect(headThumb.header("content-type") == "image/jpeg")
        #expect(headThumb.header("content-length") == String(Fixture.jpegData.count))
        #expect(headThumb.body.isEmpty)

        let get = try client.get("/api/v1/pins/\(Fixture.auroraID)/image")
        #expect(head.header("content-length") == get.header("content-length"))
    }

    @Test func imageErrors() throws {
        try expectError(try client.get("/api/v1/pins/unknown/image"), status: 404, code: "pin_not_found")

        var empty = PinFixture(id: Fixture.auroraID, title: "No image")
        empty.image = ""
        try scenario.writeLibrary([empty.json()])
        try expectError(try client.get("/api/v1/pins/\(Fixture.auroraID)/image"), status: 404, code: "image_not_found")
        try expectError(try client.get("/api/v1/pins/\(Fixture.auroraID)/image?variant=thumb"), status: 404, code: "image_not_found")
    }

    // MARK: - Aggregates

    @Test func boardsTagsAndStats() throws {
        let boards = try expectJSON(try client.get("/api/v1/boards"))
        let boardList = try #require(boards["boards"] as? [[String: Any]])
        #expect(boardList.map { $0["name"] as? String } == ["Editorial", "Landing pages", "Mobile flows", "Web dashboards"])

        let tags = try expectJSON(try client.get("/api/v1/tags"))
        let tagList = try #require(tags["tags"] as? [[String: Any]])
        #expect(tagList.count == 9)
        #expect(tagList.allSatisfy { ($0["count"] as? Int) == 1 })
        #expect(tagList.first?["name"] as? String == "analytics")

        let stats = try expectJSON(try client.get("/api/v1/stats"))
        #expect(stats["pins"] as? Int == 4)
        #expect(stats["boards"] as? Int == 4)
        #expect(stats["tags"] as? Int == 9)
        #expect(stats["favorites"] as? Int == 1)
        #expect(stats["images"] as? Int == 4)
    }

    @Test func boardsAreSortedByCountThenName() throws {
        var first = PinFixture(id: Fixture.auroraID, title: "Aurora")
        first.board = "Web dashboards"
        first.image = "Images/aurora.png"
        var second = PinFixture(id: Fixture.ledgerID, title: "Ledger")
        second.board = "Web dashboards"
        second.image = "Images/ledger.png"
        var third = PinFixture(id: Fixture.noemaID, title: "Noema")
        third.board = "Editorial"
        third.image = "Images/noema.png"
        try scenario.writeLibrary([first.json(), second.json(), third.json()])

        let boards = try expectJSON(try client.get("/api/v1/boards"))
        let list = try #require(boards["boards"] as? [[String: Any]])
        #expect(list.map { $0["name"] as? String } == ["Web dashboards", "Editorial"])
        #expect(list.map { $0["count"] as? Int } == [2, 1])
    }

    // MARK: - Context

    @Test func contextMarkdownDocument() throws {
        let result = try client.get("/api/v1/context")
        #expect(result.status == 200)
        #expect(result.header("content-type")?.hasPrefix("text/markdown") == true)
        let markdown = result.text
        #expect(markdown.contains("# Lora design context"))
        #expect(markdown.contains(baseURL))
        #expect(markdown.contains("Aurora analytics overview"))
        #expect(markdown.contains("Pin ID:"))
        #expect(markdown.contains("\(baseURL)/api/v1/pins/\(Fixture.auroraID)/image?variant=original"))
        #expect(markdown.contains("\(baseURL)/api/v1/pins/\(Fixture.ledgerID)/image?variant=original"))
        #expect(!markdown.contains("\(baseURL)/api/v1/pins/\(Fixture.ledgerID)/image?variant=thumb"))
        #expect(markdown.contains("Design note:"))
        #expect(markdown.contains("## Next steps"))
    }

    @Test func contextFiltersAndEmptyState() throws {
        var result = try client.get("/api/v1/context?board=Web%20dashboards")
        #expect(result.status == 200)
        #expect(result.text.contains("Aurora analytics overview"))
        #expect(!result.text.contains("Ledger onboarding"))
        #expect(result.text.contains("board = \"Web dashboards\""))

        result = try client.get("/api/v1/context?tag=editorial")
        #expect(result.text.contains("Noema field notes"))
        #expect(!result.text.contains("Aurora analytics overview"))

        result = try client.get("/api/v1/context?limit=1")
        #expect(result.text.contains("Zephyr pricing page"))
        #expect(!result.text.contains("Noema field notes"))
        #expect(result.text.contains("Showing 1 of 4 matching pins"))

        result = try client.get("/api/v1/context?board=Missing%20board")
        #expect(result.status == 200)
        #expect(result.text.contains("No pins matched this filter"))
        #expect(result.text.contains("Available boards:"))
    }
}
