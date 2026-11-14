import Testing
import Foundation
import Darwin
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import LoraAgentKit

// MARK: - Failures and result types

enum TestFailure: Error, CustomStringConvertible {
    case invalidURL(String)
    case timeout(String)
    case invalidJSON(String)
    case requestFailed(String)
    case socket(String)
    case serverFailed(String)

    var description: String {
        switch self {
        case .invalidURL(let value): return "Invalid URL: \(value)"
        case .timeout(let value): return "Timed out: \(value)"
        case .invalidJSON(let value): return "Invalid JSON: \(value)"
        case .requestFailed(let value): return "Request failed: \(value)"
        case .socket(let value): return "Socket error: \(value)"
        case .serverFailed(let value): return "Server failed: \(value)"
        }
    }
}

struct HTTPResult {
    let status: Int
    let headers: [String: String]
    let body: Data

    var text: String {
        String(decoding: body, as: UTF8.self)
    }

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    func jsonObject() throws -> [String: Any] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: body)
        } catch {
            throw TestFailure.invalidJSON("body is not JSON: \(text.prefix(400))")
        }
        guard let dictionary = object as? [String: Any] else {
            throw TestFailure.invalidJSON("expected a JSON object, got \(type(of: object))")
        }
        return dictionary
    }
}

// MARK: - Shared assertions

@discardableResult
func expectJSON(_ result: HTTPResult, _ label: String = "") throws -> [String: Any] {
    try expectJSONStatus(result, status: 200, label)
}

@discardableResult
func expectJSONStatus(_ result: HTTPResult, status: Int, _ label: String = "") throws -> [String: Any] {
    #expect(result.status == status, "\(label) expected HTTP \(status), got \(result.status): \(result.text.prefix(400))")
    #expect(result.header("content-type")?.contains("application/json") == true, "\(label) expected a JSON content type")
    return try result.jsonObject()
}

func expectError(_ result: HTTPResult, status: Int, code: String, _ label: String = "") throws {
    #expect(result.status == status, "\(label) expected HTTP \(status), got \(result.status): \(result.text.prefix(400))")
    #expect(result.header("content-type")?.contains("application/json") == true, "\(label) expected a JSON error content type")
    let object = try result.jsonObject()
    let error = try #require(object["error"] as? [String: Any], "\(label) missing error envelope")
    #expect(error["code"] as? String == code, "\(label) unexpected error code: \(String(describing: error["code"]))")
    #expect((error["message"] as? String)?.isEmpty == false, "\(label) error message must not be empty")
}

func pinsFromList(_ result: [String: Any]) throws -> [[String: Any]] {
    guard let pins = result["pins"] as? [[String: Any]] else {
        throw TestFailure.invalidJSON("pins array missing: \(result)")
    }
    return pins
}

// MARK: - HTTP client

private final class LockedBox<Value> {
    private let lock = NSLock()
    private var stored: Value?

    func set(_ value: Value) {
        lock.lock()
        stored = value
        lock.unlock()
    }

    func get() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

final class HTTPClient {
    let baseURL: String
    private let session: URLSession

    init(port: UInt16) {
        self.baseURL = "http://127.0.0.1:\(port)"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: configuration)
    }

    func get(_ path: String) throws -> HTTPResult {
        try request(path, method: "GET")
    }

    func head(_ path: String) throws -> HTTPResult {
        try request(path, method: "HEAD")
    }

    func post(_ path: String) throws -> HTTPResult {
        try request(path, method: "POST")
    }

    func options(_ path: String) throws -> HTTPResult {
        try request(path, method: "OPTIONS")
    }

    func postJSON(_ path: String, body: Any) throws -> HTTPResult {
        let data = try JSONSerialization.data(withJSONObject: body)
        return try request(path, method: "POST", body: data, contentType: "application/json")
    }

    func postRaw(_ path: String, body: Data, contentType: String) throws -> HTTPResult {
        try request(path, method: "POST", body: body, contentType: contentType)
    }

