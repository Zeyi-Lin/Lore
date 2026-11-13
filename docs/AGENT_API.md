# Canta Agent API

Canta is a macOS visual library for design screenshots. The **Canta Agent API** exposes that library over a read-only, loopback-only HTTP service so coding agents — Claude Code, Codex, Cursor, or any local script — can discover pinned references, read their metadata, and fetch the actual images before writing UI code.

The API is embedded in the Canta app (via **CantaAgentKit**) and starts automatically with the app. It binds to **127.0.0.1 only**, never requires authentication, and re-reads the library from disk on every request, so what you see in Canta is exactly what an agent gets.

| Property | Value |
| --- | --- |
| Base URL | `http://127.0.0.1:4242` by default (configurable in Canta → Settings → Agent access) |
| API version | `v1` |
| Server implementation | `CantaAgentKit 1.0.0` (Network.framework, HTTP/1.1) |
| Data source | `<libraryRoot>/library.json` plus `Images/` and `Thumbnails/` |
| Access | Read-only, loopback-only, no authentication |
| Human docs | `GET /docs` (offline HTML page served by the API) |
| Machine-readable | `GET /openapi.json` (OpenAPI 3.1), `GET /llms.txt` |

---

## Quickstart

**1. Launch Canta.** The Agent API starts automatically on launch when *Agent access* is enabled (it is on by default). The bound port is shown in Canta's Agent access panel and defaults to **4242**.

**2. Check that the API is alive.**

```bash
curl -s http://127.0.0.1:4242/health
# {"api":"v1","app":"Canta","pinCount":12,"port":4242,"status":"ok","version":"1.0.0"}
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

**5. Open the documentation.** Visit `http://127.0.0.1:4242/docs`, which includes curl examples, the full endpoint table, and copy-paste blocks for agent instruction files.

> `jq` is optional but recommended for exploring responses. Install it with `brew install jq` if needed.

---

## Base URL, ports, and discovery

- The default base URL is `http://127.0.0.1:4242`. If port 4242 is already in use, Canta reports **API unavailable** in its status UI; choose another port (1024–65535) in Settings.
- The actual bound port is always reported by `GET /health` in the `port` field, and by Canta's Agent access status badge.
- For embedded/programmatic use, `AgentServerConfig(port: 0, ...)` binds an ephemeral port and reports it through `AgentServerStatus.running(port:)`.
- Discover the API without guessing:
  - `GET /health` — liveness + port + pin count
  - `GET /llms.txt` — llms.txt-style index with absolute links
  - `GET /openapi.json` — OpenAPI 3.1 spec including server URL and schemas

---

## Endpoints

All endpoints are **read-only**, accept **GET** and **HEAD**, and answer **OPTIONS** for CORS preflight. Every response includes `Connection: close` and CORS headers.

| Method | Path | Response type | Purpose |
| --- | --- | --- | --- |
| GET | `/health` | JSON | Liveness, bound port, API version, pin count |
| GET | `/api/v1/health` | JSON | Versioned alias of `/health` |
| GET | `/api/v1/library` | JSON | Complete enriched library: stats, boards, tags, every pin |
| GET | `/api/v1/pins` | JSON | Filtered, sorted, paginated pin list |
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

Unknown paths return a JSON **404**. Known paths with an unsupported method return a JSON **405** with an `Allow: GET, HEAD, OPTIONS` header.

### GET /health

```json
{
  "status": "ok",
  "app": "Canta",
  "api": "v1",
  "version": "1.0.0",
  "pinCount": 12,
  "port": 4242
}
```

Health always returns `200` while the server is accepting connections. If `library.json` cannot be read, `pinCount` is `0` and library endpoints report a `500` error; this lets a supervising process distinguish "server up, library broken" from "server down".

### GET /api/v1/library

Returns the whole library in one response:

```json
{
  "app": "Canta",
  "version": "1.0.0",
  "generatedAt": "2026-11-14T02:57:54Z",
  "stats": { "pins": 12, "boards": 4, "tags": 18, "favorites": 2, "images": 12 },
  "boards": [ { "name": "Web dashboards", "count": 5 } ],
  "tags": [ { "name": "dashboard", "count": 7 } ],
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

`boards` and `tags` are sorted by count descending, then name ascending.

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
| `q` | string | — | Case-insensitive substring search across title, note, board, source label, kind, tags, and colours |
| `tag` | string | — | Case-insensitive exact match against the pin's tags |
| `board` | string | — | Case-insensitive exact match against the pin's board |
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
```

