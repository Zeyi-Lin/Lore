import Testing
import Foundation
@testable import LoreAgentKit

@Suite(.serialized)
final class HTTPBehaviorTests: RunningServerSuite {

    // MARK: - Discovery surfaces

    @Test func landingPageLinksToDocs() throws {
        let landing = try client.get("/")
        #expect(landing.status == 200)
        #expect(landing.header("content-type")?.hasPrefix("text/html") == true)
        #expect(landing.text.contains("href=\"/docs\""))
        #expect(landing.text.contains("Lore Agent API"))
        #expect(landing.text.contains("127.0.0.1:\(port)"))
    }

    @Test func docsPageIsPolishedOfflineHTML() throws {
        let docs = try client.get("/docs")
        #expect(docs.status == 200)
        #expect(docs.header("content-type")?.hasPrefix("text/html") == true)
        let html = docs.text
        #expect(html.contains("<!doctype html>"))
        #expect(html.contains("#E60023"), "docs must use the Pinterest-inspired accent")
        #expect(html.contains("Quickstart"))
        #expect(html.contains("Endpoints"))
        #expect(html.contains("data-copy="))
        #expect(html.contains(baseURL))
        #expect(html.contains("/openapi.json"))
        #expect(html.contains("/llms.txt"))
        #expect(html.contains("127.0.0.1:\(port)"))
        #expect(!html.contains("https://cdn"))
        #expect(!html.contains("fonts.googleapis"))
        #expect(!html.contains("http://fonts"))
        #expect(!html.contains("url(http"), "docs must not reference external assets")
        #expect(!html.contains("@import"))
    }

    @Test func headDocsMatchesBodyLength() throws {
        let get = try client.get("/docs")
        let head = try client.head("/docs")
        #expect(head.status == 200)
        #expect(head.header("content-length") == String(get.body.count))
        #expect(head.body.isEmpty)
    }

    @Test func openAPISpecIsValid31() throws {
        let result = try client.get("/openapi.json")
        #expect(result.status == 200)
        #expect(result.header("content-type")?.contains("application/json") == true)
        let spec = try result.jsonObject()

        #expect(spec["openapi"] as? String == "3.1.0")
        let info = try #require(spec["info"] as? [String: Any])
        #expect(info["title"] as? String == "Lore Agent API")
        #expect(info["version"] as? String != nil)

        let servers = try #require(spec["servers"] as? [[String: Any]])
        #expect(servers.first?["url"] as? String == baseURL)

        let paths = try #require(spec["paths"] as? [String: Any])
        let expectedPaths: Set<String> = [
            "/", "/docs", "/llms.txt", "/openapi.json", "/health", "/api/v1/health",
            "/api/v1/library", "/api/v1/pins", "/api/v1/pins/{id}", "/api/v1/pins/{id}/image",
            "/api/v1/boards", "/api/v1/tags", "/api/v1/stats", "/api/v1/context"
        ]
        #expect(Set(paths.keys) == expectedPaths)

        for (path, value) in paths {
            let pathItem = try #require(value as? [String: Any], "bad path item for \(path)")
            let get = try #require(pathItem["get"] as? [String: Any], "missing GET for \(path)")
            let responses = try #require(get["responses"] as? [String: Any], "missing responses for \(path)")
            #expect(responses["200"] != nil, "missing 200 response for \(path)")
            #expect(pathItem["head"] as? [String: Any] != nil, "missing HEAD for \(path)")
        }

        let components = try #require(spec["components"] as? [String: Any])
        let schemas = try #require(components["schemas"] as? [String: Any])
        let refs = collectRefs(in: spec)
        #expect(!refs.isEmpty)
        for ref in refs {
            let prefix = "#/components/schemas/"
            #expect(ref.hasPrefix(prefix), "unsupported ref \(ref)")
            let name = String(ref.dropFirst(prefix.count))
            #expect(schemas[name] != nil, "dangling ref \(ref)")
        }
        #expect(schemas["EnrichedPin"] != nil)
        #expect(schemas["Library"] != nil)
        #expect(schemas["Error"] != nil)
    }

    private func collectRefs(in value: Any) -> [String] {
        var refs: [String] = []
        if let dictionary = value as? [String: Any] {
            for (key, nested) in dictionary {
                if key == "$ref", let ref = nested as? String {
                    refs.append(ref)
                } else {
                    refs.append(contentsOf: collectRefs(in: nested))
                }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                refs.append(contentsOf: collectRefs(in: nested))
            }
        }
        return refs
    }

    @Test func llmsTxtIndex() throws {
        let result = try client.get("/llms.txt")
        #expect(result.status == 200)
        #expect(result.header("content-type")?.hasPrefix("text/plain") == true)
        let text = result.text
        #expect(text.hasPrefix("# Lore Agent API"))
        #expect(text.contains("> Lore is a local macOS visual library"))
        #expect(text.contains("\(baseURL)/api/v1/pins"))
        #expect(text.contains("\(baseURL)/docs"))
        #expect(text.contains("\(baseURL)/openapi.json"))
        #expect(text.contains("## Endpoints"))
        #expect(text.contains("## Example"))
    }