    func request(_ path: String, method: String, body: Data? = nil, contentType: String? = nil) throws -> HTTPResult {
        guard let url = URL(string: baseURL + path) else {
            throw TestFailure.invalidURL(baseURL + path)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let body {
            request.httpBody = body
        }
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        let semaphore = DispatchSemaphore(value: 0)
        let box = LockedBox<Result<HTTPResult, Error>>()
        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                box.set(.failure(TestFailure.requestFailed("\(method) \(path): \(error)")))
            } else if let httpResponse = response as? HTTPURLResponse {
                var headers: [String: String] = [:]
                for (key, value) in httpResponse.allHeaderFields {
                    headers[String(describing: key).lowercased()] = String(describing: value)
                }
                box.set(.success(HTTPResult(status: httpResponse.statusCode, headers: headers, body: data ?? Data())))
            } else {
                box.set(.failure(TestFailure.requestFailed("\(method) \(path): missing HTTP response")))
            }
            semaphore.signal()
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + 25) == .success else {
            task.cancel()
            throw TestFailure.timeout("\(method) \(path)")
        }
        guard let result = box.get() else {
            throw TestFailure.timeout("\(method) \(path): no result")
        }
        return try result.get()
    }
}

// MARK: - Raw socket client (for malformed requests)

enum RawHTTP {
    static func send(port: UInt16, _ text: String) throws -> HTTPResult {
        try send(port: port, bytes: Data(text.utf8))
    }

    static func send(port: UInt16, bytes: Data) throws -> HTTPResult {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw TestFailure.socket("socket() failed with errno \(errno)")
        }
        defer { close(descriptor) }

        var timeout = timeval(tv_sec: 15, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.connect(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else {
            throw TestFailure.socket("connect() failed with errno \(errno)")
        }

        try bytes.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < rawBuffer.count {
                let written = Darwin.send(descriptor, baseAddress.advanced(by: sent), rawBuffer.count - sent, 0)
                if written <= 0 {
                    throw TestFailure.socket("send() failed with errno \(errno)")
                }
                sent += written
            }
        }
        _ = shutdown(descriptor, Int32(SHUT_WR))

        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = Darwin.recv(descriptor, &buffer, buffer.count, 0)
            if count <= 0 { break }
            received.append(contentsOf: buffer[0..<count])
        }
        return try parse(received)
    }

    static func parse(_ data: Data) throws -> HTTPResult {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: separator) else {
            throw TestFailure.invalidJSON("raw response has no header terminator: \(String(decoding: data.prefix(400), as: UTF8.self))")
        }
        let head = String(decoding: data[data.startIndex..<range.lowerBound], as: UTF8.self)
        let body = Data(data[range.upperBound...])
        let lines = head.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else {
            throw TestFailure.invalidJSON("raw response has no status line")
        }
        let parts = statusLine.split(separator: " ")
        guard parts.count >= 2, let status = Int(parts[1]) else {
            throw TestFailure.invalidJSON("raw response has no numeric status: \(statusLine)")
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[line.startIndex..<colon]).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        return HTTPResult(status: status, headers: headers, body: body)
    }
}

// MARK: - Fixtures

struct PinFixture {
    var id: String
    var title: String = "Untitled pin"
    var note: String = ""
    var image: String = "Images/aurora.png"
    var thumbnail: String? = nil
    var width: Int = 1440
    var height: Int = 900
    var fileSize: Int = 70
    var createdAt: String = "2026-11-02T10:24:00Z"
    var updatedAt: String = "2026-11-02T10:24:00Z"
    var tags: [String] = []
    var board: String = "Web dashboards"
    var sourceURL: String? = nil
    var sourceLabel: String? = nil
    var colors: [String] = []
    var favorite: Bool = false
    var kind: String = "screenshot"

    func json() -> [String: Any] {
        var dictionary: [String: Any] = [
            "id": id,
            "title": title,
            "note": note,
            "image": image,
            "width": width,
            "height": height,
            "fileSize": fileSize,
            "createdAt": createdAt,
            "updatedAt": updatedAt,
            "tags": tags,
            "board": board,
            "colors": colors,
            "favorite": favorite,
            "kind": kind
        ]
        dictionary["thumbnail"] = thumbnail.map { $0 as Any } ?? NSNull()
        dictionary["sourceURL"] = sourceURL.map { $0 as Any } ?? NSNull()
        dictionary["sourceLabel"] = sourceLabel.map { $0 as Any } ?? NSNull()
        return dictionary
    }
}

enum Fixture {
    static let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
    static let jpegData = Data(base64Encoded: "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD3+iiigD//2Q==")!

    static let auroraID = "11111111-1111-4111-8111-111111111111"
    static let ledgerID = "22222222-2222-4222-8222-222222222222"
    static let noemaID = "33333333-3333-4333-8333-333333333333"
    static let zephyrID = "44444444-4444-4444-8444-444444444444"

    static func files() -> [String: Data] {
        return [
            "Images/aurora.png": pngData,
            "Thumbnails/aurora.jpg": jpegData,
            "Images/ledger.png": pngData,
            "Images/noema.png": pngData,
            "Thumbnails/noema.jpg": jpegData,
            "Images/zephyr.png": pngData
        ]
    }

