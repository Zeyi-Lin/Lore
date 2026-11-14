import Foundation

/// Builds the OpenAPI 3.1 description of the Agent API. The document is
/// generated in memory so the server URL always reflects the bound port.
enum OpenAPISpec {
    static func data(port: UInt16) throws -> Data {
        let baseURL = "http://127.0.0.1:\(port)"
        let spec = build(baseURL: baseURL)
        return try JSONSerialization.data(withJSONObject: spec, options: [.sortedKeys, .prettyPrinted])
    }

    static func build(baseURL: String) -> [String: Any] {
        var paths: [String: Any] = [:]
        paths["/"] = pathItem(operation(
            token: "getLandingPage",
            summary: "Landing page",
            description: "Tiny HTML landing page linking to the documentation and machine-readable resources.",
            tags: ["Discovery"],
            responses: responses(primary: ["200": htmlResponse(description: "HTML landing page.")], errors: [:])
        ))
        paths["/docs"] = pathItem(operation(
            token: "getDocumentation",
            summary: "API documentation",
            description: "Polished, fully offline HTML documentation page with quickstart, endpoint reference, and agent instructions.",
            tags: ["Discovery"],
            responses: responses(primary: ["200": htmlResponse(description: "HTML documentation page.")], errors: [:])
        ))
        paths["/llms.txt"] = pathItem(operation(
            token: "getLlmsTxt",
            summary: "llms.txt index",
            description: "llms.txt-style plain-text index with absolute links to every endpoint.",
            tags: ["Discovery"],
            responses: responses(primary: ["200": textResponse(description: "llms.txt index.", mediaType: "text/plain")], errors: [:])
        ))
        paths["/openapi.json"] = pathItem(operation(
            token: "getOpenAPISpec",
            summary: "OpenAPI specification",
            description: "This OpenAPI 3.1 document, served as JSON.",
            tags: ["Discovery"],
            responses: responses(primary: ["200": jsonResponse(description: "OpenAPI 3.1 document.", schema: ["type": "object"])], errors: [:])
        ))
        paths["/health"] = pathItem(operation(
            token: "getHealth",
            summary: "Health check",
            description: "Reports liveness, the bound loopback port, the API version, and the number of pins currently in the library. Returns \"ok\" even if the library cannot be read (pinCount is 0 in that case); library endpoints report a 500 error instead.",
            tags: ["System"],
            responses: responses(primary: ["200": jsonResponse(description: "Server is accepting requests.", schema: ref("Health"))], errors: [500: "Unexpected server error."])
        ))
        paths["/api/v1/health"] = pathItem(operation(
            token: "getApiV1Health",
            summary: "Health check (versioned alias)",
            description: "Alias of /health. Reports liveness, the bound loopback port, the API version, and the current pin count.",
            tags: ["System"],
            responses: responses(primary: ["200": jsonResponse(description: "Server is accepting requests.", schema: ref("Health"))], errors: [500: "Unexpected server error."])
        ))
        paths["/api/v1/library"] = pathItem(operation(
            token: "getLibrary",
            summary: "Full enriched library",
            description: "Returns every pin as an EnrichedPin together with aggregate stats, boards, tags, colour-family facets, and tone facets. The library file is decoded fresh for every request.",
            tags: ["Library"],
            responses: responses(primary: ["200": jsonResponse(description: "The complete enriched library.", schema: ref("Library"))], errors: [500: "library_unavailable or library_corrupt when library.json is missing or invalid."])
        ))
        paths["/api/v1/pins"] = pathItem(operation(
            token: "listPins",
            summary: "List and filter pins",
            description: "Returns a filtered, sorted page of enriched pins. Search matches text fields and colour families; tag, board, colour, tone, favorite, and kind filter exact values.",
            tags: ["Library"],
            parameters: [
                queryParameter("q", description: "Case-insensitive text search across title, note, board, source label, kind, tags, colours, colour families, and tone.", schema: ["type": "string"], example: "dashboard"),
                queryParameter("tag", description: "Only pins carrying this tag (case-insensitive).", schema: ["type": "string"], example: "dark"),
                queryParameter("board", description: "Only pins on this board (case-insensitive). Board names may nest with a slash: Linear/Settings is a child of the Linear group in the app.", schema: ["type": "string"], example: "Web dashboards"),
                queryParameter("color", description: "Only pins whose detected colour families include this value. A pin may belong to several families; multicolor matches pins with three or more named hues. Common synonyms (cyan, purple, grey) are accepted.", schema: ["type": "string", "enum": LoreColorFamily.allCases.map(\.rawValue)], example: "blue"),
                queryParameter("tone", description: "Only pins with this tonal character.", schema: ["type": "string", "enum": LoreColorTone.allCases.map(\.rawValue)], example: "deep"),
                queryParameter("favorite", description: "Filter by favorite state.", schema: ["type": "boolean"]),
                queryParameter("kind", description: "Only pins of this kind.", schema: ["type": "string"], example: "screenshot"),
                queryParameter("sort", description: "Sort order. Defaults to recent.", schema: ["type": "string", "enum": ["recent", "oldest", "title"]], example: "recent"),
                queryParameter("limit", description: "Maximum number of pins to return (1-200). Defaults to 50.", schema: ["type": "integer", "minimum": 1, "maximum": 200], example: 20),
                queryParameter("offset", description: "Number of matching pins to skip. Defaults to 0.", schema: ["type": "integer", "minimum": 0], example: 0)
            ],
            responses: responses(primary: ["200": jsonResponse(description: "A page of enriched pins.", schema: ref("PinListResponse"))], errors: [400: "invalid_parameter when a query value (including color or tone) is malformed or out of range.", 500: "library_unavailable or library_corrupt when library.json cannot be read."])
        ), post: createPinOperation())
        paths["/api/v1/pins/{id}"] = pathItem(
            operation(
                token: "getPin",
                summary: "Single pin",
                description: "Returns one enriched pin by its stable UUID.",
                tags: ["Library"],
                parameters: [pathParameter("id", description: "Stable pin UUID.")],
                responses: responses(primary: ["200": jsonResponse(description: "The requested pin.", schema: ref("EnrichedPin"))], errors: [404: "pin_not_found when no pin has this id.", 500: "library_unavailable or library_corrupt when library.json cannot be read."])
            ),
            patch: updatePinOperation()
        )
        paths["/api/v1/pins/{id}/image"] = pathItem(operation(
            token: "getPinImage",
            summary: "Pin image bytes",
            description: "Streams the original image or its thumbnail as raw bytes with the correct image Content-Type. The thumbnail variant falls back to the original when the pin has no thumbnail or the thumbnail file is unavailable.",
            tags: ["Library"],
            parameters: [
                pathParameter("id", description: "Stable pin UUID."),
                queryParameter("variant", description: "Image variant. Defaults to original.", schema: ["type": "string", "enum": ["original", "thumb"]], example: "original")
            ],
            responses: responses(primary: ["200": imageResponse(description: "Raw image bytes.")], errors: [400: "invalid_parameter when variant is not original or thumb.", 404: "pin_not_found or image_not_found when the pin or image does not exist.", 500: "library_unavailable or library_corrupt when library.json cannot be read."])
        ))
        paths["/api/v1/boards"] = pathItem(operation(
            token: "getBoards",
            summary: "Boards with counts",
            description: "Board names and pin counts, sorted by count descending then name. Names may contain a slash to nest: Linear/Settings and Linear/Onboarding fold into the Linear group in the app sidebar. The API returns the flat full names.",
            tags: ["Library"],
            responses: responses(primary: ["200": jsonResponse(description: "Board names with pin counts.", schema: ref("BoardsResponse"))], errors: [500: "library_unavailable or library_corrupt when library.json cannot be read."])
        ))
        paths["/api/v1/tags"] = pathItem(operation(
            token: "getTags",
            summary: "Tags with counts",
            description: "Tag names and pin counts, sorted by count descending then name.",
            tags: ["Library"],
            responses: responses(primary: ["200": jsonResponse(description: "Tag names with pin counts.", schema: ref("TagsResponse"))], errors: [500: "library_unavailable or library_corrupt when library.json cannot be read."])
        ))
        paths["/api/v1/stats"] = pathItem(operation(
            token: "getStats",
            summary: "Library stats",
            description: "Counters for pins, boards, tags, favorites, and images.",
            tags: ["Library"],
            responses: responses(primary: ["200": jsonResponse(description: "Library counters.", schema: ref("Stats"))], errors: [500: "library_unavailable or library_corrupt when library.json cannot be read."])
        ))
        paths["/api/v1/context"] = pathItem(operation(
            token: "getContext",
            summary: "Agent design context",
            description: "Returns markdown design context containing curated pin metadata and absolute image URLs, ready to paste into a coding agent prompt. Use board, tag, color, and/or tone to narrow the selection. When nothing matches, the document lists the available boards, tags, and colour facets.",
            tags: ["Library"],
            parameters: [
                queryParameter("board", description: "Only include pins on this board (the full name, e.g. Linear/Settings).", schema: ["type": "string"], example: "Web dashboards"),
                queryParameter("tag", description: "Only include pins carrying this tag.", schema: ["type": "string"], example: "dashboard"),
                queryParameter("color", description: "Only include pins in this colour family (synonyms accepted; multicolor means three or more hues).", schema: ["type": "string", "enum": LoreColorFamily.allCases.map(\.rawValue)], example: "blue"),
                queryParameter("tone", description: "Only include pins with this tonal character.", schema: ["type": "string", "enum": LoreColorTone.allCases.map(\.rawValue)], example: "muted"),
                queryParameter("limit", description: "Maximum number of pins to include (1-100). Defaults to 20.", schema: ["type": "integer", "minimum": 1, "maximum": 100], example: 20)
            ],
            responses: responses(primary: ["200": textResponse(description: "Markdown design context.", mediaType: "text/markdown")], errors: [400: "invalid_parameter when limit, color, or tone is malformed or out of range.", 500: "library_unavailable or library_corrupt when library.json cannot be read."])
        ))

        let info: [String: Any] = [
            "title": "Lore Agent API",
            "version": LoreAgentAPI.version,
            "description": "Loopback-only HTTP API for the Lore visual design library. Lore serves pinned UI screenshots as enriched metadata plus raw image streams so coding agents can reference real designs. Pins carry an automatic colour taxonomy: multi-valued hue families plus a tonal character, filterable with color and tone. Read endpoints are read-only; POST /api/v1/pins adds pins and PATCH /api/v1/pins/{id} updates pin metadata (title, note, board, tags, source, favorite, kind) when metadata edits are enabled in Lore Settings. The library is re-read on every request. JSON errors always use the envelope {\"error\": {\"code\": string, \"message\": string}}."
        ]
        let server: [String: Any] = [
            "url": baseURL,
            "description": "Lore Agent API bound to the IPv4 loopback interface."
        ]
        let tags: [[String: Any]] = [
            ["name": "System", "description": "Liveness and version information."],
            ["name": "Library", "description": "Access to pins, boards, tags, stats, images, and agent context. POST adds pins; PATCH updates pin metadata when the owner has it enabled."],
            ["name": "Discovery", "description": "Human and machine-readable documentation."]
        ]
        let document: [String: Any] = [
            "openapi": "3.1.0",
            "jsonSchemaDialect": "https://json-schema.org/draft/2020-12/schema",
            "info": info,
            "servers": [server],
            "tags": tags,
            "paths": paths,
            "components": ["schemas": schemas()]
        ]
        return document
    }