    // MARK: - Methods and CORS

    @Test func optionsPreflightAndCORSHeaders() throws {
        let options = try client.options("/api/v1/pins")
        #expect(options.status == 204)
        #expect(options.header("access-control-allow-origin") == "*")
        #expect(options.header("access-control-allow-methods")?.contains("GET") == true)
        #expect(options.header("access-control-allow-headers")?.contains("Content-Type") == true)
        let allow = options.header("allow") ?? ""
        #expect(allow.contains("GET"))
        #expect(allow.contains("HEAD"))
        #expect(allow.contains("OPTIONS"))
        #expect(options.body.isEmpty)

        let get = try client.get("/health")
        #expect(get.header("access-control-allow-origin") == "*")

        let missing = try client.get("/does-not-exist")
        #expect(missing.status == 404)
        #expect(missing.header("access-control-allow-origin") == "*")
    }

    @Test func methodNotAllowed() throws {
        for (method, path) in [("POST", "/api/v1/library"), ("PUT", "/health"), ("DELETE", "/api/v1/pins"), ("PATCH", "/docs")] {
            let result: HTTPResult
            if method == "POST" {
                result = try client.post(path)
            } else {
                result = try client.request(path, method: method)
            }
            #expect(result.status == 405, "expected 405 for \(method) \(path)")
            #expect(result.header("allow")?.contains("GET") == true)
            let object = try result.jsonObject()
            let error = try #require(object["error"] as? [String: Any])
            #expect(error["code"] as? String == "method_not_allowed")
        }
    }

    @Test func unknownRoutesReturn404JSON() throws {
        for path in ["/nope", "/api/v1/nope", "/api/v2/library", "/api/v1/pins/\(Fixture.auroraID)/extra", "/api/v1"] {
            try expectError(try client.get(path), status: 404, code: "not_found", path)
        }
    }

    // MARK: - Raw HTTP parsing

    @Test func rawCurlStyleRequestSucceeds() throws {
        let raw = try RawHTTP.send(port: port, "GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\nAccept: */*\r\nConnection: close\r\n\r\n")
        #expect(raw.status == 200)
        #expect(raw.header("connection") == "close")
        #expect(raw.header("content-type") == "application/json; charset=utf-8")
        let object = try raw.jsonObject()
        #expect(object["status"] as? String == "ok")
    }

    @Test func malformedRawRequestsReturnJSONErrors() throws {
        var result = try RawHTTP.send(port: port, "GARBAGE\r\n\r\n")
        try expectError(result, status: 400, code: "bad_request")

        result = try RawHTTP.send(port: port, "GET / HTTP/9.9\r\nHost: x\r\n\r\n")
        try expectError(result, status: 400, code: "unsupported_http_version")

        result = try RawHTTP.send(port: port, "GET / HTTP/1.1\r\nBrokenHeaderLine\r\n\r\n")
        try expectError(result, status: 400, code: "bad_request")

        result = try RawHTTP.send(port: port, "GET http://example.com/ HTTP/1.1\r\nHost: x\r\n\r\n")
        try expectError(result, status: 400, code: "bad_request")
    }

    @Test func oversizedRequestHeadersAreRejected() throws {
        let padding = String(repeating: "a", count: 40 * 1024)
        let raw = "GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Padding: \(padding)\r\n\r\n"
        let result = try RawHTTP.send(port: port, raw)
        try expectError(result, status: 400, code: "request_header_too_large")
    }

