import Foundation

// MARK: - HTTP errors

/// An error that maps directly onto a JSON error response.
struct APIError: Error {
    let status: Int
    let code: String
    let message: String
}

// MARK: - Requests

/// A parsed HTTP/1.x request. Only the head is retained; Canta's API is
/// read-only, so request bodies are accepted but never interpreted.
struct HTTPRequest {
    let method: String
    let target: String
    let version: String
    let path: String
    let pathSegments: [String]
    let query: [String: String]
    let headers: [String: String]

    var isHead: Bool { method == "HEAD" }

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
        head += "Server: CantaAgentKit/\(CantaAgentAPI.version)\r\n"
        head += "Date: \(HTTPDate.now())\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Access-Control-Allow-Methods: GET, HEAD, OPTIONS\r\n"
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
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
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
}

// MARK: - Request parsing

enum HTTPParseResult {
    case incomplete
    case request(HTTPRequest)
    case failure(APIError)
}

enum HTTPRequestParser {
    /// Maximum size of the request head (request line + headers), in bytes.
    static let maxHeaderBytes = 32 * 1024
    /// Maximum accepted value of a Content-Length header.
    static let maxBodyBytes = 1024 * 1024

    private static let crlfTerminator = Data("\r\n\r\n".utf8)
    private static let lfTerminator = Data("\n\n".utf8)

    static func parse(buffer: Data) -> HTTPParseResult {
        guard let terminator = terminatorRange(in: buffer) else {
            if buffer.count > maxHeaderBytes {
                return .failure(APIError(status: 400, code: "request_header_too_large", message: "Request headers exceed the \(maxHeaderBytes) byte limit."))
            }
            return .incomplete
        }
        if buffer.distance(from: buffer.startIndex, to: terminator.lowerBound) > maxHeaderBytes {
            return .failure(APIError(status: 400, code: "request_header_too_large", message: "Request headers exceed the \(maxHeaderBytes) byte limit."))
        }
        let head = buffer[buffer.startIndex..<terminator.lowerBound]
        do {
            return .request(try parseHead(Data(head)))
        } catch let error as APIError {
            return .failure(error)
        } catch {
            return .failure(APIError(status: 400, code: "bad_request", message: "The HTTP request could not be parsed."))
        }
    }

    private static func terminatorRange(in buffer: Data) -> Range<Data.Index>? {
        if let range = buffer.range(of: crlfTerminator) {
            return range
        }
        return buffer.range(of: lfTerminator)
    }

    private static func parseHead(_ head: Data) throws -> HTTPRequest {
        let text = String(decoding: head, as: UTF8.self)
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            throw APIError(status: 400, code: "bad_request", message: "The HTTP request has no request line.")
        }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 3 else {
            throw APIError(status: 400, code: "bad_request", message: "The HTTP request line must contain a method, target, and HTTP version.")
        }
        let method = parts[0]
        let target = parts[1]
        let version = parts[2]

        guard method.allSatisfy({ $0.isUppercase && $0.isLetter }), !method.isEmpty else {
            throw APIError(status: 400, code: "bad_request", message: "The HTTP method is not a valid token.")
        }
        guard version == "HTTP/1.1" || version == "HTTP/1.0" else {
            throw APIError(status: 400, code: "unsupported_http_version", message: "Only HTTP/1.0 and HTTP/1.1 requests are supported.")
        }
        guard target.hasPrefix("/") else {
            throw APIError(status: 400, code: "bad_request", message: "The request target must be an origin-form path beginning with \"/\".")
        }

        var rawPath = target
        var rawQuery: String? = nil
        if let questionIndex = target.firstIndex(of: "?") {
            rawPath = String(target[target.startIndex..<questionIndex])
            rawQuery = String(target[target.index(after: questionIndex)...])
        }

        let path = try decodePath(rawPath)
        let pathSegments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        for segment in pathSegments where segment == "." || segment == ".." {
            throw APIError(status: 404, code: "not_found", message: "Request paths may not contain dot segments.")
        }
        let query = try parseQuery(rawQuery)

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { continue }
            guard let colonIndex = line.firstIndex(of: ":") else {
                throw APIError(status: 400, code: "bad_request", message: "Malformed HTTP header line.")
            }
            let name = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                throw APIError(status: 400, code: "bad_request", message: "HTTP header names may not be empty.")
            }
            let lowercased = name.lowercased()
            if let existing = headers[lowercased] {
                headers[lowercased] = existing + ", " + value
            } else {
                headers[lowercased] = value
            }
        }

        if let transferEncoding = headers["transfer-encoding"], !transferEncoding.isEmpty {
            throw APIError(status: 400, code: "unsupported_transfer_encoding", message: "Chunked or otherwise encoded request bodies are not supported.")
        }
        if let contentLength = headers["content-length"] {
            let values = contentLength.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard values.count <= 1, let first = values.first, let length = Int(first), length >= 0 else {
                throw APIError(status: 400, code: "invalid_content_length", message: "The Content-Length header must be a single non-negative integer.")
            }
            if length > maxBodyBytes {
                throw APIError(status: 400, code: "request_body_too_large", message: "Request bodies are limited to \(maxBodyBytes) bytes.")
            }
        }

        return HTTPRequest(
            method: method,
            target: target,
            version: version,
            path: path,
            pathSegments: pathSegments,
            query: query,
            headers: headers
        )
    }

    private static func decodePath(_ rawPath: String) throws -> String {
        let decoded = try PercentCoding.decode(rawPath, plusAsSpace: false, component: "path")
        guard decoded.hasPrefix("/") else {
            throw APIError(status: 400, code: "bad_request", message: "The request path must begin with \"/\".")
        }
        for scalar in decoded.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F {
                throw APIError(status: 400, code: "bad_request", message: "The request path contains control characters.")
            }
        }
        return decoded
    }

    private static func parseQuery(_ rawQuery: String?) throws -> [String: String] {
        guard let rawQuery, !rawQuery.isEmpty else { return [:] }
        var query: [String: String] = [:]
        for pair in rawQuery.split(separator: "&", omittingEmptySubsequences: true) {
            let stringPair = String(pair)
            let key: String
            let value: String
            if let equalsIndex = stringPair.firstIndex(of: "=") {
                key = String(stringPair[stringPair.startIndex..<equalsIndex])
                value = String(stringPair[stringPair.index(after: equalsIndex)...])
            } else {
                key = stringPair
                value = ""
            }
            let decodedKey = try PercentCoding.decode(key, plusAsSpace: true, component: "query parameter name")
            let decodedValue = try PercentCoding.decode(value, plusAsSpace: true, component: "query parameter value")
            guard !decodedKey.isEmpty else { continue }
            if query[decodedKey] == nil {
                query[decodedKey] = decodedValue
            }
        }
        return query
    }
}
