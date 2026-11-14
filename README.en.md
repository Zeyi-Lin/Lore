# Canta

[简体中文](README.md) · **English**

**A quiet visual library for humans and their agents.**

Canta is a native macOS app for capturing UI screenshots, keeping them in a Pinterest-style gallery, layering on useful metadata, and serving the whole library to coding agents over a loopback HTTP API. Pin an interface you like, and your agent can fetch its palette, dimensions, tags, and an exact image stream while it builds the next screen.

![Canta gallery](docs/screenshots/en/gallery.png)

<p align="center">
  <img src="docs/screenshots/en/detail.png" width="49%" alt="Pin close-up with metadata and palette" />
  <img src="docs/screenshots/en/agent.png" width="49%" alt="Agent access page with local API endpoints" />
</p>

## Why Canta

Design reference usually lives in a messy folder of screenshots, a chat thread, or a dozen browser tabs. Agents can't see any of it. Canta is a small, local-first memory for visual taste:

- **Fast to capture** — drag files in, paste from the clipboard (⇧⌘V), or grab a screen region (⇧⌘2).
- **Pinterest, but for references** — a balanced masonry gallery with hover save, boards, search, and favorites.
- **Metadata that matters** — editable titles, design notes, tags, boards, source attribution, dimensions, file size, dominant palette, and timestamps.
- **Agent-readable by default** — a localhost API exposes enriched JSON plus original/thumbnail image streams, Markdown design context, an OpenAPI 3.1 spec, llms.txt, and an in-app documentation site. Agents can also add images back into the library.
- **Batch work** — enter selection mode to favorite, move, copy agent context, or delete several cards at once.
- **Large image & keyboard browsing** — open a pin and switch to image-only mode; use ← / → to move between pins and Esc to go back.
- **Hand-cursor details** — cards, buttons, menus, switches, and every other clickable control use the pointing-hand cursor.
- **Local and private** — images and metadata stay on this Mac. The server binds only to 127.0.0.1.

## Capture

| Action | Shortcut |
| --- | --- |
| Quick capture sheet | ⌘N |
| Import images | ⌘O |
| Paste image from clipboard | ⇧⌘V |
| Capture a screen region | ⇧⌘2 |
| Search pins | ⌘F |
| Open Agent access | ⌘4 |
| Select multiple cards | ⌘B |
| Previous / next pin in detail | ← / → |
| Enter image-only mode (detail) | Double-click image or click “Large image” |

### Batch selection & large image

<p align="center">
  <img src="docs/screenshots/en/batch.png" width="49%" alt="Batch selection on cards" />
  <img src="docs/screenshots/en/large.png" width="49%" alt="Image-only large mode" />
</p>

In selection mode, cards get a check circle and the bottom bar can select all, favorite, move to a board, copy agent context, or delete in one action. In any pin detail, click **Large image** or double-click the image for an image-only view; use ← / → to move between pins and Esc to go back.

![Quick capture sheet](docs/screenshots/en/capture.png)

You can also drop files anywhere on the window. Canta reads pixel dimensions, file size, and a five-color palette automatically; titles are derived from filenames and can be edited in the pin close-up.

> Screen region capture uses macOS's built-in `screencapture -i`. The first run may ask for Screen Recording permission.

## Agent access

By default the API runs at **http://127.0.0.1:4242** while Canta is open.

```bash
# Full, enriched library JSON
curl -s http://127.0.0.1:4242/api/v1/library | jq

# Filter pins
curl -s "http://127.0.0.1:4242/api/v1/pins?board=Web%20dashboards&favorite=true" | jq

# Markdown context — paste straight into an agent prompt
curl -s http://127.0.0.1:4242/api/v1/context

# Let an agent add an image (raw upload)
curl -X POST "http://127.0.0.1:4242/api/v1/pins?title=Agent%20capture&board=Unsorted" \
  -H "Content-Type: image/png" \
  --data-binary @screenshot.png

# Or send JSON + base64
curl -X POST http://127.0.0.1:4242/api/v1/pins \
  -H "Content-Type: application/json" \
  -d '{"imageBase64":"...","title":"Agent capture","tags":["landing","dark"]}'

# Open the documentation site
open http://127.0.0.1:4242/docs
```

Each pin exposes `imageURL` and `thumbnailURL` fields that stream raw bytes, so an agent can inspect the reference itself, not just its description.

Discovery endpoints:

