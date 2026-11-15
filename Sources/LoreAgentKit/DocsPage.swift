import Foundation

/// The polished, fully offline documentation page served at <code>/docs</code>.
enum DocsPage {
    static func html(baseURL: String) -> String {
        let port = baseURL.split(separator: ":").last.map(String.init) ?? "4242"
        return """
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lore Agent API — local design library for coding agents</title>
<meta name="description" content="Lore exposes a loopback-only HTTP API for browsing pinned UI screenshots, metadata, palettes, and images — and for agents to add new references. Built for coding agents that replicate designs.">
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Crect width='64' height='64' rx='16' fill='%23E60023'/%3E%3Crect x='14' y='20' width='30' height='24' rx='5' fill='white'/%3E%3Ccircle cx='45' cy='23' r='6' fill='%23161412'/%3E%3C/svg%3E">
<style>
:root {
  --canvas: #ffffff;
  --ink: #161412;
  --muted: #6f6a64;
  --line: #e8e2dc;
  --soft: #faf7f4;
  --accent: #e60023;
  --accent-soft: #fdecee;
  --code-bg: #1d1a18;
  --code-ink: #f7f2ec;
  --radius: 20px;
  --shadow: 0 1px 2px rgba(22, 20, 18, 0.05), 0 18px 40px rgba(22, 20, 18, 0.06);
  --mono: ui-monospace, "SF Mono", SFMono-Regular, Menlo, Consolas, monospace;
}
* { box-sizing: border-box; }
html { scroll-behavior: smooth; }
body {
  margin: 0;
  background: var(--canvas);
  color: var(--ink);
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  line-height: 1.62;
  -webkit-font-smoothing: antialiased;
}
::selection { background: var(--accent-soft); color: var(--ink); }
a { color: inherit; }
code, pre { font-family: var(--mono); }
.skip-link {
  position: absolute; left: -9999px; top: 0; background: var(--ink); color: #fff;
  padding: 10px 16px; border-radius: 0 0 10px 0; z-index: 20;
}
.skip-link:focus { left: 0; }
.topbar {
  position: sticky; top: 0; z-index: 10;
  display: flex; align-items: center; justify-content: space-between; gap: 24px;
  padding: 14px clamp(20px, 5vw, 48px);
  background: rgba(255, 255, 255, 0.86);
  backdrop-filter: saturate(180%) blur(18px);
  border-bottom: 1px solid var(--line);
}
.brand { display: flex; align-items: center; gap: 12px; font-weight: 700; letter-spacing: -0.02em; text-decoration: none; }
.brand svg { display: block; }
.brand small { display: block; font-weight: 500; font-size: 11px; letter-spacing: 0.14em; text-transform: uppercase; color: var(--muted); }
.topnav { display: flex; align-items: center; gap: 22px; font-size: 14px; color: var(--muted); }
.topnav a { text-decoration: none; }
.topnav a:hover { color: var(--accent); }
.topnav .nav-cta {
  color: var(--ink); border: 1px solid var(--line); border-radius: 999px; padding: 7px 15px;
  background: var(--soft); font-weight: 600;
}
.topnav .nav-cta:hover { border-color: var(--accent); color: var(--accent); }
main { max-width: 1080px; margin: 0 auto; padding: 0 clamp(20px, 5vw, 48px) 40px; }
.hero { padding: clamp(52px, 9vw, 104px) 0 20px; }
.eyebrow {
  display: inline-flex; align-items: center; gap: 9px;
  font-size: 12px; font-weight: 700; letter-spacing: 0.16em; text-transform: uppercase;
  color: var(--muted); margin: 0 0 22px;
}
.eyebrow .dot { width: 8px; height: 8px; border-radius: 50%; background: #1f9d55; box-shadow: 0 0 0 4px rgba(31, 157, 85, 0.14); }
h1 {
  font-size: clamp(2.5rem, 6vw, 4.1rem);
  line-height: 1.02;
  letter-spacing: -0.045em;
  margin: 0 0 24px;
  font-weight: 800;
}
h1 .accent { color: var(--accent); }
.lede { font-size: clamp(1.02rem, 1.6vw, 1.2rem); color: var(--muted); max-width: 680px; margin: 0 0 30px; }
.lede strong { color: var(--ink); font-weight: 650; }
.base-url {
  display: flex; flex-wrap: wrap; align-items: center; gap: 12px;
  background: var(--soft); border: 1px solid var(--line); border-radius: 16px;
  padding: 12px 14px; max-width: 720px; box-shadow: var(--shadow);
}
.base-url .label { font-size: 11px; font-weight: 700; letter-spacing: 0.14em; text-transform: uppercase; color: var(--muted); padding-left: 6px; }
.base-url code { font-size: 15px; background: #fff; border: 1px solid var(--line); border-radius: 10px; padding: 8px 12px; flex: 1 1 300px; color: var(--ink); overflow-wrap: anywhere; }
.hero-meta { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 18px; }
.pill { font-size: 12.5px; color: var(--muted); background: var(--soft); border: 1px solid var(--line); border-radius: 999px; padding: 5px 12px; }
.section { padding: 52px 0 8px; scroll-margin-top: 84px; }
.section-head { display: flex; align-items: baseline; justify-content: space-between; gap: 20px; margin-bottom: 8px; }
h2 { font-size: clamp(1.5rem, 2.6vw, 2rem); letter-spacing: -0.03em; margin: 0; font-weight: 750; }
.section-sub { color: var(--muted); margin: 0 0 26px; max-width: 760px; }
h3 { font-size: 1.02rem; margin: 0 0 8px; letter-spacing: -0.01em; font-weight: 700; }
.grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 18px; }
.card { background: #fff; border: 1px solid var(--line); border-radius: var(--radius); padding: 22px; box-shadow: var(--shadow); }
.card p { color: var(--muted); margin: 0 0 14px; font-size: 14.5px; }
.step { display: inline-flex; align-items: center; justify-content: center; width: 26px; height: 26px; border-radius: 50%; background: var(--accent); color: #fff; font-size: 13px; font-weight: 700; margin-right: 10px; }
.snippet { border-radius: 16px; overflow: hidden; border: 1px solid #2b2723; background: var(--code-bg); box-shadow: var(--shadow); }
.snippet-head { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 9px 12px 9px 16px; background: #241f1c; border-bottom: 1px solid #322c28; }
.snippet-head .snippet-label { font-family: var(--mono); font-size: 11.5px; letter-spacing: 0.06em; text-transform: uppercase; color: #b9aea4; }
.snippet pre { margin: 0; padding: 16px; font-size: 12.5px; line-height: 1.65; color: var(--code-ink); white-space: pre-wrap; overflow-wrap: anywhere; word-break: break-word; }
.snippet code { font-size: inherit; }
.copy {
  appearance: none; border: 1px solid #403932; background: #2b2521; color: #e9e1d8;
  border-radius: 8px; font-size: 11.5px; font-weight: 600; padding: 5px 10px; cursor: pointer;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}
.copy:hover { border-color: var(--accent); color: #fff; }
.copy.copied { background: var(--accent); border-color: var(--accent); color: #fff; }
.table-wrap { border: 1px solid var(--line); border-radius: var(--radius); overflow: auto; box-shadow: var(--shadow); background: #fff; }
table { width: 100%; border-collapse: collapse; font-size: 14px; min-width: 720px; }
th { text-align: left; font-size: 11px; letter-spacing: 0.1em; text-transform: uppercase; color: var(--muted); font-weight: 700; padding: 14px 16px; background: var(--soft); border-bottom: 1px solid var(--line); }
td { padding: 14px 16px; border-bottom: 1px solid var(--line); vertical-align: top; }
tr:last-child td { border-bottom: 0; }
td code, .inline-code { background: var(--soft); border: 1px solid var(--line); border-radius: 7px; padding: 2px 7px; font-size: 12.5px; white-space: nowrap; }
.method { display: inline-block; font-family: var(--mono); font-size: 11px; font-weight: 700; letter-spacing: 0.05em; color: var(--accent); background: var(--accent-soft); border: 1px solid #f6c9d0; border-radius: 999px; padding: 3px 9px; }
.method-post { color: #1a56b8; background: #eaf1fd; border-color: #c8dafb; }
.muted { color: var(--muted); }
.two-col { display: grid; grid-template-columns: minmax(0, 1.15fr) minmax(0, 0.85fr); gap: 22px; align-items: start; }
.list { margin: 0; padding-left: 20px; color: var(--muted); font-size: 14.5px; }
.list li { margin: 7px 0; }
.list strong { color: var(--ink); font-weight: 650; }
.note { border-left: 3px solid var(--accent); background: var(--accent-soft); border-radius: 0 14px 14px 0; padding: 16px 18px; color: #7a1420; font-size: 14.5px; }
.note strong { color: #5d0f18; }
.prompt { background: var(--soft); border: 1px solid var(--line); border-radius: 16px; padding: 18px 20px; font-size: 14.5px; color: var(--ink); margin: 14px 0; }
.prompt .prompt-label { display: block; font-size: 11px; font-weight: 700; letter-spacing: 0.12em; text-transform: uppercase; color: var(--accent); margin-bottom: 6px; }
.prompt p { margin: 0; color: var(--ink); }
footer { border-top: 1px solid var(--line); margin-top: 60px; padding: 28px clamp(20px, 5vw, 48px) 44px; color: var(--muted); font-size: 13.5px; }
footer .footer-inner { max-width: 1080px; margin: 0 auto; display: flex; flex-wrap: wrap; justify-content: space-between; gap: 16px; }
footer strong { color: var(--ink); }
@media (max-width: 780px) {
  .grid, .two-col { grid-template-columns: minmax(0, 1fr); }
  .topnav a:not(.nav-cta) { display: none; }
  .section { padding-top: 40px; }
}
</style>
</head>
<body>
<a class="skip-link" href="#endpoints">Skip to endpoints</a>
<header class="topbar">
  <a class="brand" href="/docs">
    <svg width="30" height="30" viewBox="0 0 30 30" aria-hidden="true">
      <rect x="1" y="1" width="28" height="28" rx="8" fill="#E60023"/>
      <rect x="7" y="9" width="13" height="12" rx="2.5" fill="#fff"/>
      <circle cx="23" cy="9" r="2.6" fill="#161412"/>
    </svg>
    <span>Lore<small>Agent API</small></span>
  </a>
  <nav class="topnav" aria-label="Page sections">
    <a href="#quickstart">Quickstart</a>
    <a href="#endpoints">Endpoints</a>
    <a href="#examples">Examples</a>
    <a href="#agents">Agent setup</a>
    <a href="#errors">Errors</a>
    <a class="nav-cta" href="/llms.txt">llms.txt</a>
  </nav>
</header>
<main>
  <section class="hero">
    <p class="eyebrow"><span class="dot"></span> Running locally on 127.0.0.1:\(port) · API v1</p>
    <h1>Your design library,<br><span class="accent">available to your agents.</span></h1>
    <p class="lede">Lore serves every pinned screenshot as <strong>metadata plus a real image stream</strong>, over a loopback-only HTTP API. Point Claude Code, Codex, Cursor, or any local script at it to pull layout references, palettes, and design notes before writing UI code. The library is re-read on every request, so what you see in the app is what the API returns. Agents can also add pins with <code>POST /api/v1/pins</code> — raw image bytes or JSON base64 — and Lore saves the image, thumbnail, and metadata into the library.</p>
    <div class="base-url">
      <span class="label">Base URL</span>
      <code id="base-url">\(baseURL)</code>
      <button class="copy" type="button" data-copy="base-url">Copy</button>
    </div>
    <div class="hero-meta">
      <span class="pill">Bound to loopback only</span>
      <span class="pill">Agent ingest via POST</span>
      <span class="pill">No auth required</span>
      <span class="pill">Fresh library per request</span>
      <span class="pill">Offline — no external assets</span>
    </div>
  </section>

  <section class="section" id="quickstart">
    <div class="section-head"><h2>Quickstart</h2></div>
    <p class="section-sub">Seven requests get an agent from "is Lore running?" to a design brief with reference images — including adding new references and editing their metadata from an agent workflow.</p>
    <div class="grid">
      <article class="card">
        <h3><span class="step">1</span>Check the server</h3>
        <p>Confirms the API is live and reports the bound port plus the current pin count.</p>
        <div class="snippet">
          <div class="snippet-head"><span class="snippet-label">curl</span><button class="copy" type="button" data-copy="snip-health">Copy</button></div>
          <pre id="snip-health"><code>curl -s \(baseURL)/health</code></pre>
        </div>
      </article>
      <article class="card">
        <h3><span class="step">2</span>Browse recent pins</h3>
        <p>Filter with <span class="inline-code">q</span>, <span class="inline-code">tag</span>, <span class="inline-code">board</span>, <span class="inline-code">color</span>, <span class="inline-code">tone</span>, <span class="inline-code">favorite</span>, or <span class="inline-code">kind</span>; paginate with <span class="inline-code">limit</span> and <span class="inline-code">offset</span>.</p>
        <div class="snippet">
          <div class="snippet-head"><span class="snippet-label">curl + jq</span><button class="copy" type="button" data-copy="snip-pins">Copy</button></div>
          <pre id="snip-pins"><code>curl -s "\(baseURL)/api/v1/pins?limit=5&sort=recent" | jq '.pins[] | {title, board, imageURL}'</code></pre>
        </div>
      </article>
      <article class="card">
        <h3><span class="step">3</span>Grab design context</h3>
        <p>Returns ready-to-paste markdown: curated metadata, palettes, colour families, and absolute image URLs for the pins that match a board, tag, colour family, or tone.</p>
        <div class="snippet">
          <div class="snippet-head"><span class="snippet-label">curl</span><button class="copy" type="button" data-copy="snip-context">Copy</button></div>
          <pre id="snip-context"><code>curl -s "\(baseURL)/api/v1/context?board=Web%20dashboards"</code></pre>
        </div>
      </article>
      <article class="card">
        <h3><span class="step">4</span>Download a reference image</h3>
        <p><span class="inline-code">variant=thumb</span> is faster for previews; it falls back to the original when no thumbnail exists.</p>
        <div class="snippet">
          <div class="snippet-head"><span class="snippet-label">curl</span><button class="copy" type="button" data-copy="snip-image">Copy</button></div>
          <pre id="snip-image"><code>curl -s -o reference.png "\(baseURL)/api/v1/pins/&lt;pin-id&gt;/image?variant=original"</code></pre>
        </div>
      </article>
      <article class="card">
        <h3><span class="step">5</span>Add a pin (JSON)</h3>
        <p>Send base64 image bytes plus optional metadata. Data URI prefixes are accepted; tags are trimmed, lower-cased, and de-duplicated.</p>
        <div class="snippet">
          <div class="snippet-head"><span class="snippet-label">curl + jq</span><button class="copy" type="button" data-copy="snip-create-json">Copy</button></div>
          <pre id="snip-create-json"><code>B64=$(base64 -i shot.png)
curl -s -X POST "\(baseURL)/api/v1/pins" \\
  -H "Content-Type: application/json" \\
  -d "{\\\"imageBase64\\\": \\\"$B64\\\", \\\"title\\\": \\\"Checkout flow\\\", \\\"board\\\": \\\"Mobile flows\\\", \\\"tags\\\": [\\\"mobile\\\", \\\"checkout\\\"]}" | jq</code></pre>
        </div>
      </article>
      <article class="card">
        <h3><span class="step">6</span>Add a pin (raw image)</h3>
        <p>Stream the file directly with an <span class="inline-code">image/*</span> Content-Type and metadata as query parameters. Great for large screenshots; 20 MiB limit. Prefix the board with the product name (<span class="inline-code">Linear/Settings</span>) so captures file under that product's group.</p>
        <div class="snippet">
          <div class="snippet-head"><span class="snippet-label">curl + jq</span><button class="copy" type="button" data-copy="snip-create-raw">Copy</button></div>
          <pre id="snip-create-raw"><code>curl -s -X POST --data-binary @settings.png \\
  -H "Content-Type: image/png" \\
  "\(baseURL)/api/v1/pins?title=Settings&board=Linear%2FSettings&tags=settings,linear" | jq</code></pre>
        </div>
      </article>
      <article class="card">
        <h3><span class="step">7</span>Edit pin metadata</h3>
        <p>Send only the fields you want to change: title, note, board, tags, source, favorite, or kind. Null clears a nullable field. The owner can switch this off in Settings.</p>
        <div class="snippet">
          <div class="snippet-head"><span class="snippet-label">curl + jq</span><button class="copy" type="button" data-copy="snip-update">Copy</button></div>
          <pre id="snip-update"><code>curl -s -X PATCH "\(baseURL)/api/v1/pins/&lt;pin-id&gt;" \\
  -H "Content-Type: application/json" \\
  -d '{"title": "Settings — Linear", "board": "Linear/Settings", "tags": ["settings", "linear"]}' \\
  | jq '{id, title, board, updatedAt}'</code></pre>
        </div>
      </article>
    </div>
  </section>

  <section class="section" id="endpoints">
    <div class="section-head"><h2>Endpoints</h2></div>
    <p class="section-sub">Read endpoints support <span class="inline-code">GET</span>, <span class="inline-code">HEAD</span>, and CORS preflight <span class="inline-code">OPTIONS</span>; <span class="inline-code">POST /api/v1/pins</span> creates a pin. JSON errors always use the same envelope.</p>
    <div class="table-wrap">
      <table>
        <thead>
          <tr><th>Method</th><th>Path</th><th>Returns</th><th>Description</th></tr>
        </thead>
        <tbody>
          <tr><td><span class="method">GET</span></td><td><code>/health</code></td><td><code>application/json</code></td><td>Health, bound port, current pin count. Alias: <code>/api/v1/health</code>.</td></tr>
          <tr><td><span class="method">GET</span></td><td><code>/api/v1/library</code></td><td><code>application/json</code></td><td>Full enriched library: stats, boards, tags, and every pin.</td></tr>
          <tr><td><span class="method">GET</span></td><td><code>/api/v1/pins</code></td><td><code>application/json</code></td><td>Filtered, sorted, paginated pin list with <span class="inline-code">count</span>, <span class="inline-code">total</span>, <span class="inline-code">offset</span>, <span class="inline-code">limit</span>.</td></tr>
          <tr><td><span class="method method-post">POST</span></td><td><code>/api/v1/pins</code></td><td><code>application/json</code></td><td>Add a pin: JSON <span class="inline-code">imageBase64</span> body, or raw <span class="inline-code">image/*</span> body with metadata query parameters. Returns <span class="inline-code">201</span> and a <span class="inline-code">Location</span> header.</td></tr>
          <tr><td><span class="method method-post">PATCH</span></td><td><code>/api/v1/pins/{id}</code></td><td><code>application/json</code></td><td>Update metadata: title, note, board, tags, source, favorite, or kind. Null clears a nullable field. Returns the updated pin, or <span class="inline-code">403 metadata_edits_disabled</span> when the owner turned edits off.</td></tr>
          <tr><td><span class="method">GET</span></td><td><code>/api/v1/pins/{id}</code></td><td><code>application/json</code></td><td>A single enriched pin, or a 404 JSON error.</td></tr>
          <tr><td><span class="method">GET</span></td><td><code>/api/v1/pins/{id}/image</code></td><td><code>image/png</code> · <code>image/jpeg</code> · …</td><td>Raw image bytes. <span class="inline-code">variant=original|thumb</span>, defaults to original.</td></tr>
          <tr><td><span class="method">GET</span></td><td><code>/api/v1/boards</code></td><td><code>application/json</code></td><td>Board names with pin counts. A <code>/</code> in a name nests it under a group in the app — <code>Linear/Settings</code> folds into <code>Linear</code>.</td></tr>
          <tr><td><span class="method">GET</span></td><td><code>/api/v1/tags</code></td><td><code>application/json</code></td><td>Tag names with pin counts.</td></tr>
          <tr><td><span class="method">GET</span></td><td><code>/api/v1/stats</code></td><td><code>application/json</code></td><td>Library counters: pins, boards, tags, favorites, images.</td></tr>
          <tr><td><span class="method">GET</span></td><td><code>/api/v1/context</code></td><td><code>text/markdown</code></td><td>Paste-ready design context with absolute image URLs. <span class="inline-code">board=</span>, <span class="inline-code">tag=</span>, <span class="inline-code">color=</span>, <span class="inline-code">tone=</span>, optional <span class="inline-code">limit=</span>.</td></tr>
          <tr><td><span class="method">GET</span></td><td><code>/docs</code></td><td><code>text/html</code></td><td>This page — fully offline, no CDNs.</td></tr>
          <tr><td><span class="method">GET</span></td><td><code>/openapi.json</code></td><td><code>application/json</code></td><td>OpenAPI 3.1 description of every endpoint and schema.</td></tr>
          <tr><td><span class="method">GET</span></td><td><code>/llms.txt</code></td><td><code>text/plain</code></td><td>llms.txt index with absolute links, for agents that discover services by URL.</td></tr>
          <tr><td><span class="method">GET</span></td><td><code>/</code></td><td><code>text/html</code></td><td>Tiny landing page linking to this documentation.</td></tr>
        </tbody>
      </table>
    </div>
  </section>

  <section class="section" id="examples">
    <div class="section-head"><h2>Examples</h2></div>
    <p class="section-sub">Copy these directly into a terminal or into an agent's tool-call instructions.</p>
    <div class="two-col">
      <div>
        <h3>Find dark dashboard references</h3>
        <div class="snippet">
          <div class="snippet-head"><span class="snippet-label">shell</span><button class="copy" type="button" data-copy="ex-filter">Copy</button></div>
          <pre id="ex-filter"><code>curl -s "\(baseURL)/api/v1/pins?board=Web%20dashboards&tag=dark&sort=recent&limit=10" \\
  | jq '.pins[] | {id, title, colors, imageURL}'</code></pre>
        </div>
        <h3 style="margin-top:22px">Find references by colour</h3>
        <div class="snippet">
          <div class="snippet-head"><span class="snippet-label">shell</span><button class="copy" type="button" data-copy="ex-color">Copy</button></div>
          <pre id="ex-color"><code>curl -s "\(baseURL)/api/v1/pins?color=teal&amp;tone=deep&amp;limit=20" \\
  | jq '.pins[] | {title, colorFamilies, colorTone, imageURL}'</code></pre>
        </div>
        <h3 style="margin-top:22px">Read the full library as one file</h3>
        <div class="snippet">
          <div class="snippet-head"><span class="snippet-label">shell</span><button class="copy" type="button" data-copy="ex-library">Copy</button></div>
          <pre id="ex-library"><code>curl -s \(baseURL)/api/v1/library \\
  | jq '{stats, boards, pins: [.pins[] | {title, imageURL}]}'</code></pre>
        </div>
        <h3 style="margin-top:22px">Save every favorite image</h3>
        <div class="snippet">
          <div class="snippet-head"><span class="snippet-label">shell</span><button class="copy" type="button" data-copy="ex-download">Copy</button></div>
          <pre id="ex-download"><code>mkdir -p lore-references
curl -s "\(baseURL)/api/v1/pins?favorite=true&limit=200" \\
  | jq -r '.pins[] | [.id, .imageURL] | @tsv' \\
  | while IFS=$'\\t' read -r id url; do
      curl -s -o "lore-references/$id.png" "$url"
    done</code></pre>
        </div>
      </div>
      <div>
        <h3>Pin list response shape</h3>
        <div class="snippet">
          <div class="snippet-head"><span class="snippet-label">json</span><button class="copy" type="button" data-copy="ex-shape">Copy</button></div>
          <pre id="ex-shape"><code>{
  "count": 2,
  "total": 12,
  "offset": 0,
  "limit": 2,
  "pins": [
    {
      "id": "6f1c...",
      "title": "Aurora analytics overview",
      "board": "Web dashboards",
      "tags": ["dashboard", "dark"],
      "colors": ["#0E1117", "#E60023"],
      "colorFamily": "blue",
      "colorFamilies": ["blue", "violet"],
      "colorTone": "deep",
      "animated": false,
      "frameCount": 1,
      "imageURL": "\(baseURL)/api/v1/pins/6f1c.../image?variant=original",
      "thumbnailURL": "\(baseURL)/api/v1/pins/6f1c.../image?variant=thumb"
    }
  ]
}</code></pre>
        </div>
        <div class="note" style="margin-top:18px">
          <strong>Image URLs are absolute.</strong> Every <span class="inline-code">imageURL</span> and <span class="inline-code">thumbnailURL</span> is built from the port the server actually bound, so agents can fetch images directly without guessing the base URL.
        </div>
        <h3 style="margin-top:22px">Add a pin from a raw image</h3>
        <div class="snippet">
          <div class="snippet-head"><span class="snippet-label">shell</span><button class="copy" type="button" data-copy="ex-create-raw">Copy</button></div>
          <pre id="ex-create-raw"><code>curl -s -X POST --data-binary @shot.png \\
  -H "Content-Type: image/png" \\
  "\(baseURL)/api/v1/pins?title=Checkout%20flow&board=Mobile%20flows&tags=mobile,checkout" \\
  | jq '{id, title, board, imageURL, thumbnailURL}'</code></pre>
        </div>
        <h3 style="margin-top:22px">Add an animated GIF</h3>
        <div class="snippet">
          <div class="snippet-head"><span class="snippet-label">shell</span><button class="copy" type="button" data-copy="ex-create-gif">Copy</button></div>
          <pre id="ex-create-gif"><code>curl -s -X POST --data-binary @loading.gif \
  -H "Content-Type: image/gif" \
  "\(baseURL)/api/v1/pins?title=Loading%20loop&board=Mobile%20flows&kind=image" \
  | jq '{id, animated, frameCount, imageURL}'</code></pre>
        </div>
        <h3 style="margin-top:22px">Add a pin from JSON base64</h3>
        <div class="snippet">
          <div class="snippet-head"><span class="snippet-label">shell</span><button class="copy" type="button" data-copy="ex-create-json">Copy</button></div>
          <pre id="ex-create-json"><code>B64=$(base64 -i shot.png)
curl -s -X POST "\(baseURL)/api/v1/pins" \\
  -H "Content-Type: application/json" \\
  -d "{\\\"imageBase64\\\": \\\"$B64\\\", \\\"title\\\": \\\"Settings\\\", \\\"board\\\": \\\"Linear/Settings\\\", \\\"tags\\\": [\\\"settings\\\", \\\"linear\\\"], \\\"favorite\\\": true}" \\
  | jq '{id, title, width, height, colors, imageURL}'</code></pre>
        </div>
        <div class="note" style="margin-top:18px">
          <strong>Board hierarchy.</strong> Board names are plain strings; only <span class="inline-code">/</span> is special. A pin on <span class="inline-code">Linear/Settings</span> appears under the <span class="inline-code">Linear</span> group in Lore's sidebar, next to <span class="inline-code">Linear/Onboarding</span>. Groups are collapsed by default, and filtering still matches the full board string — URL-encode the slash as <span class="inline-code">%2F</span> in query strings. When capturing screenshots for a product, prefix the board with the product name and keep one nesting level.
        </div>
        <h3 style="margin-top:22px">Update pin metadata</h3>
        <div class="snippet">
          <div class="snippet-head"><span class="snippet-label">shell</span><button class="copy" type="button" data-copy="ex-update">Copy</button></div>
          <pre id="ex-update"><code>curl -s -X PATCH "\(baseURL)/api/v1/pins/&lt;pin-id&gt;" \\
  -H "Content-Type: application/json" \\
  -d '{"note": null, "board": "Linear/Onboarding", "favorite": true}' \\
  | jq '{id, title, board, note, favorite, updatedAt}'</code></pre>
        </div>
        <div class="note" style="margin-top:18px">
          <strong>Metadata edits can be disabled.</strong> In Lore, open <em>Settings → Agent API</em> and turn off <em>Allow metadata edits</em>. PATCH then returns <span class="inline-code">403 metadata_edits_disabled</span> while every read endpoint keeps working. Editing in the app is never affected.
        </div>
      </div>
    </div>
  </section>

  <section class="section" id="data-model">
    <div class="section-head"><h2>Pin data model</h2></div>
    <p class="section-sub">An enriched pin contains every field the app persists, plus two absolute URLs. The API never exposes filesystem paths. Uploaded pins store the original image under <span class="inline-code">Images/</span> and a max-1200px JPEG thumbnail under <span class="inline-code">Thumbnails/</span>.</p>
    <div class="table-wrap">
      <table>
        <thead><tr><th>Field</th><th>Type</th><th>Notes</th></tr></thead>
        <tbody>
          <tr><td><code>id</code></td><td><code>string</code></td><td>Stable UUID. Use it for detail and image requests.</td></tr>
          <tr><td><code>title</code></td><td><code>string</code></td><td>Human-readable pin name.</td></tr>
          <tr><td><code>note</code></td><td><code>string</code></td><td>Design note an agent can use as a brief.</td></tr>
          <tr><td><code>image</code></td><td><code>string</code></td><td>Library-relative image path, e.g. <code>Images/aurora.png</code>.</td></tr>
          <tr><td><code>thumbnail</code></td><td><code>string | null</code></td><td>Library-relative thumbnail path, or <code>null</code>.</td></tr>
          <tr><td><code>imageURL</code></td><td><code>string | null</code></td><td>Absolute loopback URL for the original image.</td></tr>
          <tr><td><code>thumbnailURL</code></td><td><code>string | null</code></td><td>Absolute loopback URL for the thumbnail; <code>null</code> if the pin has none.</td></tr>
          <tr><td><code>width</code>, <code>height</code></td><td><code>integer</code></td><td>Pixel dimensions of the original image.</td></tr>
          <tr><td><code>fileSize</code></td><td><code>integer</code></td><td>Original image size in bytes.</td></tr>
          <tr><td><code>createdAt</code>, <code>updatedAt</code></td><td><code>string</code></td><td>ISO 8601 timestamps.</td></tr>
          <tr><td><code>tags</code></td><td><code>string[]</code></td><td>Lower-case filter labels.</td></tr>
          <tr><td><code>board</code></td><td><code>string</code></td><td>Board the pin belongs to. Use <code>Product/Screen</code> to nest under a product group, e.g. <code>Linear/Settings</code>.</td></tr>
          <tr><td><code>sourceURL</code>, <code>sourceLabel</code></td><td><code>string | null</code></td><td>Original inspiration URL and label, when known.</td></tr>
          <tr><td><code>colors</code></td><td><code>string[]</code></td><td>Dominant palette as <code>#RRGGBB</code> strings (up to 5).</td></tr>
          <tr><td><code>colorFamily</code></td><td><code>string</code></td><td>Leading hue family: <code>neutral</code>, <code>red</code>, <code>orange</code>, <code>yellow</code>, <code>green</code>, <code>teal</code>, <code>blue</code>, <code>violet</code>, <code>pink</code>, or <code>brown</code>.</td></tr>
          <tr><td><code>colorFamilies</code></td><td><code>string[]</code></td><td>Every meaningful detected family, ordered by coverage. A teal-and-yellow pin lists both.</td></tr>
          <tr><td><code>colorTone</code></td><td><code>string</code></td><td>Auto-detected tonal character: <code>light</code>, <code>pastel</code>, <code>vivid</code>, <code>muted</code>, or <code>deep</code>.</td></tr>
          <tr><td><code>animated</code></td><td><code>boolean</code></td><td>True when the original image has multiple frames, such as an animated GIF.</td></tr>
          <tr><td><code>frameCount</code></td><td><code>integer</code></td><td>Frame count of the original; <code>1</code> for still images.</td></tr>
          <tr><td><code>favorite</code></td><td><code>boolean</code></td><td>Whether the pin is marked as a favorite.</td></tr>
          <tr><td><code>kind</code></td><td><code>string</code></td><td>Pin kind, e.g. <code>screenshot</code>.</td></tr>
        </tbody>
      </table>
    </div>
  </section>

  <section class="section" id="agents">
    <div class="section-head"><h2>Agent setup</h2></div>
    <p class="section-sub">Give a coding agent the base URL and a short workflow. No SDK, MCP server, or authentication is required.</p>
    <div class="two-col">
      <div>
        <h3>Drop-in instruction block</h3>
        <p class="muted">Paste this into <span class="inline-code">AGENTS.md</span>, <span class="inline-code">CLAUDE.md</span>, or a Cursor rules file.</p>
        <div class="snippet">
          <div class="snippet-head"><span class="snippet-label">markdown</span><button class="copy" type="button" data-copy="agents-block">Copy</button></div>
          <pre id="agents-block"><code>## Lore design reference API

Lore runs a local HTTP API at \(baseURL) that serves the user's
pinned UI screenshots. Use it before writing UI code.

- Health:      GET /health
- Context:     GET /api/v1/context?board=&amp;tag=&amp;color=&amp;tone=   (markdown, paste into your prompt)
- Pins:        GET /api/v1/pins?q=&amp;tag=&amp;board=&amp;color=&amp;tone=&amp;favorite=&amp;kind=&amp;sort=&amp;limit=&amp;offset=
- Color:       color ∈ neutral, red, orange, yellow, green, teal, blue, violet, pink, brown, multicolor
- Tone:        tone ∈ light, pastel, vivid, muted, deep
- Pin:         GET /api/v1/pins/{id}
- Image:       GET /api/v1/pins/{id}/image?variant=original|thumb
- Library:     GET /api/v1/library
- Boards:      GET /api/v1/boards  (a "/" in a board name nests it under a group)
- Add pin:     POST /api/v1/pins   (JSON imageBase64, or raw image/* body with query metadata)
- Update pin:  PATCH /api/v1/pins/{id}   (title, note, board, tags, source, favorite, kind; null clears)
- Discovery:   GET /openapi.json and GET /llms.txt

Fetch /api/v1/context first, choose 1-2 reference pins, inspect their
imageURLs, then reproduce the layout, spacing, typography, and palette.
Do not invent image URLs; always use the absolute URLs from the API.

When you capture screenshots for a product, name the board
"&lt;Product&gt;/&lt;Screen&gt;" — for example Linear/Settings — and include the
product name in the title (e.g. "Settings — Linear"). Lore files those
pins under the product group in the sidebar, so the library stays tidy.</code></pre>
        </div>
      </div>
      <div>
        <h3>Example prompts</h3>
        <div class="prompt">
          <span class="prompt-label">Build from a board</span>
          <p>"Query Lore's design context for the board Web dashboards, pick the two most relevant references, and build the analytics overview page in SwiftUI. Match the spacing, type scale, and colour palette of the references, not just the layout."</p>
        </div>
        <div class="prompt">
          <span class="prompt-label">Capture into the library</span>
          <p>"Use Lore to add this settings screenshot to the board Linear/Settings with the tags settings and onboarding, then fetch its imageURL and use it as the reference for the empty-state screen."</p>
        </div>
        <div class="prompt">
          <span class="prompt-label">File captures by product</span>
          <p>"Capture these five screenshots, add them to Lore with board names like Linear/Settings and Linear/Onboarding, then pull the Linear context and restyle our app to match the product family."</p>
        </div>
        <div class="prompt">
          <span class="prompt-label">Extract a palette</span>
          <p>"List Lore pins tagged editorial, read their colors and thumbnails, and produce a consistent four-colour palette with hex values and suggested usage."</p>
        </div>
        <div class="note">
          <strong>Tip:</strong> the API is local. Read endpoints are read-only, while <span class="inline-code">POST /api/v1/pins</span> adds references and <span class="inline-code">PATCH /api/v1/pins/{id}</span> fixes their metadata (the owner can disable PATCH in Settings). The agent only needs <span class="inline-code">curl</span> (or any HTTP client) and access to <span class="inline-code">127.0.0.1</span>.
        </div>
      </div>
    </div>
  </section>

  <section class="section" id="errors">
    <div class="section-head"><h2>Errors</h2></div>
    <p class="section-sub">Every non-2xx response is JSON with a stable error code and a human-readable message. HTTP status codes used: 400, 403, 404, 405, 413, 415, 500.</p>
    <div class="two-col">
      <div class="snippet">
        <div class="snippet-head"><span class="snippet-label">error envelope</span><button class="copy" type="button" data-copy="err-shape">Copy</button></div>
        <pre id="err-shape"><code>{
  "error": {
    "code": "pin_not_found",
    "message": "No pin with id \"6f1c...\" exists in the Lore library."
  }
}</code></pre>
      </div>
      <div class="table-wrap">
        <table>
          <thead><tr><th>Status</th><th>Codes</th></tr></thead>
          <tbody>
            <tr><td><code>400</code></td><td><code>bad_request</code>, <code>invalid_parameter</code>, <code>invalid_percent_encoding</code>, <code>invalid_content_length</code>, <code>request_header_too_large</code>, <code>unsupported_http_version</code>, <code>invalid_json</code>, <code>missing_image</code>, <code>invalid_image_data</code>, <code>invalid_metadata</code></td></tr>
            <tr><td><code>404</code></td><td><code>not_found</code>, <code>pin_not_found</code>, <code>image_not_found</code></td></tr>
            <tr><td><code>403</code></td><td><code>metadata_edits_disabled</code> — metadata edits are turned off in Settings</td></tr>
            <tr><td><code>405</code></td><td><code>method_not_allowed</code> — includes an <code>Allow</code> header</td></tr>
            <tr><td><code>413</code></td><td><code>request_body_too_large</code> — upload bodies are limited to 20 MiB</td></tr>
            <tr><td><code>415</code></td><td><code>unsupported_media_type</code> — send <code>application/json</code> or an <code>image/*</code> body</td></tr>
            <tr><td><code>500</code></td><td><code>library_unavailable</code>, <code>library_corrupt</code>, <code>storage_failure</code>, <code>internal_error</code></td></tr>
          </tbody>
        </table>
      </div>
    </div>
  </section>

  <section class="section" id="security">
    <div class="section-head"><h2>Security &amp; behaviour</h2></div>
    <ul class="list">
      <li><strong>Loopback only.</strong> The listener binds to <span class="inline-code">127.0.0.1</span>; it is not reachable from other devices on the network.</li>
      <li><strong>No authentication.</strong> Any local process can read the library. That is the intended contract for a local design tool; avoid port-forwarding or proxying the API.</li>
      <li><strong>Two write endpoints.</strong> <span class="inline-code">POST /api/v1/pins</span> validates images with ImageIO and appends a pin; <span class="inline-code">PATCH /api/v1/pins/{id}</span> rewrites only metadata and can be disabled in Settings. Both update <span class="inline-code">library.json</span> atomically. Read endpoints remain read-only; there are no cookies or session state.</li>
      <li><strong>Local writes only.</strong> Any process that can reach loopback can add pins. Do not port-forward or proxy the API; it is designed for trusted local workflows.</li>
      <li><strong>Path-safe image serving.</strong> Only files referenced by pin entries and resolvable inside the library root are streamed. Absolute paths, dot-segment escapes, and symlinks that leave the root return a 404 JSON error.</li>
      <li><strong>Fresh reads.</strong> <span class="inline-code">library.json</span> is decoded on every request, so edits made in the app or through the API appear immediately without restarting the server.</li>
      <li><strong>Connection handling.</strong> One request per connection, <span class="inline-code">Connection: close</span>, a 32&nbsp;KB request-head limit, a 20&nbsp;MiB upload limit on <span class="inline-code">POST /api/v1/pins</span>, and correct <span class="inline-code">Content-Length</span> on every response.</li>
    </ul>
  </section>
</main>
<footer>
  <div class="footer-inner">
    <div><strong>Lore Agent API v1</strong> · Served from LoreAgentKit 1.1.0 · 127.0.0.1:\(port)</div>
    <div>Machine-readable: <a href="/openapi.json">openapi.json</a> · <a href="/llms.txt">llms.txt</a> · <a href="/health">health</a></div>
  </div>
</footer>
<script>
(function () {
  function fallback(text) {
    var area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "");
    area.style.position = "fixed";
    area.style.top = "-1000px";
    document.body.appendChild(area);
    area.select();
    try { document.execCommand("copy"); } catch (error) {}
    document.body.removeChild(area);
  }
  var buttons = document.querySelectorAll("[data-copy]");
  for (var index = 0; index < buttons.length; index++) {
    buttons[index].addEventListener("click", function () {
      var target = document.getElementById(this.getAttribute("data-copy"));
      if (!target) { return; }
      var text = target.textContent.trim();
      var button = this;
      var done = function () {
        button.textContent = "Copied";
        button.classList.add("copied");
        window.setTimeout(function () {
          button.textContent = "Copy";
          button.classList.remove("copied");
        }, 1400);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, function () {
          fallback(text);
          done();
        });
      } else {
        fallback(text);
        done();
      }
    });
  }
})();
</script>
</body>
</html>
"""
    }
}
