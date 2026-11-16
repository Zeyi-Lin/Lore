# Lore Agent API

Lore is a macOS visual library for design screenshots. The **Lore Agent API** exposes that library over a loopback-only HTTP service so coding agents — Claude Code, Codex, Cursor, or any local script — can discover pinned references, read their metadata, fetch the actual images, add new references they captured, and update existing metadata. Read endpoints are read-only; `POST /api/v1/pins` adds pins and `PATCH /api/v1/pins/{id}` updates metadata when editing is enabled in Settings.

The API is embedded in the Lore app (via **LoreAgentKit**) and starts automatically with the app. It binds to **127.0.0.1 only**, never requires authentication, and re-reads the library from disk on every request, so what you see in Lore is exactly what an agent gets.

| Property | Value |
| --- | --- |
| Base URL | `http://127.0.0.1:4242` by default (configurable in Lore → Settings → Agent access) |
| API version | `v1` |
| Server implementation | `LoreAgentKit 1.1.0` (Network.framework, HTTP/1.1) |
| Data source | `<libraryRoot>/library.json` plus `Images/` and `Thumbnails/` |
| Access | Loopback-only, no authentication |
| Writes | `POST /api/v1/pins` (JSON base64 or raw image body; 20 MiB limit) and `PATCH /api/v1/pins/{id}` (partial metadata; 256 KiB limit) |
| Human docs | `GET /docs` (offline HTML page served by the API) |
| Machine-readable | `GET /openapi.json` (OpenAPI 3.1), `GET /llms.txt` |

---

## Quickstart

**1. Launch Lore.** The Agent API starts automatically on launch when *Agent access* is enabled (it is on by default). The bound port is shown in Lore's Agent access panel and defaults to **4242**.

**2. Check that the API is alive.**

```bash
curl -s http://127.0.0.1:4242/health
# {"api":"v1","app":"Lore","pinCount":12,"port":4242,"status":"ok","version":"1.1.0"}
```

**3. List recent pins.**

```bash
curl -s "http://127.0.0.1:4242/api/v1/pins?limit=5&sort=recent" \
  | jq '.pins[] | {title, board, imageURL}'
```

**4. Get paste-ready design context.**

```bash
curl -s "http://127.0.0.1:4242/api/v1/context?board=Web%20dashboards"
```

**5. Add a pin from a screenshot.** Either stream the raw image bytes, or send JSON with `imageBase64`:

```bash
# Raw image form — metadata in query parameters
curl -s -X POST --data-binary @shot.png \
  -H "Content-Type: image/png" \
  "http://127.0.0.1:4242/api/v1/pins?title=Checkout%20flow&board=Mobile%20flows&tags=mobile,checkout" | jq

# Animated GIF: original keeps its frames; animated/frameCount are derived
curl -s -X POST --data-binary @loading.gif \
  -H "Content-Type: image/gif" \
  "http://127.0.0.1:4242/api/v1/pins?title=Loading%20loop&board=Mobile%20flows&kind=image" \
  | jq '{id, animated, frameCount, imageURL}'

# SVG: the markup is stored as the original vector (imageURL returns image/svg+xml)
curl -s -X POST --data-binary @mark.svg \
  -H "Content-Type: image/svg+xml" \
  "http://127.0.0.1:4242/api/v1/pins?title=Brand%20mark&board=Brand&tags=logo" \
  | jq '{id, kind, width, height, imageURL}'

# JSON base64 form (data URI prefixes are accepted)
B64=$(base64 -i shot.png)
curl -s -X POST "http://127.0.0.1:4242/api/v1/pins" \
  -H "Content-Type: application/json" \
  -d "{\"imageBase64\": \"$B64\", \"title\": \"Checkout flow\", \"board\": \"Mobile flows\", \"tags\": [\"mobile\", \"checkout\"]}" | jq
```

**6. Open the documentation.** Visit `http://127.0.0.1:4242/docs`, which includes curl examples, the full endpoint table, and copy-paste blocks for agent instruction files.

> `jq` is optional but recommended for exploring responses. Install it with `brew install jq` if needed.

---

## Base URL, ports, and discovery

- The default base URL is `http://127.0.0.1:4242`. If port 4242 is already in use, Lore reports **API unavailable** in its status UI; choose another port (1024–65535) in Settings.
- The actual bound port is always reported by `GET /health` in the `port` field, and by Lore's Agent access status badge.
- For embedded/programmatic use, `AgentServerConfig(port: 0, ...)` binds an ephemeral port and reports it through `AgentServerStatus.running(port:)`.
- Discover the API without guessing:
  - `GET /health` — liveness + port + pin count
  - `GET /llms.txt` — llms.txt-style index with absolute links
  - `GET /openapi.json` — OpenAPI 3.1 spec including server URL and schemas

---

## Endpoints

Read endpoints accept **GET** and **HEAD**; `POST /api/v1/pins` accepts **POST**, and `PATCH /api/v1/pins/{id}` accepts **PATCH**. Every path answers **OPTIONS** for CORS preflight, and every response includes `Connection: close` and CORS headers.