    private static func createPinOperation() -> [String: Any] {
        let rawMetadata: [[String: Any]] = [
            queryParameter("title", description: "Pin title. Defaults to an \"Agent capture\" timestamp title.", schema: ["type": "string"], example: "Checkout flow"),
            queryParameter("note", description: "Design note stored with the pin.", schema: ["type": "string"]),
            queryParameter("board", description: "Board name. Use Product/Screen to nest under a product group in the app, for example Linear/Settings. Defaults to Unsorted.", schema: ["type": "string"], example: "Linear/Settings"),
            queryParameter("tags", description: "Comma-separated tags; trimmed, lower-cased, and de-duplicated.", schema: ["type": "string"], example: "mobile,checkout"),
            queryParameter("sourceURL", description: "Optional source URL for the inspiration.", schema: ["type": "string"]),
            queryParameter("sourceLabel", description: "Optional source label. Defaults to Agent API.", schema: ["type": "string"], example: "Claude Code"),
            queryParameter("kind", description: "Pin kind. Defaults to screenshot, or image for animated GIFs.", schema: ["type": "string"], example: "screenshot"),
            queryParameter("favorite", description: "Whether the new pin is a favorite.", schema: ["type": "boolean"])
        ]
        let requestBody: [String: Any] = [
            "required": true,
            "description": "Either an application/json document with imageBase64, or a raw image body with an image/* Content-Type. Raw metadata is supplied through the query parameters.",
            "content": [
                "application/json": ["schema": ref("CreatePinRequest")],
                "image/png": ["schema": ["type": "string", "format": "binary"]],
                "image/jpeg": ["schema": ["type": "string", "format": "binary"]],
                "image/webp": ["schema": ["type": "string", "format": "binary"]],
                "image/gif": ["schema": ["type": "string", "format": "binary"]],
                "image/heic": ["schema": ["type": "string", "format": "binary"]],
                "image/tiff": ["schema": ["type": "string", "format": "binary"]],
                "image/bmp": ["schema": ["type": "string", "format": "binary"]],
                "image/avif": ["schema": ["type": "string", "format": "binary"]]
            ]
        ]
        let operationResponses: [String: Any] = [
            "201": createdPinResponse(),
            "400": errorResponse(description: "invalid_json, missing_image, invalid_image_data, or invalid_metadata when the upload cannot be accepted."),
            "405": errorResponse(description: "method_not_allowed. The response includes an Allow header listing GET, HEAD, OPTIONS, and POST."),
            "413": errorResponse(description: "request_body_too_large when the declared or decoded payload exceeds 20 MiB."),
            "415": errorResponse(description: "unsupported_media_type when the Content-Type is neither application/json nor an image media type."),
            "500": errorResponse(description: "library_unavailable, library_corrupt, or storage_failure when the library cannot be written.")
        ]
        return operation(
            token: "createPin",
            summary: "Add a pin",
            description: "Validates an image, writes the original and a JPEG thumbnail (max 1200 px) into the Lore library, appends the pin to library.json atomically, and returns the enriched pin. Send application/json with imageBase64, or a raw image body with an image/* Content-Type and metadata in query parameters.",
            tags: ["Library"],
            parameters: rawMetadata,
            requestBody: requestBody,
            responses: operationResponses
        )
    }