Invalid values (non-integer `limit`, out-of-range `limit`, negative `offset`, unknown `sort`, non-boolean `favorite`) return `400 invalid_parameter` rather than silently falling back.

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
| `limit` | integer | `20` | Maximum pins included, `1…100` |

Example output (trimmed):

```markdown
# Canta design context

> Local design reference from Canta, a visual library of UI screenshots. ...

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
- **Source:** Dribbble — <https://dribbble.com/...>
- **Image:** <http://127.0.0.1:4242/api/v1/pins/6f1c.../image?variant=original>
- **Thumbnail:** <http://127.0.0.1:4242/api/v1/pins/6f1c.../image?variant=thumb>
- **Design note:** Dark analytics dashboard with magenta highlights and dense KPI cards.

## Next steps
...
```

If no pins match, the document still returns `200` with an empty-state message listing the available boards and tags, which is usually more useful to an agent than a bare 404.

### Discovery endpoints

- `GET /docs` — polished, fully offline HTML documentation (white canvas, Canta red `#E60023`, endpoint table, copyable curl examples). No external fonts, scripts, or CDNs.
- `GET /openapi.json` — OpenAPI 3.1.0 document with all paths, parameters, response schemas, and the actual bound server URL.
- `GET /llms.txt` — llms.txt-style plain-text index with absolute links and examples.
- `GET /` — minimal HTML landing page linking to the resources above.

---

## Data model: EnrichedPin

A pin contains every field Canta persists plus two absolute URLs. Responses **never** contain internal filesystem paths.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | Stable UUID; use it for detail and image requests |
| `title` | string | Human-readable pin name |
| `note` | string | Design note usable as an agent brief |
| `image` | string | Library-relative original path, for example `Images/aurora.png` |
| `thumbnail` | string \| null | Library-relative thumbnail path, or `null` |
| `width`, `height` | integer | Pixel dimensions of the original |
| `fileSize` | integer | Original file size in bytes |
| `createdAt`, `updatedAt` | string | ISO 8601 timestamps |
| `tags` | string[] | Lower-case filter labels |
| `board` | string | Board the pin belongs to |
| `sourceURL` | string \| null | Original inspiration URL |
| `sourceLabel` | string \| null | Human label for the source, for example `Dribbble` |
| `colors` | string[] | Dominant palette as `#RRGGBB` values |
| `favorite` | boolean | Whether the pin is marked as a favorite |
| `kind` | string | Pin kind, for example `screenshot` |
| `imageURL` | string \| null | Absolute loopback URL for the original image |
| `thumbnailURL` | string \| null | Absolute loopback URL for the thumbnail; `null` when the pin has no thumbnail |

`imageURL` and `thumbnailURL` are built from the port the server actually bound, so they remain correct on custom ports and ephemeral test ports.

---

## Errors

Every non-2xx response is JSON with a stable machine-readable code and a human-readable message:

```json
{
  "error": {
    "code": "pin_not_found",
    "message": "No pin with id \"6f1c...\" exists in the Canta library."
  }
}
```

| Status | Codes | When |
| --- | --- | --- |
| 400 | `bad_request`, `invalid_parameter`, `invalid_percent_encoding`, `invalid_utf8`, `invalid_content_length`, `request_header_too_large`, `request_body_too_large`, `unsupported_http_version`, `unsupported_transfer_encoding` | Malformed request or invalid query values |
| 404 | `not_found`, `pin_not_found`, `image_not_found` | Unknown route/pin/image, including blocked traversal attempts |
| 405 | `method_not_allowed` | Method other than GET, HEAD, or OPTIONS; response includes `Allow` |
| 500 | `library_unavailable`, `library_corrupt`, `internal_error` | Library file missing/unreadable or invalid JSON |

HTTP status codes used: **400, 404, 405, 500** (plus `204` for `OPTIONS` and `200` for successful requests).

---

## HTTP behavior