| Method | Path | Response type | Purpose |
| --- | --- | --- | --- |
| GET | `/health` | JSON | Liveness, bound port, API version, pin count |
| GET | `/api/v1/health` | JSON | Versioned alias of `/health` |
| GET | `/api/v1/library` | JSON | Complete enriched library: stats, boards, tags, every pin |
| GET | `/api/v1/pins` | JSON | Filtered, sorted, paginated pin list |
| POST | `/api/v1/pins` | JSON | Add a pin from a JSON base64 payload or a raw image body (20 MiB limit) |
| PATCH | `/api/v1/pins/{id}` | JSON | Partially update pin metadata (JSON; 256 KiB limit) |
| GET | `/api/v1/pins/{id}` | JSON | One enriched pin by UUID |
| GET | `/api/v1/pins/{id}/image` | Raw image bytes | Original image or thumbnail |
| GET | `/api/v1/boards` | JSON | Board names with pin counts |
| GET | `/api/v1/tags` | JSON | Tag names with pin counts |
| GET | `/api/v1/stats` | JSON | Library counters |
| GET | `/api/v1/context` | `text/markdown` | Paste-ready design context for agents |
| GET | `/docs` | `text/html` | Offline documentation page (no CDNs, no external assets) |
| GET | `/openapi.json` | JSON | OpenAPI 3.1 description |
| GET | `/llms.txt` | `text/plain` | llms.txt-style discovery index with absolute links |
| GET | `/` | `text/html` | Tiny landing page linking to the docs |

Unknown paths return a JSON **404**. Known paths with an unsupported method return a JSON **405** with an `Allow` header listing the methods that path supports.

### GET /health

```json
{
  "status": "ok",
  "app": "Lore",
  "api": "v1",
  "version": "1.1.0",
  "pinCount": 12,
  "port": 4242
}
```

Health always returns `200` while the server is accepting connections. If `library.json` cannot be read, `pinCount` is `0` and library endpoints report a `500` error; this lets a supervising process distinguish "server up, library broken" from "server down".

### GET /api/v1/library

Returns the whole library in one response:

```json
{
  "app": "Lore",
  "version": "1.1.0",
  "generatedAt": "2026-11-14T02:57:54Z",
  "stats": { "pins": 12, "boards": 4, "tags": 18, "favorites": 2, "images": 12 },
  "boards": [ { "name": "Web dashboards", "count": 5 } ],
  "tags": [ { "name": "dashboard", "count": 7 } ],
  "colorFamilies": [ { "name": "blue", "count": 4 }, { "name": "multicolor", "count": 2 } ],
  "colorTones": [ { "name": "deep", "count": 3 }, { "name": "muted", "count": 5 } ],
  "pins": [ ...EnrichedPin objects... ]
}
```

Stats semantics:

| Field | Meaning |
| --- | --- |
| `pins` | Number of pins in the library |
| `boards` | Distinct non-empty board names |
| `tags` | Distinct tags across all pins |
| `favorites` | Pins with `favorite: true` |
| `images` | Pins that reference an image file |

`boards`, `tags`, `colorFamilies`, and `colorTones` are sorted by count descending, then name ascending. Colour-family counts are multi-membership: a teal-and-yellow pin counts in `teal`, `yellow`, and — when three or more families are present — `multicolor`.

### GET /api/v1/pins

Returns a page of enriched pins plus pagination metadata:

```json
{
  "count": 5,
  "total": 12,
  "offset": 0,
  "limit": 5,
  "pins": [ ...EnrichedPin objects... ]
}
```

Query parameters:

| Parameter | Type | Default | Behavior |
| --- | --- | --- | --- |
| `q` | string | — | Case-insensitive substring search across title, note, board, source label, kind, tags, colours, colour families, tone, and `gif` |
| `tag` | string | — | Case-insensitive exact match against the pin's tags |
| `board` | string | — | Case-insensitive exact match against the pin's board |
| `color` | enum | — | Match a detected hue family. A pin may match several families. Values: `neutral`, `red`, `orange`, `yellow`, `green`, `teal`, `blue`, `violet`, `pink`, `brown`, `multicolor`. Synonyms such as `cyan`, `purple`, and `grey` are accepted. `multicolor` matches pins with three or more named hues. |
| `tone` | enum | — | Match the auto-detected tonal character: `light`, `pastel`, `vivid`, `muted`, `deep`. Synonyms such as `dark` and `soft` are accepted. |
| `favorite` | boolean | — | `true` / `false` (also accepts `1`, `0`, `yes`, `no`) |
| `kind` | string | — | Case-insensitive exact match against `kind` (for example `screenshot`) |
| `sort` | enum | `recent` | `recent` (createdAt descending), `oldest` (createdAt ascending), `title` (title ascending, case-insensitive) |
| `limit` | integer | `50` | Page size, `1…200` |
| `offset` | integer | `0` | Pins to skip, `≥ 0` |

All filters combine with AND. `total` is the number of pins matching the filters before pagination; `count` is the number returned in this response.

Examples:

```bash
# Dark dashboard references, newest first
curl -s "http://127.0.0.1:4242/api/v1/pins?board=Web%20dashboards&tag=dark&sort=recent"

# Favorites, page 2
curl -s "http://127.0.0.1:4242/api/v1/pins?favorite=true&limit=10&offset=10"

# Full-text search
curl -s "http://127.0.0.1:4242/api/v1/pins?q=onboarding"

# Colour-family and tone filters
curl -s "http://127.0.0.1:4242/api/v1/pins?color=teal&tone=deep"
curl -s "http://127.0.0.1:4242/api/v1/pins?color=multicolor"
```

Invalid values (non-integer `limit`, out-of-range `limit`, negative `offset`, unknown `sort`, non-boolean `favorite`, unknown `color` or `tone`) return `400 invalid_parameter` rather than silently falling back.

