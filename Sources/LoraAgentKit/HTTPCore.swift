import Foundation

// MARK: - HTTP errors

/// An error that maps directly onto a JSON error response.
struct APIError: Error {
    let status: Int
    let code: String
    let message: String
}

// MARK: - Requests

/// A parsed HTTP/1.x request: the head plus the body bytes declared by
/// Content-Length (empty for bodies the route does not accept).
struct HTTPRequest {
    let method: String
    let target: String
    let version: String
    let path: String
    let pathSegments: [String]
    let query: [String: String]
    let headers: [String: String]
    let body: Data

    init(head: HTTPRequestHead, body: Data) {
        self.method = head.method
        self.target = head.target
        self.version = head.version
        self.path = head.path
        self.pathSegments = head.pathSegments
        self.query = head.query
        self.headers = head.headers
        self.body = body
    }

    var isHead: Bool { method == "HEAD" }

    /// Normalized media type without parameters, e.g. `application/json`.
    var contentType: String? {
        guard let raw = header("content-type") else { return nil }
        let mediaType = raw.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let trimmed = mediaType.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    func queryValue(_ name: String) -> String? {
        guard let raw = query[name] else { return nil }
        return raw
    }
}

// MARK: - Responses

struct HTTPResponse {
    var status: Int
    var headers: [String: String]
    var body: Data

    init(status: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    static func json<T: Encodable>(_ value: T, status: Int = 200, extraHeaders: [String: String] = [:]) -> HTTPResponse {
        let data: Data
        do {
            data = try JSONCoding.encode(value)
        } catch {
            return .error(status: 500, code: "encoding_failed", message: "The server could not encode its response.")
        }
        var headers = extraHeaders
        headers["Content-Type"] = "application/json; charset=utf-8"
        headers["Cache-Control"] = "no-store"
        return HTTPResponse(status: status, headers: headers, body: data)
    }

    static func text(_ string: String, status: Int = 200, contentType: String = "text/plain; charset=utf-8", extraHeaders: [String: String] = [:]) -> HTTPResponse {
        var headers = extraHeaders
        headers["Content-Type"] = contentType
        headers["Cache-Control"] = "no-cache"
        return HTTPResponse(status: status, headers: headers, body: Data(string.utf8))
    }

    static func markdown(_ string: String, status: Int = 200, extraHeaders: [String: String] = [:]) -> HTTPResponse {
        text(string, status: status, contentType: "text/markdown; charset=utf-8", extraHeaders: extraHeaders)
    }

    static func html(_ string: String, status: Int = 200, extraHeaders: [String: String] = [:]) -> HTTPResponse {
        text(string, status: status, contentType: "text/html; charset=utf-8", extraHeaders: extraHeaders)
    }

    static func bytes(_ data: Data, contentType: String, status: Int = 200, extraHeaders: [String: String] = [:]) -> HTTPResponse {
        var headers = extraHeaders
        headers["Content-Type"] = contentType
        headers["Cache-Control"] = "no-cache"
        return HTTPResponse(status: status, headers: headers, body: data)
    }

    static func empty(status: Int, headers: [String: String] = [:]) -> HTTPResponse {
        HTTPResponse(status: status, headers: headers, body: Data())
    }

    static func error(status: Int, code: String, message: String, extraHeaders: [String: String] = [:]) -> HTTPResponse {
        .json(ErrorEnvelope(error: ErrorBody(code: code, message: message)), status: status, extraHeaders: extraHeaders)
    }

    /// Serializes the response with correct Content-Length, CORS, and
    /// Connection: close semantics. Body is omitted for 204 and HEAD.
    func serialized(includingBody: Bool) -> Data {
        var head = "HTTP/1.1 \(status) \(HTTPStatus.reason(for: status))\r\n"
        head += "Server: LoraAgentKit/\(LoraAgentAPI.version)\r\n"
        head += "Date: \(HTTPDate.now())\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Access-Control-Allow-Methods: GET, HEAD, OPTIONS, POST, PATCH\r\n"
        head += "Access-Control-Allow-Headers: Accept, Content-Type, Origin\r\n"
        head += "Access-Control-Max-Age: 86400\r\n"
        head += "X-Content-Type-Options: nosniff\r\n"
        for key in headers.keys.sorted() {
            if let value = headers[key] {
                head += "\(key): \(value)\r\n"
            }
        }
        if status != 204 && status != 304 {
            head += "Content-Length: \(body.count)\r\n"
        }
        head += "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        if includingBody && status != 204 && status != 304 {
            data.append(body)
        }
        return data
    }
}

// MARK: - Error payloads

struct ErrorEnvelope: Encodable {
    let error: ErrorBody
}

struct ErrorBody: Encodable {
    let code: String
    let message: String
}

// MARK: - Status helpers

enum HTTPStatus {
    static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        case 415: return "Unsupported Media Type"
        case 500: return "Internal Server Error"
        default: return "Unknown"
        }
    }
}

