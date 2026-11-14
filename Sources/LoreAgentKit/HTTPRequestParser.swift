import Foundation

/// The parsed head of an HTTP/1.x request, before the body has been received.
struct HTTPRequestHead {
    let method: String
    let target: String
    let version: String
    let path: String
    let pathSegments: [String]
    let query: [String: String]
    let headers: [String: String]
    /// Validated Content-Length value, or 0 when the header is absent.
    let contentLength: Int

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    /// Normalized media type without parameters, e.g. "application/json".
    var contentType: String? {
        guard let raw = header("content-type") else { return nil }
        let parts = raw.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        let mediaType = parts.first.map(String.init) ?? raw
        let trimmed = mediaType.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }
}

enum HTTPHeadParseResult {
    case incomplete
    /// Parsed head plus the byte offset where the body begins in the buffer.
    case head(HTTPRequestHead, Int)
    case failure(APIError)
}

/// Parses request heads only. The connection layer decides, via a per-route
/// body policy, whether it needs to wait for the declared body.
enum HTTPRequestParser {
    /// Maximum size of the request head (request line + headers), in bytes.
    static let maxHeaderBytes = 32 * 1024
    /// Hard cap for any declared request body (20 MiB).
    static let maxBodyBytes = LoreAgentAPI.maxUploadBytes

    private static let crlfTerminator = Data("\r\n\r\n".utf8)
    private static let lfTerminator = Data("\n\n".utf8)

    static func parseHead(_ buffer: Data) -> HTTPHeadParseResult {
        guard let terminator = terminatorRange(in: buffer) else {
            if buffer.count > maxHeaderBytes {
                return .failure(APIError(status: 400, code: "request_header_too_large", message: "Request headers exceed the \(maxHeaderBytes) byte limit."))
            }
            return .incomplete
        }
        let headLength = buffer.distance(from: buffer.startIndex, to: terminator.lowerBound)
        if headLength > maxHeaderBytes {
            return .failure(APIError(status: 400, code: "request_header_too_large", message: "Request headers exceed the \(maxHeaderBytes) byte limit."))
        }
        let bodyStart = buffer.distance(from: buffer.startIndex, to: terminator.upperBound)
        let head = buffer[buffer.startIndex..<terminator.lowerBound]
        do {
            return .head(try parseHeadFields(Data(head)), bodyStart)
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

    private static func parseHeadFields(_ head: Data) throws -> HTTPRequestHead {
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

        var contentLength = 0
        if let rawContentLength = headers["content-length"] {
            let values = rawContentLength.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard values.count <= 1, let first = values.first, let length = Int(first), length >= 0 else {
                throw APIError(status: 400, code: "invalid_content_length", message: "The Content-Length header must be a single non-negative integer.")
            }
            if length > maxBodyBytes {
                throw APIError(status: 413, code: "request_body_too_large", message: "Request bodies are limited to \(maxBodyBytes) bytes (20 MiB).")
            }
            contentLength = length
        }

        return HTTPRequestHead(
            method: method,
            target: target,
            version: version,
            path: path,
            pathSegments: pathSegments,
            query: query,
            headers: headers,
            contentLength: contentLength
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