### POST /api/v1/pins

Creates a pin and persists it to the library. Both request forms are limited to a **20 MiB** request body.

**Form 1 — JSON with base64** (`Content-Type: application/json`, optional charset):

```json
{
  "imageBase64": "data:image/png;base64,iVBORw0KGgo...",
  "mimeType": "image/png",
  "title": "Checkout flow",
  "note": "Three-step checkout captured from a design review.",
  "board": "Mobile flows",
  "tags": ["mobile", "checkout"],
  "sourceURL": "https://example.com/checkout",
  "sourceLabel": "Claude Code",
  "kind": "screenshot",
  "favorite": false
}
```

`imageBase64` is required. A `data:<mime>;base64,` prefix is accepted, and the embedded media type is used when `mimeType` is omitted. All metadata fields are optional.

```bash
B64=$(base64 -i shot.png)
curl -s -X POST "http://127.0.0.1:4242/api/v1/pins" \
  -H "Content-Type: application/json" \
  -d "{\"imageBase64\": \"$B64\", \"title\": \"Checkout flow\", \"board\": \"Mobile flows\", \"tags\": [\"mobile\", \"checkout\"]}" | jq
```

**Form 2 — raw image body** (`Content-Type: image/png`, `image/jpeg`, `image/webp`, `image/gif`, `image/heic`, `image/tiff`, `image/bmp`, `image/avif`, …). Metadata is passed as query parameters:

```bash
curl -s -X POST --data-binary @shot.png \
  -H "Content-Type: image/png" \
  "http://127.0.0.1:4242/api/v1/pins?title=Settings%20screen&note=Captured%20from%20the%20app&board=Linear%2FSettings&tags=settings,linear&sourceLabel=Claude%20Code&favorite=true" | jq
```

Metadata fields and defaults:

