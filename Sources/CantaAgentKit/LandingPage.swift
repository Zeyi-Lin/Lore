import Foundation

/// A tiny landing page at <code>/</code> that points humans at the docs.
enum LandingPage {
    static func html(baseURL: String) -> String {
        let port = baseURL.split(separator: ":").last.map(String.init) ?? "4242"
        return """
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Canta Agent API</title>
<meta name="description" content="Canta's local, loopback-only design library API: browse pins, stream images, and add new references from agent workflows.">
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Crect width='64' height='64' rx='16' fill='%23E60023'/%3E%3Crect x='14' y='20' width='30' height='24' rx='5' fill='white'/%3E%3Ccircle cx='45' cy='23' r='6' fill='%23161412'/%3E%3C/svg%3E">
<style>
  :root { --ink: #161412; --muted: #6f6a64; --line: #e8e2dc; --soft: #faf7f4; --accent: #e60023; }
  * { box-sizing: border-box; }
  body {
    margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 32px;
    background: #fff; color: var(--ink);
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    line-height: 1.6; -webkit-font-smoothing: antialiased;
  }
  main { max-width: 560px; width: 100%; }
  .mark { width: 56px; height: 56px; border-radius: 16px; margin-bottom: 26px; }
  h1 { font-size: 2rem; letter-spacing: -0.035em; margin: 0 0 10px; }
  p { color: var(--muted); margin: 0 0 22px; }
  .links { display: grid; gap: 10px; }
  a.card {
    display: flex; justify-content: space-between; align-items: center; gap: 16px;
    text-decoration: none; color: var(--ink); background: var(--soft);
    border: 1px solid var(--line); border-radius: 16px; padding: 15px 18px; font-weight: 600;
  }
  a.card span.code { font-family: ui-monospace, Menlo, monospace; font-size: 13px; color: var(--muted); font-weight: 500; }
  a.card:hover { border-color: var(--accent); color: var(--accent); }
  footer { margin-top: 26px; color: var(--muted); font-size: 13px; }
  code { font-family: ui-monospace, Menlo, monospace; background: var(--soft); border: 1px solid var(--line); border-radius: 6px; padding: 1px 6px; font-size: 12.5px; }
</style>
</head>
<body>
<main>
  <svg class="mark" viewBox="0 0 56 56" aria-hidden="true">
    <rect width="56" height="56" rx="15" fill="#E60023"/>
    <rect x="13" y="18" width="23" height="21" rx="4" fill="#fff"/>
    <circle cx="43" cy="17" r="4.6" fill="#161412"/>
  </svg>
  <h1>Canta Agent API</h1>
  <p>Your pinned design screenshots, served locally to coding agents on <code>127.0.0.1:\(port)</code>. Read and write, loopback-only, no authentication.</p>
  <nav class="links" aria-label="API resources">
    <a class="card" href="/docs"><span>Documentation &amp; quickstart</span><span class="code">/docs</span></a>
    <a class="card" href="/llms.txt"><span>llms.txt index</span><span class="code">/llms.txt</span></a>
    <a class="card" href="/openapi.json"><span>OpenAPI 3.1 spec</span><span class="code">/openapi.json</span></a>
    <a class="card" href="/api/v1/library"><span>Full library JSON</span><span class="code">/api/v1/library</span></a>
    <a class="card" href="/api/v1/context"><span>Design context for agents</span><span class="code">/api/v1/context</span></a>
    <a class="card" href="/api/v1/pins"><span>Add a pin (POST, JSON or raw image)</span><span class="code">/api/v1/pins</span></a>
    <a class="card" href="/health"><span>Health</span><span class="code">/health</span></a>
  </nav>
  <footer>Canta · Agent API v1 · <a href="/docs">docs</a></footer>
</main>
</body>
</html>
"""
    }
}