    private static func createdPinResponse() -> [String: Any] {
        var response = jsonResponse(description: "The created pin, enriched with absolute image and thumbnail URLs.", schema: ref("EnrichedPin"))
        response["headers"] = [
            "Location": [
                "description": "Relative URL of the new pin, for example /api/v1/pins/<uuid>.",
                "schema": ["type": "string"]
            ]
        ]
        return response
    }

    // MARK: - Path helpers

    private static func operation(
        token: String,
        summary: String,
        description: String,
        tags: [String],
        parameters: [[String: Any]] = [],
        requestBody: [String: Any]? = nil,
        responses: [String: Any]
    ) -> [String: Any] {
        var result: [String: Any] = [
            "operationId": token,
            "summary": summary,
            "description": description,
            "tags": tags,
            "responses": responses
        ]
        if !parameters.isEmpty {
            result["parameters"] = parameters
        }
        if let requestBody {
            result["requestBody"] = requestBody
        }
        return result
    }

    private static func pathItem(
        _ get: [String: Any],
        post: [String: Any]? = nil,
        patch: [String: Any]? = nil
    ) -> [String: Any] {
        var item: [String: Any] = [
            "get": get,
            "head": headOperation(for: get)
        ]
        if let post {
            item["post"] = post
        }
        if let patch {
            item["patch"] = patch
        }
        return item
    }