- `/docs` — styled documentation for humans and agents
- `/openapi.json` — OpenAPI 3.1 specification
- `/llms.txt` — compact machine-readable index
- `/api/v1/context` — Markdown design context for prompting
- `POST /api/v1/pins` — image ingest (raw image or JSON base64)

The server can be stopped, restarted, or moved to another port from **Agent access** in the sidebar or **Settings**. The offline HTML docs at `/docs` are a first-class surface:

[![Canta Agent API documentation](docs/screenshots/api-docs.png)](docs/screenshots/api-docs.png)

A full reference also lives in [docs/AGENT_API.md](docs/AGENT_API.md).

## Build and run

Requirements: macOS 14 or newer, Swift 6 toolchain (Command Line Tools or Xcode).

```bash
./scripts/build-app.sh release
open dist/Canta.app
```

The build script bundles the SwiftPM resource bundle, generates the app icon from the 1024 px master, writes `Info.plist`, and ad-hoc signs `dist/Canta.app`.

For day-to-day development:

```bash
swift build
swift run Canta
```

On a bare Command Line Tools install (no Xcode), SwiftPM's nested sandbox can be blocked by the host sandbox. Use:

```bash
export CLANG_MODULE_CACHE_PATH="$PWD/.build/cache/clang"
export SWIFT_MODULECACHE_PATH="$PWD/.build/cache/swift"
swift build --disable-sandbox --manifest-cache local --cache-path .build/spm-cache --scratch-path .build
```

## Data model

Everything is plain files under:

```
~/Library/Application Support/Canta/
├── library.json      # pins + metadata
├── Images/           # original captures
├── Thumbnails/       # 1200 px JPEG previews (detail / agent)
└── Cards/            # 640 px JPEG grid thumbnails (generated on import; backfilled in the background for older libraries)
```

`library.json` is the single source of truth and is re-read by the API on every request. The schema is documented in [docs/AGENT_API.md](docs/AGENT_API.md). Set `CANTA_HOME` to point the app at a different library for development.

## Project structure

```
Sources/
├── Canta/                      SwiftUI macOS app
│   ├── CantaApp.swift          app entry, commands, menus
│   ├── Design/                 theme, components, image loading
│   ├── Localization/           English + Simplified Chinese strings
│   ├── Store/                  persistence, image processing, seed library
│   └── Views/                  gallery, pin close-up, capture, agent access
├── CantaAgentKit/              loopback HTTP API, docs, OpenAPI, llms.txt
└── Canta/Resources/Seed/       designed sample library (HTML-rendered PNGs)
Tests/                          API tests
docs/                           API reference + screenshots
scripts/                        packaging and screenshot helpers
```

The API target has no third-party dependencies; it uses Network.framework and Foundation. The app uses SwiftUI, AppKit, ImageIO, and UniformTypeIdentifiers.

## Design language

Canta borrows Pinterest's confidence — image-first cards, generous white space, a signature red, and a masonry that never feels mechanical — then warms it into a library: paper-toned surfaces, editorial type, quieter motion, and metadata that is always one click away.

The app's red is `#E60023`; the canvas is paper white with warm parchment wells. Cards use 18 px continuous radii, the pin close-up uses a 30 px radius, and all state changes favor short, eased springs.

## Language

Canta ships with **English** and **Simplified Chinese** interfaces. It follows the macOS system language by default; open **Settings → Language** to switch at any time. The choice is remembered.

## Verification

- `./scripts/build-app.sh release` produces the self-contained app bundle.
- `./scripts/perf-bench/run.sh` reproduces the pre-optimization data-layer baseline; `Canta --bench` prints query/encode/decode timings of the current implementation for a real library.
- The Agent API has a black-box smoke suite with a temporary fixture library:

  ```bash
  ./scripts/agent-smoke-test.sh
  ```

  It starts the real server on an ephemeral port and checks every endpoint family, JSON/raw image uploads, HEAD/OPTIONS/CORS behavior, JSON shape, filters, image bytes, and traversal protection (154 checks).
- The Swift Testing suite in `Tests/CantaAgentKitTests` contains 49 tests. Executing it requires Xcode's XCTest runner; the Command Line Tools-only environment here compiles the suite but cannot run it, so the smoke test is the authoritative local check.
- Automated screenshots are reproducible with `./scripts/screenshot-app.sh gallery|agent|capture|detail|batch|large`; set `SCREENSHOT_LANG=en|zh` to capture either language.

## Status

Canta 1.0 is a complete, local-first macOS app. The seed library is designed from scratch and rendered from hand-written HTML/CSS; no external assets or network requests are used at runtime.