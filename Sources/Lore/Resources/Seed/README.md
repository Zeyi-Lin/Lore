# Lore — Seed Library

The content that ships with Lore so the gallery feels alive on first launch. Everything here is
fictional work created for the app: twelve UI screenshots of made-up products, rendered from
hand-written HTML/CSS, plus thumbnails and metadata.

```
Seed/
├── seed.json          # version 1 manifest read by the app at launch (12 pins)
├── Images/            # full-size PNG screenshots, <slug>.png
├── Thumbnails/        # JPEG thumbnails, max 800 px wide, quality 82
└── README.md
```

## Contents

| # | Pin | Board | Size | Direction |
|---|-----|-------|------|-----------|
| 01 | Pulse — team health, without the noise | Web dashboards | 1600×1000 | glassmorphism, pastel gradient |
| 02 | Tide — a softer habit tracker | Mobile flows | 780×1688 | playful coral/teal, rounded type |
| 03 | Aurora — realtime product analytics | Web dashboards | 1440×900 | dark mode, data-dense |
| 04 | Atelier — objects made slowly | Landing pages | 1440×1000 | warm editorial, serif display |
| 05 | Sage — plant care, quietly | Mobile flows | 780×1688 | botanical, bone + sage, calm |
| 06 | Field Notes — the quiet science of attention | Editorial | 1440×1000 | typographic poster, Didot display |
| 07 | Orbit — bring every orbit into view | Landing pages | 1440×1000 | dark glass, cosmic gradient |
| 08 | Miso — dinner, decided | Mobile flows | 780×1688 | playful food, chunky type |
| 09 | Ledger — spend, reconciled | Web dashboards | 1600×1000 | crisp monochrome, Swiss grid |
| 10 | Noema — a reading workspace | Web dashboards | 1440×900 | warm paper, three-pane editorial |
| 11 | Cadence — practice, measured | Mobile flows | 780×1688 | dark mode, electric lime |
| 12 | Terrain — field operations, mapped | Web dashboards | 1600×1000 | dark map console, contour lines |

Boards: 5 Web dashboards, 4 Mobile flows, 2 Landing pages, 1 Editorial. Three pins are marked
`favorite`. Mobile screens are captured at 390×844 CSS px with a 2× device scale factor (780×1688).

## seed.json

`version: 1` with a `pins` array. Each pin:

- `id` — stable UUID v4 (generated once; do not regenerate when editing copy)
- `title`, `note` — display title and a 1–2 sentence design note for the agent/UI
- `image`, `thumbnail` — paths relative to this folder (`Images/<slug>.png`, `Thumbnails/<slug>.jpg`)
- `width`, `height`, `fileSize` — actual PNG pixel size and byte size
- `createdAt`, `updatedAt` — ISO 8601 UTC, spread over 2–13 November 2026
- `tags` (3–5), `board` (one of `Web dashboards`, `Mobile flows`, `Landing pages`, `Editorial`)
- `sourceURL` (null for seed pins), `sourceLabel` ("Lore Seed")
- `colors` — four palette swatches sampled from the image itself (background, signature accents, ink)
- `colorFamilies`, `colorTone` — optional auto-detected colour taxonomy; omitted here and analysed from each image on first launch
- `favorite` (bool), `kind` ("screenshot")

`Images/`, `Thumbnails/` and `seed.json` are copied into the app bundle through
`Sources/Lore/Resources`; the app reads `seed.json` from its resources at launch.

## How it was generated

1. Each scene is a single hand-written HTML file with inline CSS and inline SVG only — system
   fonts (`-apple-system`, `Iowan Old Style`, `Didot`, `Avenir Next`, `SF Mono`), no network/CDN
   assets, no real brand marks. Copy, data labels and navigation are written as real product copy.
2. Rendered with headless Google Chrome at the sizes above (`--headless=new --hide-scrollbars`).
   Mobile screens use `--force-device-scale-factor=2` with a 390×844 viewport.
   In this environment Chrome also needs `--no-sandbox --disable-gpu-sandbox` and an explicit
   `--user-data-dir` because of the outer file sandbox.
3. PNGs are kept at native resolution; thumbnails are resized to max 800 px wide and saved as
   JPEG quality 82 with Pillow.
4. `seed.json` is generated from the rendered files: real UUIDs, actual PNG dimensions and byte
   sizes, and palettes sampled from the pixels (dominant background + saturated accent clusters +
   ink/contrast colour).
5. Sanity checks before shipping: JSON parses, every referenced file exists, recorded dimensions
   and `fileSize` match the PNGs, thumbnails are JPEG ≤ 800 px wide, palettes are 4 × `#RRGGBB`,
   dates parse, tags are 3–5, exactly the four allowed boards are used.

The HTML sources and render scripts are authoring tools and are deliberately not shipped in the app
bundle; only the PNG/JPEG artifacts and `seed.json` are runtime resources. Regenerating from the
sources reproduces the same compositions.

The app icon lives separately at `Sources/Lore/Resources/AppIcon/icon_1024.png` (1024×1024,
transparent canvas: signature red `#E60023` squircle carrying the in-app brand mark — two tilted
cards and the red heart). Regenerate it with `python3 scripts/make-app-icon.py`; the geometry mirrors
`LoreMark` in `Sources/Lore/Design/Components.swift`.