    private static func headOperation(for get: [String: Any]) -> [String: Any] {
        let token = (get["operationId"] as? String ?? "operation") + "Head"
        let summary = (get["summary"] as? String ?? "Get") + " (HEAD)"
        var result: [String: Any] = [
            "operationId": token,
            "summary": summary,
            "description": "Identical status and headers to the GET operation, with no response body. Useful for checking content type and length without downloading an image.",
            "tags": get["tags"] ?? [],
            "responses": ["200": ["description": "Same headers as the corresponding GET response, with no body."]]
        ]
        if let parameters = get["parameters"] {
            result["parameters"] = parameters
        }
        return result
    }

    // MARK: - Response helpers

    private static func responses(primary: [String: Any], errors: [Int: String]) -> [String: Any] {
        var result = primary
        result["405"] = errorResponse(description: "method_not_allowed. The response includes an Allow header listing the methods supported by the path.")
        for (status, description) in errors {
            result[String(status)] = errorResponse(description: description)
        }
        return result
    }

    private static func jsonResponse(description: String, schema: [String: Any]) -> [String: Any] {
        return [
            "description": description,
            "content": ["application/json": ["schema": schema]]
        ]
    }

    private static func textResponse(description: String, mediaType: String) -> [String: Any] {
        return [
            "description": description,
            "content": [mediaType: ["schema": ["type": "string"]]]
        ]
    }