    static func defaultPins() -> [[String: Any]] {
        var aurora = PinFixture(id: auroraID, title: "Aurora analytics overview")
        aurora.note = "Dark analytics dashboard with magenta highlights and dense KPI cards."
        aurora.image = "Images/aurora.png"
        aurora.thumbnail = "Thumbnails/aurora.jpg"
        aurora.width = 1440
        aurora.height = 900
        aurora.fileSize = pngData.count
        aurora.tags = ["dashboard", "analytics", "dark"]
        aurora.board = "Web dashboards"
        aurora.sourceURL = "https://dribbble.com/shots/1"
        aurora.sourceLabel = "Dribbble"
        aurora.colors = ["#0E1117", "#E60023", "#F5F5F7"]
        aurora.favorite = true
        aurora.kind = "screenshot"

        var ledger = PinFixture(id: ledgerID, title: "Ledger onboarding")
        ledger.note = "Warm editorial mobile onboarding flow with generous spacing."
        ledger.image = "Images/ledger.png"
        ledger.thumbnail = nil
        ledger.width = 390
        ledger.height = 844
        ledger.fileSize = pngData.count
        ledger.createdAt = "2026-11-05T09:00:00Z"
        ledger.updatedAt = "2026-11-05T09:00:00Z"
        ledger.tags = ["mobile", "onboarding"]
        ledger.board = "Mobile flows"
        ledger.sourceLabel = "Lora Seed"
        ledger.colors = ["#F4EDE4", "#1F1B16"]

        var noema = PinFixture(id: noemaID, title: "Noema field notes")
        noema.note = "Typographic editorial page with a quiet grid and serif display type."
        noema.image = "Images/noema.png"
        noema.thumbnail = "Thumbnails/noema.jpg"
        noema.width = 1440
        noema.height = 1000
        noema.fileSize = pngData.count
        noema.createdAt = "2026-11-09T12:30:00Z"
        noema.updatedAt = "2026-11-09T12:30:00Z"
        noema.tags = ["editorial", "typography"]
        noema.board = "Editorial"
        noema.colors = ["#F7F3EC"]

        var zephyr = PinFixture(id: zephyrID, title: "Zephyr pricing page")
        zephyr.note = "Landing page with three-tier pricing and soft gradients."
        zephyr.image = "Images/zephyr.png"
        zephyr.thumbnail = nil
        zephyr.width = 1440
        zephyr.height = 1000
        zephyr.fileSize = pngData.count
        zephyr.createdAt = "2026-11-12T18:45:00Z"
        zephyr.updatedAt = "2026-11-12T18:45:00Z"
        zephyr.tags = ["landing", "pricing"]
        zephyr.board = "Landing pages"
        zephyr.sourceLabel = "Lora Seed"
        zephyr.colors = ["#111111"]

        return [aurora.json(), ledger.json(), noema.json(), zephyr.json()]
    }

    static func writeLibrary(pins: [[String: Any]], to root: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root.appendingPathComponent("Images", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root.appendingPathComponent("Thumbnails", isDirectory: true), withIntermediateDirectories: true)
        for (relativePath, data) in files() {
            try data.write(to: root.appendingPathComponent(relativePath))
        }
        let library: [String: Any] = ["version": 1, "pins": pins]
        let data = try JSONSerialization.data(withJSONObject: library, options: [.sortedKeys, .prettyPrinted])
        try data.write(to: root.appendingPathComponent("library.json"))
    }

    static func writeRawLibrary(_ text: String, to root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try text.write(to: root.appendingPathComponent("library.json"), atomically: true, encoding: .utf8)
    }

    /// Generates a PNG with three vertical colour bands (red, green, blue),
    /// used to exercise image validation, dimensions, thumbnails, and palettes.
    static func makePNG(width: Int = 120, height: Int = 80) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("Could not create a CGContext for the fixture image")
        }
        let bandWidth = CGFloat(width) / 3.0
        context.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.15, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: bandWidth, height: CGFloat(height)))
        context.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.3, alpha: 1.0))
        context.fill(CGRect(x: bandWidth, y: 0, width: bandWidth, height: CGFloat(height)))
        context.setFillColor(CGColor(red: 0.12, green: 0.2, blue: 0.65, alpha: 1.0))
        context.fill(CGRect(x: bandWidth * 2, y: 0, width: CGFloat(width) - bandWidth * 2, height: CGFloat(height)))
        guard let image = context.makeImage() else {
            fatalError("Could not render the fixture image")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            fatalError("Could not create a PNG destination")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            fatalError("Could not encode the fixture PNG")
        }
        return Data(referencing: output)
    }

    /// Decodes image dimensions from in-memory bytes, for thumbnail assertions.
    static func imageDimensions(_ data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return (width, height)
    }
}