    @Test func dotSegmentPathsAreRejected() throws {
        let result = try RawHTTP.send(port: port, "GET /api/v1/../library HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
        try expectError(result, status: 404, code: "not_found")

        let encoded = try RawHTTP.send(port: port, "GET /api/v1/pins/..%2F..%2Fsecret/image HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
        try expectError(encoded, status: 404, code: "not_found")
    }

    // MARK: - Path traversal protection

    @Test func traversalPathsCannotEscapeLibraryRoot() throws {
        let secret = "LORE_TRAVERSAL_SECRET_\(UUID().uuidString)"
        let secretURL = scenario.baseDirectory.appendingPathComponent("secret.txt")
        try secret.write(to: secretURL, atomically: true, encoding: .utf8)

        let symlinkURL = scenario.libraryRoot.appendingPathComponent("Images/escape.png")
        try? FileManager.default.removeItem(at: symlinkURL)
        try FileManager.default.createSymbolicLink(atPath: symlinkURL.path, withDestinationPath: "../../secret.txt")

        func hostilePin(id: String, image: String, thumbnail: String?) -> PinFixture {
            var pin = PinFixture(id: id)
            pin.title = "Hostile pin"
            pin.image = image
            pin.thumbnail = thumbnail
            return pin
        }
        let relativeID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let absoluteID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        let symlinkID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        let fallbackID = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
        let pins = [
            hostilePin(id: relativeID, image: "../../secret.txt", thumbnail: nil).json(),
            hostilePin(id: absoluteID, image: "/etc/passwd", thumbnail: nil).json(),
            hostilePin(id: symlinkID, image: "Images/escape.png", thumbnail: nil).json(),
            hostilePin(id: fallbackID, image: "Images/aurora.png", thumbnail: "../../secret.txt").json()
        ]
        try scenario.writeLibrary(pins)

        for id in [relativeID, absoluteID, symlinkID] {
            let result = try client.get("/api/v1/pins/\(id)/image")
            try expectError(result, status: 404, code: "image_not_found")
            #expect(!result.text.contains(secret), "traversal leaked secret content")
            #expect(!result.text.contains("root:"), "traversal leaked /etc/passwd")
        }

        let fallback = try client.get("/api/v1/pins/\(fallbackID)/image?variant=thumb")
        #expect(fallback.status == 200)
        #expect(fallback.body == Fixture.pngData)
        #expect(!fallback.text.contains(secret))
    }

    // MARK: - HEAD

    @Test func headJSONEndpointsReturnNoBody() throws {
        for path in ["/api/v1/library", "/api/v1/pins", "/health", "/api/v1/context"] {
            let get = try client.get(path)
            let head = try client.head(path)
            #expect(head.status == 200, "HEAD \(path)")
            #expect(head.body.isEmpty, "HEAD \(path) must not include a body")
            #expect(head.header("content-length") == String(get.body.count), "HEAD \(path) content-length")
        }
    }

    // MARK: - Concurrency

    @Test func concurrentRequests() throws {
        let lock = NSLock()
        var failures: [String] = []
        var successes = 0
        DispatchQueue.concurrentPerform(iterations: 12) { index in
            do {
                let result = try self.client.get(index % 2 == 0 ? "/api/v1/library" : "/api/v1/pins?limit=2")
                lock.lock()
                if result.status == 200 {
                    successes += 1
                } else {
                    failures.append("status \(result.status) for request \(index)")
                }
                lock.unlock()
            } catch {
                lock.lock()
                failures.append("request \(index): \(error)")
                lock.unlock()
            }
        }
        #expect(failures.isEmpty, "concurrent request failures: \(failures)")
        #expect(successes == 12)
    }
}

// MARK: - Lifecycle

@Suite(.serialized)
struct ServerLifecycleTests {

    @Test func startStopAndRestartOnFixedPort() throws {
        let base = try TestPaths.makeScenarioBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("LoreLibrary", isDirectory: true)
        try Fixture.writeLibrary(pins: Fixture.defaultPins(), to: root)
        let port = try TestPaths.freePort()
        let recorder = StatusRecorder()
        let server = LoreAgentServer(config: AgentServerConfig(port: port, libraryRoot: root))
        server.onStatusChange = { [recorder] status in recorder.record(status) }

        #expect(server.status == AgentServerStatus.stopped)
        #expect(server.baseURL == nil)
        #expect(!server.isRunning)

        server.start()
        server.start() // must be idempotent
        let boundPort = try TestPaths.waitForRunning(server)
        #expect(boundPort == port)
        #expect(server.baseURL?.absoluteString == "http://127.0.0.1:\(port)")
        #expect(server.isRunning)

        let client = HTTPClient(port: boundPort)
        #expect(try client.get("/health").status == 200)

        #expect(TestPaths.waitUntil { recorder.snapshot.contains(AgentServerStatus.starting) })
        #expect(TestPaths.waitUntil {
            recorder.snapshot.contains { status in
                if case .running = status { return true }
                return false
            }
        })

        server.stop()
        #expect(server.status == AgentServerStatus.stopped)
        #expect(server.runningPort == nil)
        #expect(TestPaths.waitUntil { recorder.snapshot.last == AgentServerStatus.stopped })

        // Restart on the same fixed port: stop() must have released the socket.
        server.start()
        let restartedPort = try TestPaths.waitForRunning(server)
        #expect(restartedPort == port)
        #expect(try HTTPClient(port: restartedPort).get("/health").status == 200)
        server.stop()
        #expect(TestPaths.waitUntil { server.status == AgentServerStatus.stopped })
    }

    @Test func portConflictReportsFailure() throws {
        let base = try TestPaths.makeScenarioBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("LoreLibrary", isDirectory: true)
        try Fixture.writeLibrary(pins: Fixture.defaultPins(), to: root)
        let port = try TestPaths.freePort()

        let first = LoreAgentServer(config: AgentServerConfig(port: port, libraryRoot: root))
        defer { first.stop() }
        first.start()
        _ = try TestPaths.waitForRunning(first)

        let second = LoreAgentServer(config: AgentServerConfig(port: port, libraryRoot: root))
        defer { second.stop() }
        second.start()
        let deadline = Date().addingTimeInterval(10)
        var failureMessage: String?
        while Date() < deadline {
            if case .failed(let message) = second.status {
                failureMessage = message
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        let message = try #require(failureMessage, "second server should fail to bind an occupied port")
        let lowered = message.lowercased()
        #expect(lowered.contains("listen") || lowered.contains("address") || lowered.contains("bind"))
    }
}