    private static func htmlResponse(description: String) -> [String: Any] {
        return textResponse(description: description, mediaType: "text/html")
    }

    private static func imageResponse(description: String) -> [String: Any] {
        return [
            "description": description,
            "content": [
                "image/*": ["schema": ["type": "string", "format": "binary"]],
                "application/octet-stream": ["schema": ["type": "string", "format": "binary"]]
            ]
        ]
    }

    private static func errorResponse(description: String) -> [String: Any] {
        return jsonResponse(description: description, schema: ref("Error"))
    }

    private static func ref(_ name: String) -> [String: Any] {
        return ["$ref": "#/components/schemas/\(name)"]
    }

    private static func queryParameter(_ name: String, description: String, schema: [String: Any], example: Any? = nil) -> [String: Any] {
        var parameter: [String: Any] = [
            "name": name,
            "in": "query",
            "required": false,
            "description": description,
            "schema": schema
        ]
        if let example {
            parameter["example"] = example
        }
        return parameter
    }

    private static func pathParameter(_ name: String, description: String) -> [String: Any] {
        return [
            "name": name,
            "in": "path",
            "required": true,
            "description": description,
            "schema": ["type": "string"]
        ]
    }

    // MARK: - Schemas

    private static func updatePinOperation() -> [String: Any] {
        operation(
            token: "updatePin",
            summary: "Update pin metadata",
            description: "Partially updates a pin's metadata. Only the fields named in the JSON body change; nullable fields accept null to clear them. Image assets, dimensions, colours, id, and createdAt are preserved. The app owner can disable metadata edits in Lore Settings; PATCH then answers 403 metadata_edits_disabled.",
            tags: ["Library"],
            parameters: [pathParameter("id", description: "Stable pin UUID.")],
            requestBody: [
                "required": true,
                "description": "JSON object with one or more metadata fields to update. Bodies are limited to 256 KiB.",
                "content": ["application/json": ["schema": ref("UpdatePinRequest")]]
            ],
            responses: responses(
                primary: ["200": jsonResponse(description: "The updated pin.", schema: ref("EnrichedPin"))],
                errors: [
                    400: "invalid_json, invalid_metadata, or unsupported_media_type when the payload is malformed, empty, contains unknown fields, or has a wrong value type.",
                    403: "metadata_edits_disabled when metadata edits are turned off in Lore Settings.",
                    404: "pin_not_found when no pin has this id.",
                    413: "request_body_too_large when the JSON body exceeds 256 KiB.",
                    415: "unsupported_media_type when the Content-Type is not application/json.",
                    500: "library_unavailable, library_corrupt, or storage_failure when the library cannot be read or written."
                ]
            )
        )
    }