- **CORS:** every response includes `Access-Control-Allow-Origin: *`, `Access-Control-Allow-Methods: GET, HEAD, OPTIONS`, and `Access-Control-Allow-Headers: Accept, Content-Type, Origin`. Preflight `OPTIONS` returns `204` with `Allow`.
- **HEAD:** supported on every endpoint. Headers (including `Content-Length`) match the corresponding GET; the body is omitted.
- **Connections:** one request per connection; every response sends `Connection: close` and a correct `Content-Length`. Request heads are capped at 32 KB; bodies are ignored/limited to 1 MB (the API is read-only).
- **URL encoding:** query keys and values are percent-decoded (`+` means space); malformed percent escapes return `400 invalid_percent_encoding`. Path dot-segments (`.` / `..`) are rejected as `404 not_found`.
- **Caching:** JSON responses send `Cache-Control: no-store`; images and docs send `Cache-Control: no-cache` so edits in Canta are visible immediately.
- **Headers:** every response includes `Server: CantaAgentKit/1.0.0`, an RFC 1123 `Date`, and `X-Content-Type-Options: nosniff`. SVG images also send a restrictive `Content-Security-Policy`.
- **Fresh reads:** `library.json` is decoded for every request. Adding, editing, or deleting pins in Canta is reflected on the next API call, with no restart.

---

## Using Canta with coding agents

### Drop-in instructions

Add this block to `AGENTS.md` (Codex), `CLAUDE.md` (Claude Code), or a Cursor rules file. Adjust the port if you changed it in Canta settings.

```markdown
## Canta design reference API

Canta runs a read-only HTTP API on loopback at http://127.0.0.1:4242.
It serves the user's pinned UI screenshots as JSON metadata plus image streams.

- Health:   GET /health
- Context:  GET /api/v1/context?board=&tag=   (markdown, paste into your prompt)
- Pins:     GET /api/v1/pins?q=&tag=&board=&favorite=&kind=&sort=&limit=&offset=
- Pin:      GET /api/v1/pins/{id}
- Image:    GET /api/v1/pins/{id}/image?variant=original|thumb
- Library:  GET /api/v1/library
- Docs:     GET /docs            OpenAPI: GET /openapi.json    Index: GET /llms.txt

Before writing UI code, fetch /api/v1/context (optionally filtered by board or tag),
pick one or two reference pins, inspect their imageURLs, then reproduce the layout,
spacing, typography, and palette. Always use the absolute image URLs returned by the
API; do not invent URLs or guess pin IDs.
```

### Example prompts

- *"Query Canta's design context for the board Web dashboards, choose the two most relevant references, and build the analytics overview page in SwiftUI. Match spacing, type scale, and palette."*
- *"Use Canta to find pins matching 'onboarding'. Read each pin's imageURL and design note, then implement the empty-state screen so it belongs to the same product family."*
- *"List Canta pins tagged editorial. Read their colors and thumbnails, and propose a consistent four-colour palette with hex values and usage notes."*
- *"Before restyling the settings screen, pull Canta pins on the board Mobile flows and summarize the common navigation patterns."*

### Useful jq recipes