| Field | JSON form | Raw form | Default |
| --- | --- | --- | --- |
| `title` | `title` | `?title=` | `Agent capture · YYYY-MM-DD HH:MM` (UTC) |
| `note` | `note` | `?note=` | empty string |
| `board` | `board` | `?board=` | `Unsorted`; a `Product/Screen` name nests under `Product` in the app sidebar, while filtering still matches the full string (see [Board hierarchy](#board-hierarchy)) |
| `tags` | `tags` array | `?tags=` comma-separated | empty array |
| `sourceURL` | `sourceURL` | `?sourceURL=` | `null` |
| `sourceLabel` | `sourceLabel` | `?sourceLabel=` | `Agent API` |
| `kind` | `kind` | `?kind=` | `screenshot`; `svg` for vector uploads, `image` for animated files |
| `favorite` | `favorite` boolean | `?favorite=` | `false` |

**Naming captures.** When you capture screenshots for a product, prefix the board with the product name — e.g. `board=Linear/Settings` — so Lore files them under the Linear group. Prefer one level of nesting. Include the product name in the title too (e.g. `Settings — Linear`) so the pin reads well in search and design context.

Processing and response:

- The image is validated and decoded with ImageIO. Unsupported, corrupt, or non-image payloads return `400 invalid_image_data`; a body with no image returns `400 missing_image`.
- The original bytes are written to `<libraryRoot>/Images/<uuid>.<ext>`; a JPEG thumbnail (max 1200 px on the longest side) is written to `<libraryRoot>/Thumbnails/<uuid>.jpg`.
- SVG payloads are detected from their markup and stored verbatim at `<libraryRoot>/Images/<uuid>.svg`; the thumbnail is rasterised from the vector, `width`/`height` report the document's intrinsic size, and `kind` defaults to `svg`. The image endpoint serves them as `image/svg+xml` with a sandboxing `Content-Security-Policy`.
- Pixel dimensions, `fileSize`, timestamps, and up to five dominant palette colours are computed and stored.
- Tags are trimmed, lower-cased, and de-duplicated.
- The pin is appended to `library.json`, which is rewritten atomically as pretty-printed, sorted JSON. Existing pins and fields are preserved.
- Success returns `201 Created`, the enriched pin JSON, and a `Location: /api/v1/pins/{id}` header. The same pin is immediately available from every read endpoint.
- If anything fails, partially written image files are removed and the library is left unchanged. A missing or corrupt library returns the usual `500 library_unavailable` / `500 library_corrupt`.
- Unsupported `Content-Type` values return `415 unsupported_media_type`; declared bodies over 20 MiB return `413 request_body_too_large`.
- In the app, `LoreAgentServer.onLibraryChanged` fires once after the atomic write so the UI can reload.
- `POST` is accepted on `/api/v1/pins` only. On read-only paths it returns `405 method_not_allowed` with an `Allow` header listing the supported methods.

### PATCH /api/v1/pins/{id}

Partially updates one pin's metadata. Send `Content-Type: application/json` with at least one editable field; fields not named in the body are left unchanged, and `null` clears nullable fields. The response is `200` with the updated `EnrichedPin` — the same shape as `GET /api/v1/pins/{id}`. `updatedAt` is bumped; `id`, `image`, `thumbnail`, `width`, `height`, `fileSize`, `colors`, `colorFamilies`, `colorTone`, `animated`, `frameCount`, and `createdAt` are preserved (image analysis is derived, never agent-editable). `library.json` is rewritten atomically and the pin is immediately visible in every read endpoint.

Request example:

```json
{
  "title": "Settings — Linear",
  "note": "Account and workspace settings, captured from a design review.",
  "board": "Linear/Settings",
  "tags": ["settings", "linear"],
  "sourceURL": null,
  "favorite": true
}
```

```bash
curl -s -X PATCH "http://127.0.0.1:4242/api/v1/pins/<pin-id>" \
  -H "Content-Type: application/json" \
  -d '{"title":"Settings — Linear","board":"Linear/Settings","tags":["settings","linear"],"favorite":true}' | jq
```

Editable fields:

| Field | Type | Notes |
| --- | --- | --- |
| `title` | string | Non-empty after trimming; `null` and empty strings are rejected. |
| `note` | string \| null | `null` or an empty string clears the note; the response then returns `note: ""`. |
| `board` | string \| null | `null` or an empty string moves the pin to `Unsorted`; a `Product/Screen` name nests under `Product` in the app sidebar (see [Board hierarchy](#board-hierarchy)). |
| `tags` | string[] \| null | Replaces the whole array; `null` clears it. Tags are trimmed, lower-cased, and de-duplicated; at most 50 are kept, and tags longer than 64 characters are dropped. |
| `sourceURL` | string \| null | `null` or an empty string clears it. |
| `sourceLabel` | string \| null | `null` or an empty string clears it. |
| `favorite` | boolean | Must be a JSON boolean; `null` is rejected. |
| `kind` | string | `"screenshot"` or `"image"` (case-insensitive); `null` and other values are rejected. |

Bodies are limited to **256 KiB**; larger bodies return `413 request_body_too_large`. An empty or malformed JSON body returns `400 invalid_json`. A body with no editable fields, an unknown field, a wrong type, an empty or null `title`, or an unknown `kind` returns `400 invalid_metadata`. Unknown pins return `404 pin_not_found`; non-`application/json` payloads return `415 unsupported_media_type`; `PATCH /api/v1/pins` (the collection) returns `405 method_not_allowed`.

The library owner can disable metadata editing in **Lore → Settings → Agent API → Allow metadata edits** (on by default and persisted across launches). Toggling it restarts the local server; while off, every `PATCH /api/v1/pins/{id}` returns `403 metadata_edits_disabled`, and all read endpoints plus the in-app editor keep working.

### GET /api/v1/pins/{id}

Returns a single `EnrichedPin` or `404 pin_not_found`.

```bash
curl -s http://127.0.0.1:4242/api/v1/pins/6F1C2D4E-8A5B-4C3D-9E1F-2A3B4C5D6E7F
```

### GET /api/v1/pins/{id}/image

Streams raw image bytes with the correct `Content-Type`:

```bash
# Original image (default)
curl -s -o reference.png "http://127.0.0.1:4242/api/v1/pins/<pin-id>/image"

# Thumbnail (falls back to the original if no thumbnail exists)
curl -s -o reference-thumb.jpg "http://127.0.0.1:4242/api/v1/pins/<pin-id>/image?variant=thumb"
```

| Variant | Behavior |
| --- | --- |
| `original` (default) | Streams the pin's original image |
| `thumb` | Streams the thumbnail when present and readable; otherwise falls back to the original |

- `Content-Type` is detected from the file's magic bytes, then its extension: `image/png`, `image/jpeg`, `image/gif`, `image/webp`, `image/avif`, `image/heic`, `image/tiff`, `image/bmp`, `image/svg+xml`, `application/pdf`, or `application/octet-stream`.
- `HEAD` returns the same headers (including `Content-Length`) with no body.
- Unknown pins or missing images return JSON errors (`404 pin_not_found` / `404 image_not_found`), never an HTML error page.
- Only files referenced by a pin entry and resolvable **inside** the library root are served. Absolute paths, dot-segment escapes, and symlinks that resolve outside the root return `404`.

### GET /api/v1/boards

```json
{
  "boards": [
    { "name": "Web dashboards", "count": 5 },
    { "name": "Mobile flows", "count": 4 }
  ]
}
```

### Board hierarchy

`board` is a plain string, and the API never parses it. The app gives `/` a meaning: a pin on `Linear/Settings` is filed under a **Linear** group in the sidebar, and `Modal/Dialog` and `Modal/Sheet` collapse together under `Modal`. Groups start collapsed; expanding one shows the child boards indented. `PATCH /api/v1/pins/{id}` can refile a pin by changing `board`, and the same `Product/Screen` convention groups it in the sidebar.

Use `Product/Screen` with one level of nesting. Filtering still matches the full board string (case-insensitive) — the group itself is not addressable. `/api/v1/boards` keeps returning flat full names with counts, and `/api/v1/pins?board=` and `/api/v1/context?board=` expect the full name too. In query strings, URL-encode `/` as `%2F`:

```bash
curl -s "http://127.0.0.1:4242/api/v1/pins?board=Linear%2FSettings"
curl -s "http://127.0.0.1:4242/api/v1/context?board=Linear%2FSettings"
```

Examples: `Linear/Settings`, `Linear/Onboarding`, `Modal/Dialog` (and `Modal/Sheet`, which groups with it under `Modal`).

### GET /api/v1/tags

```json
{ "tags": [ { "name": "dashboard", "count": 7 } ] }
```

### GET /api/v1/stats

```json
{ "pins": 12, "boards": 4, "tags": 18, "favorites": 2, "images": 12 }
```

### GET /api/v1/context

Returns `text/markdown` designed to be pasted directly into an agent prompt. It includes the library summary, the active filters, and one section per pin with curated metadata and **absolute image URLs**.

Query parameters:

| Parameter | Type | Default | Behavior |
| --- | --- | --- | --- |
| `board` | string | — | Only pins on this board (case-insensitive exact) |
| `tag` | string | — | Only pins carrying this tag (case-insensitive exact) |
| `color` | enum | — | Only pins whose detected families include this value (`multicolor` for three or more hues) |
| `tone` | enum | — | Only pins with this tonal character |
| `limit` | integer | `20` | Maximum pins included, `1…100` |

Example output (trimmed):

```markdown
# Lore design context

> Local design reference from Lore, a visual library of UI screenshots. ...

- Base URL: http://127.0.0.1:4242
- Library: 12 pins · 4 boards · 18 tags
- Filter: board = "Web dashboards"
- Matches: 5 pins

## 1. Aurora analytics overview

- **Pin ID:** `6f1c...`
- **Board:** Web dashboards
- **Tags:** `dashboard`, `analytics`, `dark`
- **Dimensions:** 1440 × 900 · 412 KB
- **Palette:** `#0E1117`, `#E60023`
- **Color family:** blue / violet · deep
- **Source:** Dribbble — <https://dribbble.com/...>
- **Image:** <http://127.0.0.1:4242/api/v1/pins/6f1c.../image?variant=original>
- **Thumbnail:** <http://127.0.0.1:4242/api/v1/pins/6f1c.../image?variant=thumb>
- **Design note:** Dark analytics dashboard with magenta highlights and dense KPI cards.

## Next steps
...
```

If no pins match, the document still returns `200` with an empty-state message listing the available boards and tags, which is usually more useful to an agent than a bare 404.

### Discovery endpoints

- `GET /docs` — polished, fully offline HTML documentation (white canvas, Lore red `#E60023`, endpoint table, copyable curl examples). No external fonts, scripts, or CDNs.
- `GET /openapi.json` — OpenAPI 3.1.0 document with all paths, parameters, response schemas, and the actual bound server URL.
- `GET /llms.txt` — llms.txt-style plain-text index with absolute links and examples.
- `GET /` — minimal HTML landing page linking to the resources above.

---

## Data model: EnrichedPin

A pin contains every field Lore persists plus two absolute URLs. Responses **never** contain internal filesystem paths.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | Stable UUID; use it for detail and image requests |
| `title` | string | Human-readable pin name |
| `note` | string | Design note usable as an agent brief |
| `image` | string | Library-relative original path, for example `Images/aurora.png` |
| `thumbnail` | string \| null | Library-relative thumbnail path, or `null` |
| `width`, `height` | integer | Pixel dimensions of the original; intrinsic size for an SVG |
| `fileSize` | integer | Original file size in bytes |
| `createdAt`, `updatedAt` | string | ISO 8601 timestamps |
| `tags` | string[] | Lower-case filter labels |
| `board` | string | Board the pin belongs to |
| `sourceURL` | string \| null | Original inspiration URL |
| `sourceLabel` | string \| null | Human label for the source, for example `Dribbble` |
| `colors` | string[] | Dominant palette as `#RRGGBB` values |
| `colorFamily` | string | Leading auto-detected hue family |
| `colorFamilies` | string[] | Every meaningful hue family, ordered by coverage; multi-membership (teal + yellow) |
| `colorTone` | string | Auto-detected tonal character: `light`, `pastel`, `vivid`, `muted`, or `deep` |
| `animated` | boolean | `true` when the original image has multiple frames (for example a GIF) |
| `frameCount` | integer | Frame count of the original image; `1` for still images |
| `favorite` | boolean | Whether the pin is marked as a favorite |
| `kind` | string | Pin kind: `screenshot`, `image`, or `svg`; animated GIF uploads default to `image`, SVG uploads to `svg`, when `kind` is omitted |
| `imageURL` | string \| null | Absolute loopback URL for the original image |
| `thumbnailURL` | string \| null | Absolute loopback URL for the thumbnail; `null` when the pin has no thumbnail |

`imageURL` and `thumbnailURL` are built from the port the server actually bound, so they remain correct on custom ports and ephemeral test ports. For animated GIFs, `imageURL` streams the animated original; `thumbnailURL` streams a static first-frame JPEG. For SVG pins, `imageURL` streams the vector markup and `thumbnailURL` a rasterised JPEG.

---

## Errors

Every non-2xx response is JSON with a stable machine-readable code and a human-readable message:

```json
{
  "error": {
    "code": "pin_not_found",
    "message": "No pin with id \"6f1c...\" exists in the Lore library."
  }
}
```

| Status | Codes | When |
| --- | --- | --- |
| 400 | `bad_request`, `invalid_parameter`, `invalid_percent_encoding`, `invalid_utf8`, `invalid_content_length`, `request_header_too_large`, `request_body_too_large`, `unsupported_http_version`, `unsupported_transfer_encoding`, `invalid_json`, `missing_image`, `invalid_image_data`, `invalid_metadata` | Malformed request, invalid query values, or an unusable upload payload |
| 403 | `metadata_edits_disabled` | `PATCH /api/v1/pins/{id}` while metadata edits are turned off in Lore Settings |
| 404 | `not_found`, `pin_not_found`, `image_not_found` | Unknown route/pin/image, including blocked traversal attempts |
| 405 | `method_not_allowed` | Method not supported by the path; response includes `Allow` |
| 413 | `request_body_too_large` | Upload body exceeds the 20 MiB limit, or a PATCH body exceeds 256 KiB |
| 415 | `unsupported_media_type` | Upload or PATCH is not `application/json` or an `image/*` body |
| 500 | `library_unavailable`, `library_corrupt`, `storage_failure`, `internal_error` | Library file missing/unreadable/invalid, or assets could not be persisted |

HTTP status codes used: **400, 403, 404, 405, 413, 415, 500** (plus `204` for `OPTIONS`, `200` for successful reads and updates, and `201` for successful creation).

---

## HTTP behavior

- **CORS:** every response includes `Access-Control-Allow-Origin: *`, `Access-Control-Allow-Methods: GET, HEAD, OPTIONS, POST, PATCH`, and `Access-Control-Allow-Headers: Accept, Content-Type, Origin`. Preflight `OPTIONS` returns `204` with a path-specific `Allow` header (`POST` on `/api/v1/pins`; `PATCH` on `/api/v1/pins/{id}`).
- **HEAD:** supported on every endpoint. Headers (including `Content-Length`) match the corresponding GET; the body is omitted.
- **Connections:** one request per connection; every response sends `Connection: close` and a correct `Content-Length`. Request heads are capped at 32 KB. Only `POST /api/v1/pins` (up to 20 MiB) and `PATCH /api/v1/pins/{id}` (up to 256 KiB) wait for a request body, validated against `Content-Length`; read endpoints answer from the head alone. Chunked transfer encoding is rejected with `400 unsupported_transfer_encoding`.
- **URL encoding:** query keys and values are percent-decoded (`+` means space); malformed percent escapes return `400 invalid_percent_encoding`. Path dot-segments (`.` / `..`) are rejected as `404 not_found`.
- **Caching:** JSON responses send `Cache-Control: no-store`; images and docs send `Cache-Control: no-cache` so edits in Lore are visible immediately.
- **Headers:** every response includes `Server: LoreAgentKit/1.0.0`, an RFC 1123 `Date`, and `X-Content-Type-Options: nosniff`. SVG images also send a restrictive `Content-Security-Policy`.
- **Fresh reads:** `library.json` is decoded for every request. Adding, editing, or deleting pins in Lore is reflected on the next API call, with no restart.

---

## Using Lore with coding agents

### Drop-in instructions

Add this block to `AGENTS.md` (Codex), `CLAUDE.md` (Claude Code), or a Cursor rules file. Adjust the port if you changed it in Lore settings.

```markdown
## Lore design reference API

Lore runs a local HTTP API on loopback at http://127.0.0.1:4242.
It serves the user's pinned UI screenshots as JSON metadata plus image streams
and can add new pins from images you capture.

- Health:   GET /health
- Context:  GET /api/v1/context?board=&tag=&color=&tone=   (markdown, paste into your prompt)
- Pins:     GET /api/v1/pins?q=&tag=&board=&color=&tone=&favorite=&kind=&sort=&limit=&offset=
- Color:    color ∈ neutral, red, orange, yellow, green, teal, blue, violet, pink, brown, multicolor
- Tone:     tone ∈ light, pastel, vivid, muted, deep
- Pin:      GET /api/v1/pins/{id}
- Image:    GET /api/v1/pins/{id}/image?variant=original|thumb
- Library:  GET /api/v1/library
- Add pin:  POST /api/v1/pins   (JSON imageBase64, or raw image/* body with query metadata; 20 MiB; GIF frames are preserved; SVG stays vector)
- Update:   PATCH /api/v1/pins/{id}   (partial metadata: title, note, board, tags, source, favorite, kind; null clears)
- Board naming: add captures on Product/Screen boards (e.g. Linear/Settings); Lore groups them under Product in the sidebar.
- Docs:     GET /docs            OpenAPI: GET /openapi.json    Index: GET /llms.txt

Before writing UI code, fetch /api/v1/context (optionally filtered by board or tag),
pick one or two reference pins, inspect their imageURLs, then reproduce the layout,
spacing, typography, and palette. Always use the absolute image URLs returned by the
API; do not invent URLs or guess pin IDs.
```

### Example prompts

- *"Query Lore's design context for the board Web dashboards, choose the two most relevant references, and build the analytics overview page in SwiftUI. Match spacing, type scale, and palette."*
- *"Use Lore to find pins matching 'onboarding'. Read each pin's imageURL and design note, then implement the empty-state screen so it belongs to the same product family."*
- *"List Lore pins tagged editorial. Read their colors and thumbnails, and propose a consistent four-colour palette with hex values and usage notes."*
- *"Find Lore references with the colour family `teal` and the tone `deep`, inspect their palettes and imageURLs, and propose a dark teal design direction."*
- *"Before restyling the settings screen, pull Lore pins on the board Mobile flows and summarize the common navigation patterns."*
- *"Capture the current Figma frame and add it to Lore with POST /api/v1/pins, tagged 'checkout' on the Mobile flows board, then use its imageURL as the reference for the implementation."*
- *"Capture these five settings screenshots, add them to Lore on the board `Linear/Settings` with the tag `settings`, then pull the board context and restyle our settings page to match."*
- *"Review the Lore pins I just added; fix their titles and file each on a `Product/Screen` board with PATCH /api/v1/pins/{id}."*

### Useful jq recipes

```bash
# Titles, boards, and absolute image URLs for the 20 newest pins
curl -s "http://127.0.0.1:4242/api/v1/pins?limit=20&sort=recent" \
  | jq '.pins[] | {title, board, imageURL}'

# All palettes, flattened and de-duplicated
curl -s http://127.0.0.1:4242/api/v1/library \
  | jq '[.pins[].colors[]] | unique'

# Colour-family facets
curl -s http://127.0.0.1:4242/api/v1/library \
  | jq '.colorFamilies'

# Blue references, newest first
curl -s "http://127.0.0.1:4242/api/v1/pins?color=blue&limit=20" \
  | jq '.pins[] | {title, colorFamilies, colorTone, imageURL}'

# Total pins per board
curl -s http://127.0.0.1:4242/api/v1/boards | jq '.boards[] | "\(.name): \(.count)"'

# Download every favorite image
mkdir -p lore-references
curl -s "http://127.0.0.1:4242/api/v1/pins?favorite=true&limit=200" \
  | jq -r '.pins[] | [.id, .imageURL] | @tsv' \
  | while IFS=$'\t' read -r id url; do curl -s -o "lore-references/$id.png" "$url"; done

# One pin with everything
curl -s http://127.0.0.1:4242/api/v1/pins/<pin-id> | jq

# Upload a screenshot and print the created pin
curl -s -X POST --data-binary @shot.png \
  -H "Content-Type: image/png" \
  "http://127.0.0.1:4242/api/v1/pins?title=Checkout%20flow&board=Mobile%20flows&tags=mobile,checkout" \
  | jq '{id, title, width, height, imageURL}'
```

### Worked example: build a page from the library

```bash
# 1. Confirm the server and read the library summary
curl -s http://127.0.0.1:4242/health | jq

# 2. Ask for context scoped to the board you are working on
curl -s "http://127.0.0.1:4242/api/v1/context?board=Web%20dashboards" > context.md

# 3. Pick a reference and download its original image
PIN=$(curl -s "http://127.0.0.1:4242/api/v1/pins?board=Web%20dashboards&limit=1" | jq -r '.pins[0].id')
curl -s -o reference.png "http://127.0.0.1:4242/api/v1/pins/$PIN/image?variant=original"

# 4. Paste context.md + reference.png into your agent prompt
```

---

## Security and privacy

- **Loopback only.** The listener binds to `127.0.0.1` and is unreachable from other machines or network interfaces.
- **No authentication by design.** Any process running as the local user can read the library. This is the intended contract for a local design tool; do not port-forward, reverse-proxy, or otherwise expose the API beyond the Mac.
- **Two write endpoints.** `POST /api/v1/pins` validates images with ImageIO, writes assets inside the library root, and updates `library.json` atomically. `PATCH /api/v1/pins/{id}` rewrites metadata only — no image assets are touched — and can be disabled by the library owner in **Settings → Agent API → Allow metadata edits**. All other endpoints are read-only; there are no cookies or session state.
- **Local writes only.** Any process that can reach loopback can add pins or update their metadata. Do not port-forward, reverse-proxy, or otherwise expose the API beyond the Mac.
- **No filesystem leakage.** Responses contain library-relative image paths (which are part of the documented schema) and absolute loopback URLs; the configured library root is never exposed. Image serving rejects absolute paths, dot-segment escapes, and symlinks that leave the library root.
- **Hardened parsing.** Request-head size cap, Content-Length validation, percent-encoding validation, and one-request-per-connection semantics.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `curl: (7) Failed to connect` | Lore is not running, Agent access is off, or the API failed to bind | Launch Lore; enable Agent access; check the status badge or a custom port |
| Status shows *API unavailable* | Port already in use or invalid | Pick a different port (1024–65535) in Settings and retry |
| `500 library_unavailable` | `library.json` is missing at the configured library root | Open Lore once so it creates the library, or check the data folder setting |
| `500 library_corrupt` | `library.json` is not valid JSON or is missing required pin fields | Recover/repair the library; the error message includes the decoding path |
| `404 image_not_found` | The pin has no image or its image file is missing | Re-import the image in Lore |
| `pinCount` is 0 but the app shows pins | The app's library root differs from the API's `libraryRoot` | Ensure the app started the server with its own data root |
| `400 invalid_parameter` | Invalid `limit`, `offset`, `sort`, or `favorite` value | Use documented values; see the parameters table |
| `405 method_not_allowed` | Tried POST/PATCH/PUT/DELETE on a path that does not accept it | Only `POST /api/v1/pins` and `PATCH /api/v1/pins/{id}` are writable; read endpoints accept GET/HEAD |
| `403 metadata_edits_disabled` | Metadata edits are turned off in Settings | Enable **Allow metadata edits** in Lore → Settings → Agent API |
| `413 request_body_too_large` | Upload body exceeds 20 MiB, or a PATCH body exceeds 256 KiB | Downscale the screenshot, or send a smaller metadata patch |
| `415 unsupported_media_type` | Upload used a non-JSON, non-image Content-Type | Send `application/json` with `imageBase64`, or a raw image body with `image/png`/`image/jpeg`/… |
| `400 invalid_image_data` | Base64 did not decode to an image, or the bytes are not a supported image or are malformed SVG | Verify the file opens as PNG/JPEG/WebP/GIF/HEIC/TIFF/BMP/AVIF, or that the SVG renders |
| Browser CORS error | Custom browser code without preflight | Send an `OPTIONS` preflight; CORS headers are always present |

---

## Versioning

- The API generation is `v1`, reflected in the path prefix `/api/v1/` and the `api` field of `/health`.
- `version` (currently `1.1.0`) identifies the LoreAgentKit implementation and may change independently of the API generation.
- Changes within `v1` are additive: new optional fields or endpoints may appear, but existing fields, status codes, and semantics stay compatible. Clients should ignore unknown JSON fields.
- `generatedAt` in `/api/v1/library` indicates when the snapshot was produced; the library itself is read fresh on every request.
- `POST /api/v1/pins` and `PATCH /api/v1/pins/{id}` are additive within `v1`: clients that only read the library keep working unchanged.
- `/openapi.json` is authoritative for the current machine-readable contract.

---

## Development and verification

### Source layout

| Path | Contents |
| --- | --- |
| `Sources/LoreAgentKit/` | Embedded HTTP server, router, library model, image ingest pipeline, docs/OpenAPI/llms content |
| `Tests/LoreAgentKitTests/` | 49 Swift Testing tests (ephemeral ports, temporary library roots) |
| `docs/AGENT_API.md` | This document |
| `scripts/agent-smoke-test.sh` | Builds the kit and black-box tests a live server against a temp fixture library |

### Build and test

The API target builds independently of the app:

```bash
swift build --target LoreAgentKit
swift test --filter LoreAgentKitTests
```

Requirements and environment notes:

- **Full Xcode toolchain (recommended):** both commands work as usual. The test suite is written with **Swift Testing** (`import Testing`).
- **Command Line Tools only (no Xcode):** XCTest is not installed and SwiftPM cannot execute XCTest-based test bundles. The Swift Testing suite can still be compiled and run, but the compiler/linker need the CLT `Testing.framework`, and sandboxed shells need `--disable-sandbox` plus workspace-local caches:

```bash
export CLANG_MODULE_CACHE_PATH="$PWD/.build/cache/clang"
export SWIFT_MODULECACHE_PATH="$PWD/.build/cache/swift"
export TMPDIR="$PWD/.build/tmp"
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
INTEROP=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
swift test --disable-sandbox --manifest-cache local \
  --cache-path .build/spm-cache --scratch-path .build \
  -Xswiftc -F -Xswiftc "$FW" \
  -Xlinker -rpath -Xlinker "$FW" \
  -Xlinker -rpath -Xlinker "$INTEROP"
```

> If a CLT-only machine builds the test bundle but does not execute it with plain `swift test`, that is an environment limitation (no XCTest harness), not an API defect. Use the smoke test below as the authoritative end-to-end verification in that case.

The suite covers: health and alias, library JSON shape and enrichment, stats/boards/tags, search/filter/sort/pagination, invalid parameters, pin detail, image streaming and thumbnails, HEAD metadata, thumbnail fallback, docs/OpenAPI/llms.txt presence, CORS and OPTIONS, 405/404 handling, malformed and oversized raw HTTP requests, dot-segment rejection, path-traversal and symlink escapes, library reload and corrupt/missing-library errors, lifecycle (start/stop/restart, port conflict), concurrent request handling, and the full image-ingest surface: JSON and raw uploads, metadata persistence, thumbnail capping, invalid base64/missing image/unsupported media type, oversized-rejection via Content-Length, atomic append and preserved existing pins, orphan cleanup, `onLibraryChanged` firing, and concurrent uploads.

### Smoke test

```bash
./scripts/agent-smoke-test.sh          # build kit + black-box HTTP checks
./scripts/agent-smoke-test.sh --tests  # also run the Swift Testing suite
```

The script builds `LoreAgentKit` (and a temporary standalone harness), writes a fixture library to a temporary directory, starts the server on an ephemeral port, and runs 192 black-box checks covering health, library, filters, pin detail, images/thumbnails, HEAD, CORS, OPTIONS, 405/404, traversal protection, docs, OpenAPI, llms.txt, the metadata-update flow (successful partial update, null clearing, board move, validation failures, unknown pin, disabled-editing 403, and PATCH in CORS/OPTIONS plus docs/OpenAPI/llms.txt), and the ingest flow: JSON and raw uploads, metadata/tags/board persistence, image and thumbnail verification, default metadata, invalid JSON/base64/media type, oversized-rejection, POST-to-read-only-path 405s, and CORS/OPTIONS advertising POST. It prints `PASS`/`FAIL` lines and exits non-zero on failure (`SMOKE TEST PASSED: 192 checks` on success). Requirements: `swift` and `python3`; it never reads the real Lore library.

### How the app wires it

```swift
let server = LoreAgentServer(
    config: AgentServerConfig(port: agentPort, libraryRoot: root)
)
server.onStatusChange = { status in
    // called on a background queue; hop to main for UI updates
}
server.onLibraryChanged = {
    // called on a background queue after POST /api/v1/pins wrote library.json;
    // reload the app's in-memory library here
}
server.start()   // returns immediately
// ...
server.stop()    // releases the listening socket
```

- `config.port` defaults to `4242`; `0` requests an ephemeral port.
- `onStatusChange` receives `.starting`, `.running(port:)`, `.failed(message)`, and `.stopped` on a background queue.
- `onLibraryChanged` fires once per successful `POST /api/v1/pins` after the atomic library write, and is the app's cue to reload pins without polling.
- `status`, `runningPort`, `baseURL`, and `isRunning` are thread-safe conveniences for the UI.
- The app's data root is `~/Library/Application Support/Lore` (overridable with the `LORE_HOME` environment variable), containing `library.json`, `Images/`, and `Thumbnails/`.
