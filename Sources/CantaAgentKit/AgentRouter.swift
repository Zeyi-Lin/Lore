import Foundation

/// Routes loopback HTTP requests to the Canta library endpoints, JSON
/// surfaces, and offline documentation pages.
struct AgentRouter {
    let store: LibraryStore
    let ingestor: LibraryIngestor
    let portProvider: () -> UInt16

    // MARK: - Routing

    private enum Route {
        case landing
        case health
        case docs
        case openapi
        case llms
        case library
        case pins
        case pin(id: String)
        case pinImage(id: String)
        case boards
        case tags
        case stats
        case context
    }

    func handle(_ request: HTTPRequest) -> HTTPResponse {
        do {
            let route = try route(for: request)
            let allow = allowedMethods(for: route)
            let allowHeader = allow.joined(separator: ", ")
            if request.method == "OPTIONS" {
                return HTTPResponse.empty(status: 204, headers: ["Allow": allowHeader])
            }
            guard allow.contains(request.method) else {
                return HTTPResponse.error(
                    status: 405,
                    code: "method_not_allowed",
                    message: "\(request.method) is not supported by this endpoint. Allowed methods: \(allowHeader).",
                    extraHeaders: ["Allow": allowHeader]
                )
            }
            return try respond(to: route, request: request)
        } catch let error as APIError {
            var headers: [String: String] = [:]
            if error.status == 405 { headers["Allow"] = "GET, HEAD, OPTIONS" }
            return HTTPResponse.error(status: error.status, code: error.code, message: error.message, extraHeaders: headers)
        } catch let error as PinIngestError {
            return Self.response(for: error)
        } catch let error as LibraryStoreError {
            switch error {
            case .unavailable(let message):
                return HTTPResponse.error(status: 500, code: "library_unavailable", message: message)
            case .corrupt(let message):
                return HTTPResponse.error(status: 500, code: "library_corrupt", message: message)
            case .imageNotFound, .forbidden:
                return HTTPResponse.error(status: 404, code: "image_not_found", message: "The requested image is not available.")
            }
        } catch {
            return HTTPResponse.error(status: 500, code: "internal_error", message: "The Agent API could not complete this request.")
        }
    }

    /// Methods accepted by each route. The pins collection is the only route
    /// with a write method.
    private func allowedMethods(for route: Route) -> [String] {
        switch route {
        case .pins:
            return ["GET", "HEAD", "OPTIONS", "POST"]
        default:
            return ["GET", "HEAD", "OPTIONS"]
        }
    }

    /// Body buffering policy used by the HTTP connection. Only pin creation
    /// waits for a body; read endpoints answer from the head immediately.
    func maxBodyBytes(for head: HTTPRequestHead) -> Int {
        guard head.method == "POST", head.pathSegments == ["api", "v1", "pins"] else {
            return 0
        }
        return CantaAgentAPI.maxUploadBytes
    }

    private static func response(for error: PinIngestError) -> HTTPResponse {
        switch error {
        case .malformedJSON(let message):
            return .error(status: 400, code: "invalid_json", message: message)
        case .missingImage(let message):
            return .error(status: 400, code: "missing_image", message: message)
        case .invalidImageData(let message):
            return .error(status: 400, code: "invalid_image_data", message: message)
        case .invalidMetadata(let message):
            return .error(status: 400, code: "invalid_metadata", message: message)
        case .unsupportedMediaType(let message):
            return .error(status: 415, code: "unsupported_media_type", message: message)
        case .storageFailure(let message):
            return .error(status: 500, code: "storage_failure", message: message)
        }
    }

    private func route(for request: HTTPRequest) throws -> Route {
        let segments = request.pathSegments
        if segments.isEmpty { return .landing }
        if segments == ["health"] || segments == ["api", "v1", "health"] { return .health }
        if segments == ["docs"] { return .docs }
        if segments == ["openapi.json"] { return .openapi }
        if segments == ["llms.txt"] { return .llms }

        guard segments.count >= 3, segments[0] == "api", segments[1] == "v1" else {
            throw notFound(request)
        }
        switch segments[2] {
        case "library" where segments.count == 3:
            return .library
        case "pins":
            switch segments.count {
            case 3:
                return .pins
            case 4:
                return .pin(id: segments[3])
            case 5 where segments[4] == "image":
                return .pinImage(id: segments[3])
            default:
                throw notFound(request)
            }
        case "boards" where segments.count == 3:
            return .boards
        case "tags" where segments.count == 3:
            return .tags
        case "stats" where segments.count == 3:
            return .stats
        case "context" where segments.count == 3:
            return .context
        default:
            throw notFound(request)
        }
    }