```bash
# Titles, boards, and absolute image URLs for the 20 newest pins
curl -s "http://127.0.0.1:4242/api/v1/pins?limit=20&sort=recent" \
  | jq '.pins[] | {title, board, imageURL}'

# All palettes, flattened and de-duplicated
curl -s http://127.0.0.1:4242/api/v1/library \
  | jq '[.pins[].colors[]] | unique'

# Total pins per board
curl -s http://127.0.0.1:4242/api/v1/boards | jq '.boards[] | "\(.name): \(.count)"'

# Download every favorite image
mkdir -p canta-references
curl -s "http://127.0.0.1:4242/api/v1/pins?favorite=true&limit=200" \
  | jq -r '.pins[] | [.id, .imageURL] | @tsv' \
  | while IFS=$'\t' read -r id url; do curl -s -o "canta-references/$id.png" "$url"; done

# One pin with everything
curl -s http://127.0.0.1:4242/api/v1/pins/<pin-id> | jq
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
- **Read-only.** No mutating endpoints, cookies, or session state.
- **No filesystem leakage.** Responses contain library-relative image paths (which are part of the documented schema) and absolute loopback URLs; the configured library root is never exposed. Image serving rejects absolute paths, dot-segment escapes, and symlinks that leave the library root.
- **Hardened parsing.** Request-head size cap, Content-Length validation, percent-encoding validation, and one-request-per-connection semantics.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `curl: (7) Failed to connect` | Canta is not running, Agent access is off, or the API failed to bind | Launch Canta; enable Agent access; check the status badge or a custom port |
| Status shows *API unavailable* | Port already in use or invalid | Pick a different port (1024–65535) in Settings and retry |
| `500 library_unavailable` | `library.json` is missing at the configured library root | Open Canta once so it creates the library, or check the data folder setting |
| `500 library_corrupt` | `library.json` is not valid JSON or is missing required pin fields | Recover/repair the library; the error message includes the decoding path |
| `404 image_not_found` | The pin has no image or its image file is missing | Re-import the image in Canta |
| `pinCount` is 0 but the app shows pins | The app's library root differs from the API's `libraryRoot` | Ensure the app started the server with its own data root |
| `400 invalid_parameter` | Invalid `limit`, `offset`, `sort`, or `favorite` value | Use documented values; see the parameters table |
| `405 method_not_allowed` | Tried POST/PUT/DELETE | The API is read-only; use GET |
| Browser CORS error | Custom browser code without preflight | Send an `OPTIONS` preflight; CORS headers are always present |

---

## Versioning

- The API generation is `v1`, reflected in the path prefix `/api/v1/` and the `api` field of `/health`.
- `version` (currently `1.0.0`) identifies the CantaAgentKit implementation and may change independently of the API generation.
- Changes within `v1` are additive: new optional fields or endpoints may appear, but existing fields, status codes, and semantics stay compatible. Clients should ignore unknown JSON fields.
- `generatedAt` in `/api/v1/library` indicates when the snapshot was produced; the library itself is read fresh on every request.
- `/openapi.json` is authoritative for the current machine-readable contract.

---

## Development and verification

### Source layout

| Path | Contents |
| --- | --- |
| `Sources/CantaAgentKit/` | Embedded HTTP server, router, library model, docs/OpenAPI/llms content |
| `Tests/CantaAgentKitTests/` | 35 Swift Testing tests (ephemeral ports, temporary library roots) |
| `docs/AGENT_API.md` | This document |
| `scripts/agent-smoke-test.sh` | Builds the kit and black-box tests a live server against a temp fixture library |

### Build and test

The API target builds independently of the app:

```bash
swift build --target CantaAgentKit
swift test --filter CantaAgentKitTests
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

The suite covers: health and alias, library JSON shape and enrichment, stats/boards/tags, search/filter/sort/pagination, invalid parameters, pin detail, image streaming and thumbnails, HEAD metadata, thumbnail fallback, docs/OpenAPI/llms.txt presence, CORS and OPTIONS, 405/404 handling, malformed and oversized raw HTTP requests, dot-segment rejection, path-traversal and symlink escapes, library reload and corrupt/missing-library errors, lifecycle (start/stop/restart, port conflict), and concurrent request handling.

### Smoke test

```bash
./scripts/agent-smoke-test.sh          # build kit + black-box HTTP checks
./scripts/agent-smoke-test.sh --tests  # also run the Swift Testing suite
```

The script builds `CantaAgentKit` (and a temporary standalone harness), writes a fixture library to a temporary directory, starts the server on an ephemeral port, and runs 114 black-box checks covering health, library, filters, pin detail, images/thumbnails, HEAD, CORS, OPTIONS, 405/404, traversal protection, docs, OpenAPI, and llms.txt. It prints `PASS`/`FAIL` lines and exits non-zero on failure (`SMOKE TEST PASSED: 114 checks` on success). Requirements: `swift` and `python3`; it never reads the real Canta library.

### How the app wires it

```swift
let server = CantaAgentServer(
    config: AgentServerConfig(port: agentPort, libraryRoot: root)
)
server.onStatusChange = { status in
    // called on a background queue; hop to main for UI updates
}
server.start()   // returns immediately
// ...
server.stop()    // releases the listening socket
```

- `config.port` defaults to `4242`; `0` requests an ephemeral port.
- `onStatusChange` receives `.starting`, `.running(port:)`, `.failed(message)`, and `.stopped` on a background queue.
- `status`, `runningPort`, `baseURL`, and `isRunning` are thread-safe conveniences for the UI.
- The app's data root is `~/Library/Application Support/Canta` (overridable with the `CANTA_HOME` environment variable), containing `library.json`, `Images/`, and `Thumbnails/`.