    private static func schemas() -> [String: Any] {
        let nullableString: [String: Any] = ["type": ["string", "null"]]
        let stringArray: [String: Any] = ["type": "array", "items": ["type": "string"]]
        let integer: [String: Any] = ["type": "integer"]
        let colorFamily: [String: Any] = [
            "type": "string",
            "enum": LoreColorFamily.allCases.filter { $0 != .multicolor }.map(\.rawValue),
            "description": "Hue family."
        ]
        let colorFamilies: [String: Any] = [
            "type": "array",
            "items": colorFamily,
            "description": "Detected hue families ordered by coverage. Multi-membership: a teal-and-yellow pin lists both."
        ]
        let colorTone: [String: Any] = [
            "type": "string",
            "enum": LoreColorTone.allCases.map(\.rawValue),
            "description": "Tonal character inferred from lightness and accent chroma."
        ]

        let errorDetail: [String: Any] = [
            "type": "object",
            "description": "Machine-readable error code plus a human-readable message.",
            "properties": [
                "code": ["type": "string", "description": "Stable error code, for example not_found or invalid_parameter."],
                "message": ["type": "string", "description": "Human-readable explanation."]
            ],
            "required": ["code", "message"]
        ]
        let errorEnvelope: [String: Any] = [
            "type": "object",
            "description": "Every non-2xx response uses this envelope.",
            "properties": ["error": ref("ErrorDetail")],
            "required": ["error"]
        ]
        let health: [String: Any] = [
            "type": "object",
            "description": "Liveness and library summary.",
            "properties": [
                "status": ["type": "string", "enum": ["ok"]],
                "app": ["type": "string", "enum": ["Lore"]],
                "api": ["type": "string", "enum": ["v1"]],
                "version": ["type": "string", "description": "Agent API implementation version."],
                "pinCount": ["type": "integer", "minimum": 0, "description": "Pins currently in the library, or 0 when library.json cannot be read."],
                "port": ["type": "integer", "minimum": 1, "maximum": 65535, "description": "Actual bound loopback port."]
            ],
            "required": ["status", "app", "api", "version", "pinCount", "port"]
        ]
        let stats: [String: Any] = [
            "type": "object",
            "description": "Aggregate library counters.",
            "properties": [
                "pins": ["type": "integer", "minimum": 0],
                "boards": ["type": "integer", "minimum": 0],
                "tags": ["type": "integer", "minimum": 0],
                "favorites": ["type": "integer", "minimum": 0],
                "images": ["type": "integer", "minimum": 0]
            ],
            "required": ["pins", "boards", "tags", "favorites", "images"]
        ]
        let namedCount: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "count": ["type": "integer", "minimum": 0]
            ],
            "required": ["name", "count"]
        ]
        let enrichedPin: [String: Any] = [
            "type": "object",
            "description": "A persisted pin with absolute image URLs resolved against the bound port.",
            "properties": [
                "id": ["type": "string", "description": "Stable pin UUID."],
                "title": ["type": "string"],
                "note": ["type": "string"],
                "image": ["type": "string", "description": "Library-relative original image path."],
                "thumbnail": nullableString,
                "width": integer,
                "height": integer,
                "fileSize": integer,
                "createdAt": ["type": "string", "format": "date-time"],
                "updatedAt": ["type": "string", "format": "date-time"],
                "tags": stringArray,
                "board": ["type": "string", "description": "Board the pin belongs to. A slash nests the board under a group in the app, e.g. Linear/Settings."],
                "sourceURL": nullableString,
                "sourceLabel": nullableString,
                "colors": stringArray,
                "colorFamily": colorFamily,
                "colorFamilies": colorFamilies,
                "colorTone": colorTone,
                "animated": ["type": "boolean", "description": "True when the original image has multiple frames (for example a GIF)."],
                "frameCount": ["type": "integer", "minimum": 1, "description": "Frame count of the original image; 1 for still images."],
                "favorite": ["type": "boolean"],
                "kind": ["type": "string"],
                "imageURL": ["type": ["string", "null"], "description": "Absolute loopback URL for the original image."],
                "thumbnailURL": ["type": ["string", "null"], "description": "Absolute loopback URL for the thumbnail."]
            ],
            "required": [
                "id", "title", "note", "image", "thumbnail", "width", "height", "fileSize",
                "createdAt", "updatedAt", "tags", "board", "sourceURL", "sourceLabel",
                "colors", "colorFamily", "colorFamilies", "colorTone", "animated", "frameCount",
                "favorite", "kind", "imageURL", "thumbnailURL"
            ]
        ]
        let createPinRequest: [String: Any] = [
            "type": "object",
            "description": "JSON form for POST /api/v1/pins. imageBase64 is required; a data URI prefix (data:image/png;base64,...) is accepted.",
            "properties": [
                "imageBase64": ["type": "string", "description": "Base64-encoded image bytes. Data URI prefixes are accepted."],
                "mimeType": ["type": "string", "description": "Optional declared media type, for example image/png."],
                "title": ["type": "string"],
                "note": ["type": "string"],
                "board": ["type": "string", "description": "Board the pin belongs to. Prefix the product name and nest with a slash, e.g. Linear/Settings."],
                "tags": ["type": "array", "items": ["type": "string"]],
                "sourceURL": nullableString,
                "sourceLabel": nullableString,
                "kind": ["type": "string"],
                "favorite": ["type": "boolean"]
            ],
            "required": ["imageBase64"]
        ]
        let nullableMetadataString: [String: Any] = ["type": ["string", "null"]]
        let updatePinRequest: [String: Any] = [
            "type": "object",
            "description": "Partial pin metadata update. Include at least one field; nullable fields accept null to clear them.",
            "additionalProperties": false,
            "properties": [
                "title": ["type": "string", "description": "Non-empty pin title."],
                "note": nullableMetadataString,
                "board": ["type": ["string", "null"], "description": "Full board name. Null or empty moves the pin to Unsorted. A slash nests the board under a group in the app."],
                "tags": ["type": ["array", "null"], "items": ["type": "string"], "description": "Replaces all tags; trimmed, lower-cased, and de-duplicated."],
                "sourceURL": nullableMetadataString,
                "sourceLabel": nullableMetadataString,
                "favorite": ["type": "boolean"],
                "kind": ["type": "string", "enum": ["screenshot", "image"]]
            ]
        ]
        let pinList: [String: Any] = [
            "type": "object",
            "properties": [
                "count": ["type": "integer", "minimum": 0, "description": "Pins returned in this page."],
                "total": ["type": "integer", "minimum": 0, "description": "Pins matching the filters before pagination."],
                "offset": ["type": "integer", "minimum": 0],
                "limit": ["type": "integer", "minimum": 1],
                "pins": ["type": "array", "items": ref("EnrichedPin")]
            ],
            "required": ["count", "total", "offset", "limit", "pins"]
        ]
        let library: [String: Any] = [
            "type": "object",
            "properties": [
                "app": ["type": "string", "enum": ["Lore"]],
                "version": ["type": "string"],
                "generatedAt": ["type": "string", "format": "date-time"],
                "stats": ref("Stats"),
                "boards": ["type": "array", "items": ref("NamedCount")],
                "tags": ["type": "array", "items": ref("NamedCount")],
                "colorFamilies": ["type": "array", "items": ref("NamedCount"), "description": "Hue-family facets with multi-membership counts (includes multicolor)."],
                "colorTones": ["type": "array", "items": ref("NamedCount")],
                "pins": ["type": "array", "items": ref("EnrichedPin")]
            ],
            "required": ["app", "version", "generatedAt", "stats", "boards", "tags", "colorFamilies", "colorTones", "pins"]
        ]
        let boards: [String: Any] = [
            "type": "object",
            "properties": ["boards": ["type": "array", "items": ref("NamedCount")]],
            "required": ["boards"]
        ]
        let tags: [String: Any] = [
            "type": "object",
            "properties": ["tags": ["type": "array", "items": ref("NamedCount")]],
            "required": ["tags"]
        ]

        return [
            "Error": errorEnvelope,
            "ErrorDetail": errorDetail,
            "Health": health,
            "Stats": stats,
            "NamedCount": namedCount,
            "EnrichedPin": enrichedPin,
            "CreatePinRequest": createPinRequest,
            "UpdatePinRequest": updatePinRequest,
            "PinListResponse": pinList,
            "Library": library,
            "BoardsResponse": boards,
            "TagsResponse": tags
        ]
    }
}
