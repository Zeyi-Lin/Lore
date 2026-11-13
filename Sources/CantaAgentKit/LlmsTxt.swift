import Foundation

/// llms.txt-style discovery file served at <code>/llms.txt</code>.
enum LlmsTxt {
    static func text(baseURL: String) -> String {
        return """
# Canta Agent API

> Canta is a local macOS visual library of pinned UI screenshots. This loopback-only HTTP API exposes pin metadata, palettes, boards, tags, design notes, and original or thumbnail image streams so coding agents can reference real designs when replicating UI. The library is re-read from disk on every request.

Base URL: \(baseURL)
API version: v1
OpenAPI 3.1 spec: \(baseURL)/openapi.json
Human documentation: \(baseURL)/docs

## Docs

- [Canta Agent API documentation](\(baseURL)/docs): quickstart, endpoint reference, error codes, and paste-ready agent instructions.
- [OpenAPI 3.1 spec](\(baseURL)/openapi.json): machine-readable schemas for every endpoint.

## Endpoints

- [Health](\(baseURL)/health): liveness check with the bound port and current pin count. Alias: \(baseURL)/api/v1/health.
- [Library](\(baseURL)/api/v1/library): the complete enriched library with stats, boards, tags, and every pin.
- [Pins](\(baseURL)/api/v1/pins): filterable pin list. Query parameters: q, tag, board, favorite, kind, sort (recent|oldest|title), limit (1-200), offset.
- [Pin](\(baseURL)/api/v1/pins/{id}): one enriched pin by its UUID.
- [Pin image](\(baseURL)/api/v1/pins/{id}/image): raw image bytes. Use variant=original (default) or variant=thumb; thumb falls back to original.
- [Boards](\(baseURL)/api/v1/boards): board names with pin counts.
- [Tags](\(baseURL)/api/v1/tags): tag names with pin counts.
- [Stats](\(baseURL)/api/v1/stats): library counters for pins, boards, tags, favorites, and images.
- [Context](\(baseURL)/api/v1/context): markdown design context with absolute image URLs, ready to paste into an agent prompt. Optional board and tag filters.
- [llms.txt](\(baseURL)/llms.txt): this index.
- [Landing page](\(baseURL)/): links to all of the above.

## Example

List the five most recent pins and show their absolute image URLs:

    curl -s "\(baseURL)/api/v1/pins?limit=5&sort=recent" | jq '.pins[] | {title, board, imageURL}'

Fetch paste-ready design context for one board:

    curl -s "\(baseURL)/api/v1/context?board=Web%20dashboards"

Download the original image for a pin:

    curl -s -o reference.png "\(baseURL)/api/v1/pins/{id}/image?variant=original"

## Notes

- The listener binds only to 127.0.0.1. It is not reachable from other devices.
- All endpoints are read-only and support GET, HEAD, and OPTIONS (CORS preflight).
- Errors are JSON: {"error": {"code": "...", "message": "..."}} with HTTP 400, 404, 405, or 500.
- Image responses use the correct Content-Type for the stored file (for example image/png or image/jpeg).
- No authentication is required because the API is loopback-only.
"""
    }
}
