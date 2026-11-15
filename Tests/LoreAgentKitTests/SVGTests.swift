import Testing
import Foundation
@testable import LoreAgentKit

@Suite(.serialized)
final class SVGTests: RunningServerSuite {

    private var sampleSVG: Data { Fixture.makeSVG(width: 120, height: 80) }

    private func pinsFromList(_ object: [String: Any]) throws -> [[String: Any]] {
        try #require(object["pins"] as? [[String: Any]])
    }

    @Test func rawSVGUploadStoresVectorAndRendersThumbnail() throws {
        let svg = sampleSVG
        let result = try client.postRaw(
            "/api/v1/pins?title=Brand%20mark&board=Brand&tags=logo,vector",
            body: svg,
            contentType: "image/svg+xml"
        )
        #expect(result.status == 201, "expected 201, got \(result.status): \(result.text.prefix(400))")
        let pin = try result.jsonObject()
        let pinID = try #require(pin["id"] as? String)

        #expect(pin["kind"] as? String == "svg")
        #expect((pin["image"] as? String)?.hasSuffix(".svg") == true)
        #expect((pin["thumbnail"] as? String)?.hasSuffix(".jpg") == true)
        #expect(pin["width"] as? Int == 120)
        #expect(pin["height"] as? Int == 80)
        #expect(pin["fileSize"] as? Int == svg.count)
        #expect(pin["animated"] as? Bool == false)
        #expect(pin["frameCount"] as? Int == 1)
        let colors = try #require(pin["colors"] as? [String])
        #expect(!colors.isEmpty)
        #expect(colors.count <= 5)
        let families = try #require(pin["colorFamilies"] as? [String])
        #expect(families.contains("red"))
        #expect(families.contains("green"))
        #expect(families.contains("blue"))

        let original = try client.get("/api/v1/pins/\(pinID)/image")
        #expect(original.status == 200)
        #expect(original.header("content-type") == "image/svg+xml")
        #expect(original.body == svg)
        #expect(original.header("content-security-policy")?.contains("sandbox") == true)

        let thumbnail = try client.get("/api/v1/pins/\(pinID)/image?variant=thumb")
        #expect(thumbnail.status == 200)
        #expect(thumbnail.header("content-type") == "image/jpeg")
        let dimensions = try #require(Fixture.imageDimensions(thumbnail.body))
        // Vectors render at the full 1200 px thumbnail size, not at the
        // document's 120 px intrinsic width.
        #expect(dimensions.width == 1200)
        #expect(dimensions.height == 800)
    }

    @Test func jsonUploadAcceptsSVGBase64() throws {
        let svg = sampleSVG
        let body: [String: Any] = [
            "imageBase64": svg.base64EncodedString(),
            "mimeType": "image/svg+xml",
            "title": "Logo JSON",
            "board": "Brand",
            "tags": ["logo"]
        ]
        let result = try client.postJSON("/api/v1/pins", body: body)
        #expect(result.status == 201, "expected 201, got \(result.status): \(result.text.prefix(400))")
        let pin = try result.jsonObject()
        #expect(pin["kind"] as? String == "svg")
        #expect((pin["image"] as? String)?.hasSuffix(".svg") == true)
        #expect(pin["width"] as? Int == 120)
        #expect(pin["height"] as? Int == 80)

        let pinID = try #require(pin["id"] as? String)
        let original = try client.get("/api/v1/pins/\(pinID)/image")
        #expect(original.header("content-type") == "image/svg+xml")
        #expect(original.body == svg)
    }

    @Test func explicitKindOverridesTheVectorDefault() throws {
        let result = try client.postRaw(
            "/api/v1/pins?kind=image&title=Styled%20vector",
            body: sampleSVG,
            contentType: "image/svg+xml"
        )
        #expect(result.status == 201, "expected 201, got \(result.status): \(result.text.prefix(400))")
        let pin = try result.jsonObject()
        #expect(pin["kind"] as? String == "image")
        #expect((pin["image"] as? String)?.hasSuffix(".svg") == true)
    }

    @Test func malformedSVGIsRejected() throws {
        let broken = try client.postRaw(
            "/api/v1/pins",
            body: Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><g></svg>".utf8),
            contentType: "image/svg+xml"
        )
        try expectError(broken, status: 400, code: "invalid_image_data", "malformed SVG")

        let text = try client.postRaw(
            "/api/v1/pins",
            body: Data("not markup at all".utf8),
            contentType: "image/svg+xml"
        )
        try expectError(text, status: 400, code: "invalid_image_data", "non-SVG bytes")
    }

    @Test func svgPinsAreSearchableAndFilterable() throws {
        _ = try client.postRaw(
            "/api/v1/pins?title=Vector%20mark",
            body: sampleSVG,
            contentType: "image/svg+xml"
        )

        let byKind = try expectJSON(try client.get("/api/v1/pins?kind=svg"))
        let kindMatches = try pinsFromList(byKind)
        #expect(kindMatches.count == 1)
        #expect(kindMatches.first?["title"] as? String == "Vector mark")

        let bySearch = try expectJSON(try client.get("/api/v1/pins?q=vector"))
        let searchMatches = try pinsFromList(bySearch)
        #expect(searchMatches.contains { $0["title"] as? String == "Vector mark" })
    }

    @Test func vectorMetadataSurvivesPATCH() throws {
        let result = try client.postRaw(
            "/api/v1/pins?title=Before",
            body: sampleSVG,
            contentType: "image/svg+xml"
        )
        let pin = try result.jsonObject()
        let pinID = try #require(pin["id"] as? String)

        let patched = try client.request(
            "/api/v1/pins/\(pinID)",
            method: "PATCH",
            body: try JSONSerialization.data(withJSONObject: ["title": "After"]),
            contentType: "application/json"
        )
        let updated = try expectJSONStatus(patched, status: 200, "PATCH vector")
        #expect(updated["title"] as? String == "After")
        #expect(updated["kind"] as? String == "svg")
        #expect((updated["image"] as? String)?.hasSuffix(".svg") == true)
        #expect(updated["width"] as? Int == 120)

        let kindPatch = try client.request(
            "/api/v1/pins/\(pinID)",
            method: "PATCH",
            body: try JSONSerialization.data(withJSONObject: ["kind": "svg"]),
            contentType: "application/json"
        )
        let kindUpdated = try expectJSONStatus(kindPatch, status: 200, "PATCH kind svg")
        #expect(kindUpdated["kind"] as? String == "svg")
    }
}