// MARK: - Scenario

final class StatusRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [AgentServerStatus] = []

    func record(_ status: AgentServerStatus) {
        lock.lock()
        values.append(status)
        lock.unlock()
    }

    var snapshot: [AgentServerStatus] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

final class LibraryChangeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func record() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

final class AgentAPIScenario {
    let baseDirectory: URL
    let libraryRoot: URL
    let server: LoraAgentServer
    let recorder: StatusRecorder
    let libraryChanges: LibraryChangeRecorder
    let port: UInt16
    let client: HTTPClient

    init(pins: [[String: Any]]? = nil, rawLibrary: String? = nil, port requestedPort: UInt16 = 0) throws {
        let base = try TestPaths.makeScenarioBase()
        let root = base.appendingPathComponent("LoraLibrary", isDirectory: true)
        if let rawLibrary {
            try Fixture.writeRawLibrary(rawLibrary, to: root)
        } else {
            try Fixture.writeLibrary(pins: pins ?? Fixture.defaultPins(), to: root)
        }
        let recorder = StatusRecorder()
        let libraryChanges = LibraryChangeRecorder()
        let server = LoraAgentServer(config: AgentServerConfig(port: requestedPort, libraryRoot: root))
        server.onStatusChange = { [recorder] status in
            recorder.record(status)
        }
        server.onLibraryChanged = { [libraryChanges] in
            libraryChanges.record()
        }
        self.baseDirectory = base
        self.libraryRoot = root
        self.recorder = recorder
        self.libraryChanges = libraryChanges
        self.server = server
        server.start()
        let boundPort = try TestPaths.waitForRunning(server)
        self.port = boundPort
        self.client = HTTPClient(port: boundPort)
    }

    var baseURL: String {
        "http://127.0.0.1:\(port)"
    }

    var libraryFile: URL {
        libraryRoot.appendingPathComponent("library.json")
    }

    func writeLibrary(_ pins: [[String: Any]]) throws {
        try Fixture.writeLibrary(pins: pins, to: libraryRoot)
    }

    func writeRawLibrary(_ text: String) throws {
        try Fixture.writeRawLibrary(text, to: libraryRoot)
    }

    func removeLibraryFile() throws {
        try FileManager.default.removeItem(at: libraryFile)
    }

    func cleanup() {
        server.stop()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if case .stopped = server.status { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        try? FileManager.default.removeItem(at: baseDirectory)
    }

    deinit {
        server.stop()
        try? FileManager.default.removeItem(at: baseDirectory)
    }
}

// MARK: - Shared suite lifecycle

/// Base class for suites that need a running server backed by the fixture library.
/// Swift Testing creates a fresh instance for every test and calls deinit afterwards,
/// so each test gets an isolated ephemeral-port server and temporary library root.
class RunningServerSuite {
    let scenario: AgentAPIScenario

    init() throws {
        scenario = try AgentAPIScenario()
    }

    deinit {
        scenario.cleanup()
    }

    var client: HTTPClient { scenario.client }
    var port: UInt16 { scenario.port }
    var root: URL { scenario.libraryRoot }
    var baseURL: String { scenario.baseURL }
    var libraryChanges: LibraryChangeRecorder { scenario.libraryChanges }
}

// MARK: - Paths and ports

enum TestPaths {
    static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static var testsRoot: URL {
        packageRoot.appendingPathComponent(".build/agent-api-tests", isDirectory: true)
    }

    static func makeScenarioBase() throws -> URL {
        let base = testsRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func waitForRunning(_ server: LoraAgentServer, timeout: TimeInterval = 10) throws -> UInt16 {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch server.status {
            case .running(let port):
                return port
            case .failed(let message):
                throw TestFailure.serverFailed(message)
            case .stopped, .starting:
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        throw TestFailure.timeout("server did not reach .running within \(timeout) seconds")
    }

    static func waitUntil(timeout: TimeInterval = 5, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return condition()
    }

    static func freePort() throws -> UInt16 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw TestFailure.socket("socket() failed with errno \(errno)")
        }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            throw TestFailure.socket("bind() failed with errno \(errno)")
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(descriptor, socketAddress, &length)
            }
        }
        guard named == 0 else {
            throw TestFailure.socket("getsockname() failed with errno \(errno)")
        }
        return UInt16(bigEndian: address.sin_port)
    }
}