    private func notFound(_ request: HTTPRequest) -> APIError {
        APIError(status: 404, code: "not_found", message: "No Canta Agent API route matches \(request.method) \(request.path).")
    }

    // MARK: - Responses

    private func respond(to route: Route, request: HTTPRequest) throws -> HTTPResponse {
        let port = portProvider()
        let baseURL = "http://127.0.0.1:\(port)"
        switch route {
        case .landing:
            return .html(LandingPage.html(baseURL: baseURL))

        case .health:
            let pinCount = (try? store.loadLibrary().pins.count) ?? 0
            return .json(HealthResponse(
                status: "ok",
                app: CantaAgentAPI.appName,
                api: CantaAgentAPI.apiVersion,
                version: CantaAgentAPI.version,
                pinCount: pinCount,
                port: Int(port)
            ))

        case .docs:
            return .html(DocsPage.html(baseURL: baseURL))

        case .openapi:
            let data = try OpenAPISpec.data(port: port)
            return .bytes(data, contentType: "application/json; charset=utf-8")

        case .llms:
            return .text(LlmsTxt.text(baseURL: baseURL), contentType: "text/plain; charset=utf-8")

        case .library:
            let library = try store.loadLibrary()
            return .json(LibraryResponse(
                app: CantaAgentAPI.appName,
                version: CantaAgentAPI.version,
                generatedAt: Timestamp.nowString(),
                stats: LibraryStats(pins: library.pins),
                boards: LibraryStore.boardCounts(for: library.pins),
                tags: LibraryStore.tagCounts(for: library.pins),
                pins: library.pins.map { $0.enriched(baseURL: baseURL) }
            ))

        case .pins:
            if request.method == "POST" {
                return try createPin(from: request, baseURL: baseURL)
            }
            let query = try pinQuery(from: request)
            let filtered = LibraryStore.searchPins(in: try store.loadLibrary().pins, matching: query)
            let total = filtered.count
            let start = min(query.offset, total)
            let end = min(start + query.limit, total)
            let page = start < end ? Array(filtered[start..<end]) : []
            return .json(PinListResponse(
                count: page.count,
                total: total,
                offset: query.offset,
                limit: query.limit,
                pins: page.map { $0.enriched(baseURL: baseURL) }
            ))

        case .pin(let id):
            let pins = try store.loadLibrary().pins
            guard let pin = pins.first(where: { $0.id == id }) else {
                throw APIError(status: 404, code: "pin_not_found", message: "No pin with id \"\(id)\" exists in the Canta library.")
            }
            return .json(pin.enriched(baseURL: baseURL))

        case .pinImage(let id):
            let variantName = (stringParameter(request, "variant") ?? "original").lowercased()
            guard let variant = ImageVariant(rawValue: variantName) else {
                throw APIError(status: 400, code: "invalid_parameter", message: "\"variant\" must be one of: original, thumb.")
            }
            let pins = try store.loadLibrary().pins
            guard let pin = pins.first(where: { $0.id == id }) else {
                throw APIError(status: 404, code: "pin_not_found", message: "No pin with id \"\(id)\" exists in the Canta library.")
            }
            let image = try store.imageData(for: pin, variant: variant)
            var headers: [String: String] = [:]
            if image.contentType == "image/svg+xml" {
                headers["Content-Security-Policy"] = "default-src 'none'; style-src 'unsafe-inline'; sandbox"
            }
            return .bytes(image.data, contentType: image.contentType, extraHeaders: headers)

        case .boards:
            return .json(BoardsResponse(boards: try store.boardCounts()))

        case .tags:
            return .json(TagsResponse(tags: try store.tagCounts()))

        case .stats:
            return .json(try store.stats())

        case .context:
            let board = stringParameter(request, "board")
            let tag = stringParameter(request, "tag")
            let limit = try integerParameter(request, name: "limit", range: 1...100, defaultValue: 20)
            let library = try store.loadLibrary()
            var query = PinQuery()
            query.board = board
            query.tag = tag
            query.sort = .recent
            let matches = LibraryStore.searchPins(in: library.pins, matching: query)
            let selected = Array(matches.prefix(limit))
            let markdown = ContextMarkdown.build(
                allPins: library.pins,
                selected: selected,
                totalMatches: matches.count,
                baseURL: baseURL,
                board: board,
                tag: tag
            )
            return .markdown(markdown)
        }
    }