enum HTTPDate {
    private static let lock = NSLock()
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter
    }()

    static func now() -> String {
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(from: Date())
    }
}

enum Timestamp {
    private static let lock = NSLock()
    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func nowString() -> String {
        lock.lock()
        defer { lock.unlock() }
        return plain.string(from: Date())
    }

    static func date(from string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return fractional.date(from: trimmed) ?? plain.date(from: trimmed)
    }
}

// MARK: - Percent coding

enum PercentCoding {
    private static let unreserved: Set<UInt8> = {
        var set = Set<UInt8>()
        for byte in UInt8(ascii: "A")...UInt8(ascii: "Z") { set.insert(byte) }
        for byte in UInt8(ascii: "a")...UInt8(ascii: "z") { set.insert(byte) }
        for byte in UInt8(ascii: "0")...UInt8(ascii: "9") { set.insert(byte) }
        for scalar in "-._~".unicodeScalars { set.insert(UInt8(scalar.value)) }
        return set
    }()

    /// Percent-encodes a single URL path segment (e.g. a pin UUID).
    static func encodePathSegment(_ value: String) -> String {
        var out = String()
        out.reserveCapacity(value.utf8.count)
        for byte in value.utf8 {
            if unreserved.contains(byte) {
                out.unicodeScalars.append(UnicodeScalar(byte))
            } else {
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }

    /// Decodes percent escapes. Throws a 400 APIError on malformed escapes or
    /// invalid UTF-8. When plusAsSpace is true, "+" becomes a space (query
    /// string semantics, application/x-www-form-urlencoded).
    static func decode(_ value: String, plusAsSpace: Bool, component: String) throws -> String {
        let bytes = Array(value.utf8)
        var decoded: [UInt8] = []
        decoded.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x25 { // %
                guard index + 2 < bytes.count,
                      let high = hexValue(bytes[index + 1]),
                      let low = hexValue(bytes[index + 2]) else {
                    throw APIError(status: 400, code: "invalid_percent_encoding", message: "The \"\(component)\" value contains an invalid percent-encoding sequence.")
                }
                decoded.append(high << 4 | low)
                index += 3
            } else if byte == 0x2B && plusAsSpace { // +
                decoded.append(0x20)
                index += 1
            } else {
                decoded.append(byte)
                index += 1
            }
        }
        guard let string = String(bytes: decoded, encoding: .utf8) else {
            throw APIError(status: 400, code: "invalid_utf8", message: "The \"\(component)\" value is not valid UTF-8.")
        }
        return string
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return byte - UInt8(ascii: "A") + 10
        default: return nil
        }
    }
}

// MARK: - JSON coding

enum JSONCoding {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    /// Pretty, sorted output used when writing library.json so the file stays
    /// human-readable and diff-friendly, matching the Lora app's writer.
    static func encodePretty<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
