import Testing
import Foundation
@testable import CantaAgentKit

@Suite(.serialized)
final class PinCreationTests: RunningServerSuite {

    private var samplePNG: Data { Fixture.makePNG(width: 120, height: 80) }

    private func libraryPayload() throws -> [String: Any] {
        try expectJSON(try client.get("/api/v1/library"))
    }

    private func pins(in library: [String: Any]) throws -> [[String: Any]] {
        try #require(library["pins"] as? [[String: Any]])
    }

    private func fileCount(in directory: URL) -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path).count) ?? 0
    }

    // MARK: - JSON form

    @Test func jsonUploadCreatesPinWithAssets() throws {
        let png = samplePNG
        let body: [String: Any] = [
            "imageBase64": "data:image/png;base64," + png.base64EncodedString(),
            "mimeType": "image/png",
            "title": "Checkout flow",
            "note": "Three-step checkout captured from a design review.",
            "board": "Mobile flows",
            "tags": ["Mobile", "CHECKOUT", "checkout", "  ", ""],
            "sourceURL": "https://example.com/checkout",
            "sourceLabel": "Claude Code",
            "kind": "screenshot",
            "favorite": true
        ]
        let result = try client.postJSON("/api/v1/pins", body: body)
        #expect(result.status == 201, "expected 201, got \(result.status): \(result.text.prefix(400))")
        let pin = try result.jsonObject()
        let pinID = try #require(pin["id"] as? String, "response missing id")
        #expect(result.header("location") == "/api/v1/pins/\(pinID)")
        #expect(pin["title"] as? String == "Checkout flow")
        #expect(pin["board"] as? String == "Mobile flows")
        #expect(pin["tags"] as? [String] == ["mobile", "checkout"])
        #expect(pin["favorite"] as? Bool == true)
        #expect(pin["sourceLabel"] as? String == "Claude Code")
        #expect(pin["sourceURL"] as? String == "https://example.com/checkout")
        #expect(pin["note"] as? String == "Three-step checkout captured from a design review.")
        #expect(pin["width"] as? Int == 120)
        #expect(pin["height"] as? Int == 80)
        #expect(pin["fileSize"] as? Int == png.count)
        #expect(pin["imageURL"] as? String == "\(baseURL)/api/v1/pins/\(pinID)/image?variant=original")
        #expect(pin["thumbnailURL"] as? String == "\(baseURL)/api/v1/pins/\(pinID)/image?variant=thumb")
        let colors = try #require(pin["colors"] as? [String])
        #expect(!colors.isEmpty)
        #expect(colors.count <= 5)
        #expect(colors.allSatisfy { $0.count == 7 && $0.hasPrefix("#") })
        let createdAt = try #require(pin["createdAt"] as? String)
        #expect(Timestamp.date(from: createdAt) != nil)

        let image = try client.get("/api/v1/pins/\(pinID)/image")
        #expect(image.status == 200)
        #expect(image.header("content-type") == "image/png")
        #expect(image.body == png)

        let thumbnail = try client.get("/api/v1/pins/\(pinID)/image?variant=thumb")
        #expect(thumbnail.status == 200)
        #expect(thumbnail.header("content-type") == "image/jpeg")
        #expect(thumbnail.body.prefix(2) == Data([0xFF, 0xD8]))
        let thumbnailSize = try #require(Fixture.imageDimensions(thumbnail.body))
        #expect(thumbnailSize.width == 120)
        #expect(thumbnailSize.height == 80)

        let library = try libraryPayload()
        let storedPins = try pins(in: library)
        #expect(storedPins.count == 5)
        #expect(storedPins.last?["id"] as? String == pinID)
        let stats = try #require(library["stats"] as? [String: Any])
        #expect(stats["pins"] as? Int == 5)
        #expect(stats["images"] as? Int == 5)

        let boards = try expectJSON(try client.get("/api/v1/boards"))
        let boardList = try #require(boards["boards"] as? [[String: Any]])
        let mobile = boardList.first { $0["name"] as? String == "Mobile flows" }
        #expect(mobile?["count"] as? Int == 2)

        #expect(TestPaths.waitUntil { libraryChanges.count == 1 }, "onLibraryChanged should fire once")
    }

    @Test func jsonUploadWithoutDataURIPrefixAppliesDefaults() throws {
        let png = samplePNG
        let result = try client.postJSON("/api/v1/pins", body: ["imageBase64": png.base64EncodedString()])
        #expect(result.status == 201)
        let pin = try result.jsonObject()
        let title = try #require(pin["title"] as? String)
        #expect(title.hasPrefix("Agent capture · "))
        #expect(pin["board"] as? String == "Unsorted")
        #expect(pin["sourceLabel"] as? String == "Agent API")
        #expect(pin["kind"] as? String == "screenshot")
        #expect(pin["favorite"] as? Bool == false)
        #expect(pin["tags"] as? [String] == [])
        #expect(pin["note"] as? String == "")
        #expect(pin["sourceURL"] is NSNull)
        #expect(pin["width"] as? Int == 120)
        #expect(pin["height"] as? Int == 80)
        #expect(TestPaths.waitUntil { libraryChanges.count == 1 })
    }

    // MARK: - Raw image form

    @Test func rawUploadWithQueryMetadata() throws {
        let jpeg = Fixture.jpegData
        let path = "/api/v1/pins?title=Raw%20capture&note=Uploaded%20as%20raw%20bytes&board=Editorial&tags=Raw,EDITORIAL&sourceURL=https%3A%2F%2Fexample.com%2Fraw&sourceLabel=Codex&kind=reference&favorite=true"
        let result = try client.postRaw(path, body: jpeg, contentType: "image/jpeg")
        #expect(result.status == 201, "expected 201, got \(result.status): \(result.text.prefix(400))")
        let pin = try result.jsonObject()
        let pinID = try #require(pin["id"] as? String)
        #expect(result.header("location") == "/api/v1/pins/\(pinID)")
        #expect(pin["title"] as? String == "Raw capture")
        #expect(pin["board"] as? String == "Editorial")
        #expect(pin["tags"] as? [String] == ["raw", "editorial"])
        #expect(pin["sourceLabel"] as? String == "Codex")
        #expect(pin["sourceURL"] as? String == "https://example.com/raw")
        #expect(pin["kind"] as? String == "reference")
        #expect(pin["favorite"] as? Bool == true)
        #expect(pin["width"] as? Int == 1)
        #expect(pin["height"] as? Int == 1)
        #expect(pin["fileSize"] as? Int == jpeg.count)

        let image = try client.get("/api/v1/pins/\(pinID)/image")
        #expect(image.header("content-type") == "image/jpeg")
        #expect(image.body == jpeg)

        let library = try libraryPayload()
        #expect(try pins(in: library).count == 5)
        #expect(TestPaths.waitUntil { libraryChanges.count == 1 })
    }

    @Test func largeImageThumbnailIsCappedAt1200Pixels() throws {
        let large = Fixture.makePNG(width: 1600, height: 900)
        let result = try client.postRaw("/api/v1/pins?title=Large%20capture", body: large, contentType: "image/png")
        #expect(result.status == 201)
        let pin = try result.jsonObject()
        let pinID = try #require(pin["id"] as? String)
        #expect(pin["width"] as? Int == 1600)
        #expect(pin["height"] as? Int == 900)
        let thumbnail = try client.get("/api/v1/pins/\(pinID)/image?variant=thumb")
        #expect(thumbnail.header("content-type") == "image/jpeg")
        let size = try #require(Fixture.imageDimensions(thumbnail.body))
        #expect(size.width == 1200)
        #expect(size.height == 675)
    }

    // MARK: - Validation errors

    @Test func invalidUploadsReturnJSONErrorsWithoutWriting() throws {
        let imagesDirectory = root.appendingPathComponent("Images", isDirectory: true)
        let initialFiles = fileCount(in: imagesDirectory)
        let png = samplePNG

        try expectError(try client.postJSON("/api/v1/pins", body: ["title": "No image"]), status: 400, code: "missing_image")
        try expectError(try client.postRaw("/api/v1/pins", body: Data("{ this is not JSON".utf8), contentType: "application/json"), status: 400, code: "invalid_json")
        try expectError(try client.postJSON("/api/v1/pins", body: ["imageBase64": "not base64!!!"]), status: 400, code: "invalid_image_data")
        try expectError(try client.postJSON("/api/v1/pins", body: ["imageBase64": Data("hello world".utf8).base64EncodedString()]), status: 400, code: "invalid_image_data")
        try expectError(
            try client.postJSON("/api/v1/pins", body: ["imageBase64": png.base64EncodedString(), "mimeType": "text/plain"]),
            status: 415,
            code: "unsupported_media_type"
        )
        try expectError(try client.postRaw("/api/v1/pins", body: Data("hello".utf8), contentType: "text/plain"), status: 415, code: "unsupported_media_type")
        try expectError(try client.postRaw("/api/v1/pins", body: Data(), contentType: "image/png"), status: 400, code: "missing_image")
        try expectError(
            try client.postJSON("/api/v1/pins", body: ["imageBase64": png.base64EncodedString(), "tags": "not-an-array"]),
            status: 400,
            code: "invalid_metadata"
        )

        #expect(fileCount(in: imagesDirectory) == initialFiles, "failed uploads must not leave orphan files")
        let library = try libraryPayload()
        #expect(try pins(in: library).count == 4)
        #expect(libraryChanges.count == 0)
    }

    @Test func postToReadOnlyPathsReturns405() throws {
        let libraryResult = try client.postRaw("/api/v1/library", body: Data(), contentType: "application/json")
        try expectError(libraryResult, status: 405, code: "method_not_allowed")
        let allow = libraryResult.header("allow") ?? ""
        #expect(allow.contains("GET"))
        #expect(allow.contains("HEAD"))
        #expect(allow.contains("OPTIONS"))
        #expect(!allow.contains("POST"))

        try expectError(
            try client.postRaw("/api/v1/pins/\(Fixture.auroraID)", body: Data(), contentType: "application/json"),
            status: 405,
            code: "method_not_allowed"
        )
        try expectError(try client.postRaw("/docs", body: Data(), contentType: "application/json"), status: 405, code: "method_not_allowed")
    }

    @Test func optionsAndCORSAdvertisePost() throws {
        let options = try client.options("/api/v1/pins")
        #expect(options.status == 204)
        #expect((options.header("allow") ?? "").contains("POST"))
        #expect((options.header("access-control-allow-methods") ?? "").contains("POST"))

        let readOnlyOptions = try client.options("/api/v1/library")
        #expect(readOnlyOptions.status == 204)
        #expect(!(readOnlyOptions.header("allow") ?? "").contains("POST"))
    }

    @Test func oversizedUploadIsRejectedWith413() throws {
        let raw = "POST /api/v1/pins HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: image/png\r\nContent-Length: 20971521\r\n\r\n"
        let result = try RawHTTP.send(port: port, raw)
        try expectError(result, status: 413, code: "request_body_too_large")
    }

    // MARK: - Persistence guarantees

    @Test func corruptOrMissingLibraryRejectsUploadWithoutOrphans() throws {
        let imagesDirectory = root.appendingPathComponent("Images", isDirectory: true)
        let initialFiles = fileCount(in: imagesDirectory)

        try scenario.writeRawLibrary("{ this is not valid json")
        try expectError(
            try client.postRaw("/api/v1/pins", body: Fixture.pngData, contentType: "image/png"),
            status: 500,
            code: "library_corrupt"
        )
        #expect(fileCount(in: imagesDirectory) == initialFiles, "corrupt library upload must not leave orphan files")
        #expect(libraryChanges.count == 0)

        try scenario.removeLibraryFile()
        try expectError(
            try client.postRaw("/api/v1/pins", body: Fixture.pngData, contentType: "image/png"),
            status: 500,
            code: "library_unavailable"
        )
        #expect(fileCount(in: imagesDirectory) == initialFiles)
    }

    @Test func uploadPreservesExistingPinsAndAppends() throws {
        let before = try pins(in: try libraryPayload())
        #expect(before.count == 4)
        let result = try client.postRaw("/api/v1/pins?title=Appended", body: Fixture.pngData, contentType: "image/png")
        #expect(result.status == 201)
        let created = try result.jsonObject()
        let createdID = try #require(created["id"] as? String)

        let after = try pins(in: try libraryPayload())
        #expect(after.count == 5)
        #expect(after.last?["id"] as? String == createdID)
        for (index, original) in before.enumerated() {
            #expect(after[index]["id"] as? String == original["id"] as? String)
            #expect(after[index]["title"] as? String == original["title"] as? String)
            #expect(after[index]["image"] as? String == original["image"] as? String)
        }
    }

    @Test func onLibraryChangedFiresOnlyForSuccessfulUploads() throws {
        #expect(libraryChanges.count == 0)
        try expectError(try client.postJSON("/api/v1/pins", body: ["imageBase64": "!!"]), status: 400, code: "invalid_image_data")
        #expect(libraryChanges.count == 0)

        let first = try client.postRaw("/api/v1/pins?title=First", body: Fixture.pngData, contentType: "image/png")
        #expect(first.status == 201)
        #expect(TestPaths.waitUntil { libraryChanges.count == 1 })

        let second = try client.postRaw("/api/v1/pins?title=Second", body: Fixture.jpegData, contentType: "image/jpeg")
        #expect(second.status == 201)
        #expect(TestPaths.waitUntil { libraryChanges.count == 2 })
    }

    @Test func concurrentUploadsAllPersist() throws {
        let png = samplePNG
        let lock = NSLock()
        var failures: [String] = []
        var created = 0
        DispatchQueue.concurrentPerform(iterations: 4) { index in
            do {
                let result = try self.client.postJSON("/api/v1/pins", body: [
                    "imageBase64": png.base64EncodedString(),
                    "title": "Concurrent \(index)"
                ])
                lock.lock()
                if result.status == 201 {
                    created += 1
                } else {
                    failures.append("request \(index) returned \(result.status): \(result.text.prefix(160))")
                }
                lock.unlock()
            } catch {
                lock.lock()
                failures.append("request \(index): \(error)")
                lock.unlock()
            }
        }
        #expect(failures.isEmpty, "concurrent upload failures: \(failures)")
        #expect(created == 4)
        #expect(TestPaths.waitUntil { libraryChanges.count == 4 })
        let library = try libraryPayload()
        let storedPins = try pins(in: library)
        #expect(storedPins.count == 8)
        let concurrentTitles = storedPins.compactMap { $0["title"] as? String }.filter { $0.hasPrefix("Concurrent ") }
        #expect(Set(concurrentTitles).count == 4)
    }

    // MARK: - Documentation surfaces

    @Test func openAPIDocumentsCreatePin() throws {
        let openapi = try expectJSON(try client.get("/openapi.json"))
        let paths = try #require(openapi["paths"] as? [String: Any])
        let pinsPath = try #require(paths["/api/v1/pins"] as? [String: Any])
        let post = try #require(pinsPath["post"] as? [String: Any], "OpenAPI is missing the POST /api/v1/pins operation")
        #expect(post["operationId"] as? String == "createPin")
        let requestBody = try #require(post["requestBody"] as? [String: Any])
        let content = try #require(requestBody["content"] as? [String: Any])
        #expect(content["application/json"] != nil)
        #expect(content["image/png"] != nil)
        let responses = try #require(post["responses"] as? [String: Any])
        for status in ["201", "400", "413", "415", "500"] {
            #expect(responses[status] != nil, "OpenAPI POST responses missing \(status)")
        }
        let components = try #require(openapi["components"] as? [String: Any])
        let schemas = try #require(components["schemas"] as? [String: Any])
        let createSchema = try #require(schemas["CreatePinRequest"] as? [String: Any])
        #expect(createSchema["required"] as? [String] == ["imageBase64"])
    }

    @Test func docsAndLlmsDescribeIngest() throws {
        let docs = try client.get("/docs")
        #expect(docs.status == 200)
        #expect(docs.text.contains("POST"))
        #expect(docs.text.contains("Add a pin"))
        #expect(docs.text.contains("imageBase64"))
        #expect(docs.text.contains("20 MiB"))
        let llms = try client.get("/llms.txt")
        #expect(llms.status == 200)
        #expect(llms.text.contains("POST /api/v1/pins"))
        #expect(llms.text.contains("Create pin"))
    }
}