    // MARK: - Pin ingestion

    private func createPin(from request: HTTPRequest, baseURL: String) throws -> HTTPResponse {
        let newPin = try parseNewPinRequest(from: request)
        let pin = try ingestor.createPin(newPin)
        let location = "/api/v1/pins/" + PercentCoding.encodePathSegment(pin.id)
        return .json(pin.enriched(baseURL: baseURL), status: 201, extraHeaders: ["Location": location])
    }

    private func parseNewPinRequest(from request: HTTPRequest) throws -> NewPinRequest {
        let contentType = request.contentType
        if contentType == "application/json" {
            return try parseJSONPinRequest(from: request)
        }
        if let contentType, contentType.hasPrefix("image/") {
            return try parseRawPinRequest(from: request, declaredMimeType: contentType)
        }
        if contentType == nil || contentType == "application/octet-stream" {
            return try parseRawPinRequest(from: request, declaredMimeType: nil)
        }
        throw PinIngestError.unsupportedMediaType(
            "Content-Type \"\(contentType ?? "")\" is not supported. Send application/json with imageBase64, or a raw image body with an image/* Content-Type."
        )
    }

    private func parseJSONPinRequest(from request: HTTPRequest) throws -> NewPinRequest {
        guard !request.body.isEmpty else {
            throw PinIngestError.missingImage("The JSON request body is empty; imageBase64 is required.")
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: request.body)
        } catch {
            throw PinIngestError.malformedJSON("The request body is not valid JSON.")
        }
        guard let dictionary = object as? [String: Any] else {
            throw PinIngestError.malformedJSON("The JSON request body must be an object.")
        }
        guard let imageBase64 = dictionary["imageBase64"] as? String else {
            throw PinIngestError.missingImage("The JSON request body must contain an imageBase64 string.")
        }
        var declaredMimeType = try optionalString(dictionary["mimeType"], field: "mimeType")
        var base64 = imageBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        if base64.lowercased().hasPrefix("data:") {
            guard let commaIndex = base64.firstIndex(of: ",") else {
                throw PinIngestError.invalidImageData("The imageBase64 data URI is malformed.")
            }
            let header = String(base64[base64.startIndex..<commaIndex]).lowercased()
            base64 = String(base64[base64.index(after: commaIndex)...])
            if declaredMimeType == nil, header.hasSuffix(";base64") {
                let mimeStart = header.index(header.startIndex, offsetBy: 5)
                let mimeEnd = header.index(header.endIndex, offsetBy: -7)
                let mime = String(header[mimeStart..<mimeEnd]).trimmingCharacters(in: .whitespaces)
                if !mime.isEmpty { declaredMimeType = mime }
            }
        }
        if let declaredMimeType, !declaredMimeType.lowercased().hasPrefix("image/") {
            throw PinIngestError.unsupportedMediaType("mimeType \"\(declaredMimeType)\" is not an image media type.")
        }
        guard let data = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters]), !data.isEmpty else {
            throw PinIngestError.invalidImageData("imageBase64 did not decode to any image bytes.")
        }
        return NewPinRequest(
            imageData: data,
            declaredMimeType: declaredMimeType,
            title: try optionalString(dictionary["title"], field: "title"),
            note: try optionalString(dictionary["note"], field: "note"),
            board: try optionalString(dictionary["board"], field: "board"),
            tags: try stringArray(dictionary["tags"], field: "tags"),
            sourceURL: try optionalString(dictionary["sourceURL"], field: "sourceURL"),
            sourceLabel: try optionalString(dictionary["sourceLabel"], field: "sourceLabel"),
            kind: try optionalString(dictionary["kind"], field: "kind"),
            favorite: try optionalBool(dictionary["favorite"], field: "favorite")
        )
    }

    private func parseRawPinRequest(from request: HTTPRequest, declaredMimeType: String?) throws -> NewPinRequest {
        guard !request.body.isEmpty else {
            throw PinIngestError.missingImage("The raw image request body is empty.")
        }
        let tags = (stringParameter(request, "tags") ?? "").split(separator: ",").map(String.init)
        return NewPinRequest(
            imageData: request.body,
            declaredMimeType: declaredMimeType,
            title: stringParameter(request, "title"),
            note: stringParameter(request, "note"),
            board: stringParameter(request, "board"),
            tags: tags,
            sourceURL: stringParameter(request, "sourceURL"),
            sourceLabel: stringParameter(request, "sourceLabel"),
            kind: stringParameter(request, "kind"),
            favorite: try booleanParameter(request, name: "favorite")
        )
    }

    private func optionalString(_ value: Any?, field: String) throws -> String? {
        guard let value else { return nil }
        guard let string = value as? String else {
            throw PinIngestError.invalidMetadata("\"\(field)\" must be a string.")
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func stringArray(_ value: Any?, field: String) throws -> [String] {
        guard let value else { return [] }
        guard let array = value as? [Any] else {
            throw PinIngestError.invalidMetadata("\"\(field)\" must be an array of strings.")
        }
        var result: [String] = []
        result.reserveCapacity(array.count)
        for item in array {
            guard let string = item as? String else {
                throw PinIngestError.invalidMetadata("\"\(field)\" must contain only strings.")
            }
            result.append(string)
        }
        return result
    }

    private func optionalBool(_ value: Any?, field: String) throws -> Bool? {
        guard let value else { return nil }
        if let number = value as? NSNumber {
            let intValue = number.intValue
            if intValue == 0 || intValue == 1 { return intValue == 1 }
        }
        if let bool = value as? Bool { return bool }
        throw PinIngestError.invalidMetadata("\"\(field)\" must be a boolean.")
    }

    // MARK: - Query parsing

    private func stringParameter(_ request: HTTPRequest, _ name: String) -> String? {
        guard let raw = request.queryValue(name) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func pinQuery(from request: HTTPRequest) throws -> PinQuery {
        var query = PinQuery()
        query.search = stringParameter(request, "q")
        query.tag = stringParameter(request, "tag")
        query.board = stringParameter(request, "board")
        query.kind = stringParameter(request, "kind")
        query.favorite = try booleanParameter(request, name: "favorite")
        if let rawSort = stringParameter(request, "sort") {
            guard let sort = PinSort(rawValue: rawSort.lowercased()) else {
                throw APIError(status: 400, code: "invalid_parameter", message: "\"sort\" must be one of: recent, oldest, title.")
            }
            query.sort = sort
        }
        if stringParameter(request, "limit") != nil {
            query.limit = try integerParameter(request, name: "limit", range: 1...200, defaultValue: 50)
        }
        if stringParameter(request, "offset") != nil {
            query.offset = try nonNegativeIntegerParameter(request, name: "offset")
        }
        return query
    }

    private func booleanParameter(_ request: HTTPRequest, name: String) throws -> Bool? {
        guard let raw = stringParameter(request, name) else { return nil }
        switch raw.lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default:
            throw APIError(status: 400, code: "invalid_parameter", message: "\"\(name)\" must be true or false.")
        }
    }

    private func integerParameter(_ request: HTTPRequest, name: String, range: ClosedRange<Int>, defaultValue: Int) throws -> Int {
        guard let raw = stringParameter(request, name) else { return defaultValue }
        guard let value = Int(raw) else {
            throw APIError(status: 400, code: "invalid_parameter", message: "\"\(name)\" must be an integer.")
        }
        guard range.contains(value) else {
            throw APIError(status: 400, code: "invalid_parameter", message: "\"\(name)\" must be between \(range.lowerBound) and \(range.upperBound).")
        }
        return value
    }

    private func nonNegativeIntegerParameter(_ request: HTTPRequest, name: String) throws -> Int {
        guard let raw = stringParameter(request, name) else { return 0 }
        guard let value = Int(raw), value >= 0 else {
            throw APIError(status: 400, code: "invalid_parameter", message: "\"\(name)\" must be a non-negative integer.")
        }
        return value
    }
}

// MARK: - Markdown context document

enum ContextMarkdown {
    static func build(
        allPins: [CantaPinRecord],
        selected: [CantaPinRecord],
        totalMatches: Int,
        baseURL: String,
        board: String?,
        tag: String?
    ) -> String {
        var lines: [String] = []
        lines.append("# Canta design context")
        lines.append("")
        lines.append("> Local design reference from Canta, a visual library of UI screenshots. Use these pins to match layout, typography, colour, and component patterns when replicating or adapting UI work. Every image URL below is served by Canta on this machine.")
        lines.append("")
        lines.append("- Base URL: \(baseURL)")
        lines.append("- Library: \(allPins.count) pins · \(LibraryStore.boardCounts(for: allPins).count) boards · \(LibraryStore.tagCounts(for: allPins).count) tags")
        var filters: [String] = []
        if let board { filters.append("board = \"\(escapeInline(board))\"") }
        if let tag { filters.append("tag = \"\(escapeInline(tag))\"") }
        if !filters.isEmpty {
            lines.append("- Filter: " + filters.joined(separator: ", "))
        }
        lines.append("- Matches: \(totalMatches) pins" + (selected.count < totalMatches ? " (showing the \(selected.count) most recent)" : ""))
        lines.append("- Generated: \(Timestamp.nowString())")
        lines.append("- Full machine-readable library: \(baseURL)/api/v1/library")
        lines.append("")

        if selected.isEmpty {
            lines.append("No pins matched this filter.")
            lines.append("")
            lines.append("Available boards: " + LibraryStore.boardCounts(for: allPins).map { "\($0.name) (\($0.count))" }.joined(separator: ", "))
            lines.append("")
            lines.append("Available tags: " + LibraryStore.tagCounts(for: allPins).prefix(30).map { $0.name }.joined(separator: ", "))
            lines.append("")
            lines.append("Try again without filters: \(baseURL)/api/v1/context")
            return lines.joined(separator: "\n")
        }

        for (index, pin) in selected.enumerated() {
            lines.append("## \(index + 1). \(escapeInline(pin.title.isEmpty ? "Untitled pin" : pin.title))")
            lines.append("")
            lines.append("- **Pin ID:** `\(pin.id)`")
            if !pin.board.isEmpty { lines.append("- **Board:** \(escapeInline(pin.board))") }
            if !pin.tags.isEmpty { lines.append("- **Tags:** " + pin.tags.map { "`\(escapeCode($0))`" }.joined(separator: ", ")) }
            if pin.width > 0 && pin.height > 0 {
                var dimensions = "\(pin.width) × \(pin.height)"
                if pin.fileSize > 0 { dimensions += " · \(humanFileSize(pin.fileSize))" }
                lines.append("- **Dimensions:** \(dimensions)")
            }
            if !pin.colors.isEmpty { lines.append("- **Palette:** " + pin.colors.map { "`\(escapeCode($0))`" }.joined(separator: ", ")) }
            if let sourceURL = pin.sourceURL, !sourceURL.isEmpty {
                let label = pin.sourceLabel.map { escapeInline($0) + " — " } ?? ""
                lines.append("- **Source:** \(label)<\(safeURL(sourceURL))>")
            } else if let sourceLabel = pin.sourceLabel, !sourceLabel.isEmpty {
                lines.append("- **Source:** \(escapeInline(sourceLabel))")
            }
            if let imageURL = pin.originalImageURL(baseURL: baseURL) {
                lines.append("- **Image:** <\(imageURL)>")
            }
            if let thumbnailURL = pin.thumbnailImageURL(baseURL: baseURL) {
                lines.append("- **Thumbnail:** <\(thumbnailURL)>")
            }
            if !pin.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("- **Design note:** \(escapeInline(pin.note))")
            }
            lines.append("")
        }

        if totalMatches > selected.count {
            lines.append("---")
            lines.append("")
            lines.append("Showing \(selected.count) of \(totalMatches) matching pins. Fetch all of them as JSON: \(baseURL)/api/v1/pins?limit=200" + contextQuerySuffix(board: board, tag: tag))
            lines.append("")
        }
        lines.append("## Next steps")
        lines.append("")
        lines.append("- Open the full library JSON: \(baseURL)/api/v1/library")
        lines.append("- Browse paginated pins: \(baseURL)/api/v1/pins?limit=20&sort=recent")
        lines.append("- Download a reference image with curl: `curl -o reference.png \"\(baseURL)/api/v1/pins/<pin-id>/image?variant=original\"`")
        lines.append("- Read the API docs: \(baseURL)/docs")
        return lines.joined(separator: "\n")
    }

    private static func contextQuerySuffix(board: String?, tag: String?) -> String {
        var parts: [String] = []
        if let board, !board.isEmpty {
            parts.append("board=" + (board.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? board))
        }
        if let tag, !tag.isEmpty {
            parts.append("tag=" + (tag.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tag))
        }
        return parts.isEmpty ? "" : "&" + parts.joined(separator: "&")
    }

    private static func humanFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB]
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private static func escapeInline(_ value: String) -> String {
        let collapsed = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return collapsed
    }

    private static func escapeCode(_ value: String) -> String {
        escapeInline(value).replacingOccurrences(of: "`", with: "'")
    }

    private static func safeURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
            .replacingOccurrences(of: "<", with: "%3C")
            .replacingOccurrences(of: ">", with: "%3E")
            .replacingOccurrences(of: " ", with: "%20")
    }
}
