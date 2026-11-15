import Foundation

/// llms.txt-style discovery file served at <code>/llms.txt</code>.
enum LlmsTxt {
    static func text(baseURL: String) -> String {
        return """
# Lore Agent API

> Lore is a local macOS visual library of pinned UI screenshots. This loopback-only HTTP API exposes pin metadata, palettes, boards, tags, auto-detected colour families and tones, GIF/animation and SVG/vector metadata, design notes, and original or thumbnail image streams so coding agents can reference real designs when replicating UI. Agents can also add new pins with POST /api/v1/pins using a JSON base64 payload or a raw image body. The library is re-read from disk on every request.

Base URL: \(baseURL)
API version: v1
OpenAPI 3.1 spec: \(baseURL)/openapi.json
Human documentation: \(baseURL)/docs

## Docs

- [Lore Agent API documentation](\(baseURL)/docs): quickstart, endpoint reference, error codes, image ingest examples, and paste-ready agent instructions.
- [OpenAPI 3.1 spec](\(baseURL)/openapi.json): machine-readable schemas for every endpoint.

## Endpoints

- [Health](\(baseURL)/health): liveness check with the bound port and current pin count. Alias: \(baseURL)/api/v1/health.
- [Library](\(baseURL)/api/v1/library): the complete enriched library with stats, boards, tags, colour-family facets, tone facets, and every pin.
- [Pins](\(baseURL)/api/v1/pins): filterable pin list. Query parameters: q, tag, board, color (neutral|red|orange|yellow|green|teal|blue|violet|pink|brown|multicolor), tone (light|pastel|vivid|muted|deep), favorite, kind, sort (recent|oldest|title), limit (1-200), offset.
- [Create pin](\(baseURL)/api/v1/pins): POST a new pin. Send application/json with imageBase64 (data URI prefixes accepted) and optional metadata, or send a raw image body with Content-Type image/* and metadata as query parameters. Animated GIFs keep their frames; SVG bodies are stored as vectors and served back as image/svg+xml. The response includes `animated` and `frameCount`. Bodies are limited to 20 MiB; responses are 201 with an EnrichedPin and a Location header. Board names are plain strings: use a Product/Screen name — e.g. board=Linear/Settings — so the pin nests under "Linear" in the app sidebar.
- [Update pin](\(baseURL)/api/v1/pins/{id}): PATCH pin metadata. Send application/json with one or more of title, note, board, tags, sourceURL, sourceLabel, favorite, kind; null clears a nullable field. Bodies are limited to 256 KiB and the response is the updated EnrichedPin. The library owner can disable PATCH in Lore Settings; it then returns 403 metadata_edits_disabled.
- [Pin](\(baseURL)/api/v1/pins/{id}): one enriched pin by its UUID.
- [Pin image](\(baseURL)/api/v1/pins/{id}/image): raw image bytes. Use variant=original (default) or variant=thumb; thumb falls back to original.
- [Boards](\(baseURL)/api/v1/boards): board names with pin counts.
- [Tags](\(baseURL)/api/v1/tags): tag names with pin counts.
- [Stats](\(baseURL)/api/v1/stats): library counters for pins, boards, tags, favorites, and images.
- [Context](\(baseURL)/api/v1/context): markdown design context with absolute image URLs, ready to paste into an agent prompt. Optional board, tag, color, and tone filters.
- [llms.txt](\(baseURL)/llms.txt): this index.
- [Landing page](\(baseURL)/): links to all of the above.

## Example

List the five most recent pins and show their absolute image URLs:

    curl -s "\(baseURL)/api/v1/pins?limit=5&sort=recent" | jq '.pins[] | {title, board, imageURL}'

Fetch paste-ready design context for one board:

    curl -s "\(baseURL)/api/v1/context?board=Web%20dashboards"

Find references by colour family and tone:

    curl -s "\(baseURL)/api/v1/pins?color=teal&tone=deep&limit=20" | jq '.pins[] | {title, colorFamilies, colorTone, imageURL}'

Download the original image for a pin:

    curl -s -o reference.png "\(baseURL)/api/v1/pins/{id}/image?variant=original"

Add a pin from a local screenshot (raw image body). Prefix the board with the product name so the pin is filed into that product's group:

    curl -s -X POST --data-binary @settings.png \\
      -H "Content-Type: image/png" \\
      "\(baseURL)/api/v1/pins?title=Settings&board=Linear%2FSettings&tags=settings,linear"

Add an animated GIF (frames are preserved; `animated` and `frameCount` are returned):

    curl -s -X POST --data-binary @loading.gif \
      -H "Content-Type: image/gif" \
      "\(baseURL)/api/v1/pins?title=Loading%20loop&board=Mobile%20flows&kind=image" \
      | jq '{id, animated, frameCount, imageURL}'

Add an SVG (the markup is stored as Images/<id>.svg; imageURL streams image/svg+xml):

    curl -s -X POST --data-binary @mark.svg \
      -H "Content-Type: image/svg+xml" \
      "\(baseURL)/api/v1/pins?title=Mark&board=Brand&tags=logo" \
      | jq '{id, kind, width, height, imageURL}'

Add a pin with JSON base64 (data URI prefixes are accepted):

    curl -s -X POST "\(baseURL)/api/v1/pins" \\
      -H "Content-Type: application/json" \\
      -d '{"imageBase64":"data:image/png;base64,iVBOR...","title":"Checkout flow","board":"Mobile flows","tags":["mobile","checkout"]}'

Rename or refile an existing pin (PATCH only touches the fields you send):

    curl -s -X PATCH "\(baseURL)/api/v1/pins/{id}" \\
      -H "Content-Type: application/json" \\
      -d '{"title":"Settings — Linear","board":"Linear/Settings","tags":["settings","linear"],"favorite":true}'

## Colour taxonomy

Every pin carries `colorFamily` (leading hue), `colorFamilies` (all meaningful
hues, ordered by coverage), and `colorTone` (tonal character). Classification is
automatic and works for pins added before the taxonomy existed.

Hue families: neutral, red, orange, yellow, green, teal, blue, violet, pink,
brown. A pin can belong to several families; `color=multicolor` matches pins
with three or more named hues. Tone: light, pastel, vivid, muted, deep.

## Animated images

GIFs are preserved as the original `Images/<id>.gif`; `imageURL` streams the
animated file, while `thumbnailURL` is a static first-frame JPEG. Every pin
carries `animated` (boolean) and `frameCount` (integer). The app plays GIFs on
card hover, in the detail card, and in large-image mode. Agent uploads are
analysed automatically; `kind` defaults to `image` for animated GIFs when the
agent does not supply one.

## Vector images

SVG uploads are stored verbatim as `Images/<id>.svg`; `imageURL` streams
image/svg+xml with a sandboxing Content-Security-Policy, while `thumbnailURL`
is a rasterised JPEG for previews. `width` and `height` report the document's
intrinsic size, and `kind` defaults to `svg` when the agent does not supply one.
The original stays vector, so an agent can recolor or rescale it without loss.
In the app, SVG pins render at the requested size for the grid, the detail
pane, and large-image mode; you can also add one by pasting markup into the
SVG sheet (or copying it and pressing ⌘V).

## Board hierarchy

Board names, titles, and tags are plain strings; only `/` is special. A pin on
board `Linear/Settings` appears under the `Linear` group in Lore's sidebar,
alongside `Linear/Onboarding`. Groups are collapsed by default, and filtering
still matches the full board string (`board=Linear/Settings`, URL-encoded as
`Linear%2FSettings` in query strings). When capturing screenshots for a
product, prefix the board with the product name and keep one nesting level:

    board=Linear/Settings
    board=Linear/Onboarding
    board=Modal/Dialog

## Notes

- The listener binds only to 127.0.0.1. It is not reachable from other devices.
- Read endpoints are read-only. POST /api/v1/pins appends a pin and writes Images/ and Thumbnails/ assets inside the library root; PATCH /api/v1/pins/{id} rewrites metadata only. The app owner can disable metadata edits in Settings, in which case PATCH returns 403 metadata_edits_disabled.
- Upload bodies are limited to 20 MiB. JSON base64 payloads must fit within that limit (base64 adds ~33% overhead).
- All endpoints support GET, HEAD, and OPTIONS (CORS preflight); POST is supported on /api/v1/pins only.
- Errors are JSON: {"error": {"code": "...", "message": "..."}} with HTTP 400, 404, 405, 413, 415, or 500.
- Image responses use the correct Content-Type for the stored file (for example image/png, image/jpeg, or image/svg+xml).
- No authentication is required because the API is loopback-only. Any local process can add pins; do not expose the port.
"""
    }
}
