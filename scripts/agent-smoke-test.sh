#!/usr/bin/env bash
#
# Canta Agent API smoke test
# --------------------------
# Builds CantaAgentKit, compiles a tiny standalone harness around the real
# server implementation, generates a temporary fixture library, starts the
# server on an ephemeral loopback port, and black-box tests every public
# endpoint with python3.
#
# Usage:
#   ./scripts/agent-smoke-test.sh            # build + HTTP smoke checks
#   ./scripts/agent-smoke-test.sh --tests    # also run the Swift Testing suite
#
# Requires: swift, python3. The fixture lives under .build/agent-smoke and is
# removed on exit. The test never touches the real Canta library.
#
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.build/agent-smoke"
FIXTURE="$WORK/fixture"
LIBRARY="$FIXTURE/library"
CACHE="$ROOT/.build/agent-smoke-cache"
TMP="$WORK/tmp"
PORT_FILE="$WORK/port.txt"
SERVER_LOG="$WORK/server.log"
HARNESS="$WORK/harness/canta-agent-smoke"
RUN_TESTS=0
if [ "$#" -ge 1 ] && [ "$1" = "--tests" ]; then
    RUN_TESTS=1
fi
KEEP_SMOKE_WORK="$(printenv KEEP_SMOKE_WORK 2>/dev/null || true)"
if [ -z "$KEEP_SMOKE_WORK" ]; then
    KEEP_SMOKE_WORK=0
fi

rm -rf "$WORK"
mkdir -p "$LIBRARY/Images" "$LIBRARY/Thumbnails" "$CACHE/clang" "$CACHE/swift" "$TMP" "$WORK/harness" "$ROOT/.build/spm-cache"
export CLANG_MODULE_CACHE_PATH="$CACHE/clang"
export SWIFT_MODULECACHE_PATH="$CACHE/swift"
export TMPDIR="$TMP"

SERVER_PID=""
cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null
        wait "$SERVER_PID" 2>/dev/null
    fi
    if [ "$KEEP_SMOKE_WORK" = "1" ]; then
        echo "Smoke-test work directory kept at $WORK"
    else
        rm -rf "$WORK"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "==> Building CantaAgentKit"
if ! swift build --target CantaAgentKit --disable-sandbox --manifest-cache local \
        --cache-path "$ROOT/.build/spm-cache" --scratch-path "$ROOT/.build" > "$WORK/build.log" 2>&1; then
    echo "    swift build failed:"
    tail -30 "$WORK/build.log"
    exit 1
fi
echo "    ok"

echo "==> Generating fixture library"
python3 - "$FIXTURE" <<'PY'
import base64
import json
import os
import sys

root = sys.argv[1]
library = os.path.join(root, "library")
secret = os.path.join(root, "secret.txt")
with open(secret, "w", encoding="utf-8") as handle:
    handle.write("CANTA_SMOKE_TRAVERSAL_SECRET_DO_NOT_SERVE\n")

png = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
)
jpeg = base64.b64decode(
    "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD3+iiigD//2Q=="
)

files = {
    "Images/aurora.png": png,
    "Thumbnails/aurora.jpg": jpeg,
    "Images/ledger.png": png,
    "Images/noema.png": png,
    "Thumbnails/noema.jpg": jpeg,
    "Images/zephyr.png": png,
}
for relative, data in files.items():
    with open(os.path.join(library, relative), "wb") as handle:
        handle.write(data)

escape_link = os.path.join(library, "Images", "escape.png")
try:
    os.remove(escape_link)
except FileNotFoundError:
    pass
os.symlink("../../secret.txt", escape_link)

def pin(identifier, title, image, thumbnail, board, tags, favorite, created):
    return {
        "id": identifier,
        "title": title,
        "note": "Fixture design note for " + title + ".",
        "image": image,
        "thumbnail": thumbnail,
        "width": 1440,
        "height": 900,
        "fileSize": len(png),
        "createdAt": created,
        "updatedAt": created,
        "tags": tags,
        "board": board,
        "sourceURL": "https://example.com/reference" if favorite else None,
        "sourceLabel": "Dribbble" if favorite else "Canta Seed",
        "colors": ["#0E1117", "#E60023"],
        "favorite": favorite,
        "kind": "screenshot",
    }

pins = [
    pin("11111111-1111-4111-8111-111111111111", "Aurora analytics overview",
        "Images/aurora.png", "Thumbnails/aurora.jpg", "Web dashboards",
        ["dashboard", "analytics", "dark"], True, "2026-11-02T10:24:00Z"),
    pin("22222222-2222-4222-8222-222222222222", "Ledger onboarding",
        "Images/ledger.png", None, "Mobile flows",
        ["mobile", "onboarding"], False, "2026-11-05T09:00:00Z"),
    pin("33333333-3333-4333-8333-333333333333", "Noema field notes",
        "Images/noema.png", "Thumbnails/noema.jpg", "Editorial",
        ["editorial", "typography"], False, "2026-11-09T12:30:00Z"),
    pin("44444444-4444-4444-8444-444444444444", "Zephyr pricing page",
        "Images/zephyr.png", None, "Landing pages",
        ["landing", "pricing"], False, "2026-11-12T18:45:00Z"),
]
hostile = pin("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "Hostile relative",
              "../../secret.txt", None, "Web dashboards", ["unsafe"], False, "2026-11-13T00:00:00Z")
absolute = pin("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "Hostile absolute",
               "/etc/passwd", None, "Web dashboards", ["unsafe"], False, "2026-11-13T00:00:00Z")
symlinked = pin("cccccccc-cccc-4ccc-8ccc-cccccccccccc", "Hostile symlink",
                "Images/escape.png", None, "Web dashboards", ["unsafe"], False, "2026-11-13T00:00:00Z")
pins.extend([hostile, absolute, symlinked])

with open(os.path.join(library, "library.json"), "w", encoding="utf-8") as handle:
    json.dump({"version": 1, "pins": pins}, handle, indent=2)

with open(os.path.join(root, "expected-png.bin"), "wb") as handle:
    handle.write(png)
with open(os.path.join(root, "expected-jpeg.bin"), "wb") as handle:
    handle.write(jpeg)
with open(os.path.join(root, "secret-marker.txt"), "w", encoding="utf-8") as handle:
    handle.write("CANTA_SMOKE_TRAVERSAL_SECRET_DO_NOT_SERVE")
PY
echo "    ok"

echo "==> Compiling standalone smoke harness"
cat > "$WORK/harness/main.swift" <<'SWIFT'
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: harness <library-root> <port-file>\n".utf8))
    exit(2)
}
let libraryRoot = URL(fileURLWithPath: arguments[1], isDirectory: true)
let portFile = URL(fileURLWithPath: arguments[2])
let server = CantaAgentServer(config: AgentServerConfig(port: 0, libraryRoot: libraryRoot))
server.onStatusChange = { status in
    switch status {
    case .running(let port):
        try? "\(port)".write(to: portFile, atomically: true, encoding: .utf8)
        print("CantaAgentSmoke listening on 127.0.0.1:\(port)")
        fflush(stdout)
    case .failed(let message):
        FileHandle.standardError.write(Data(("CantaAgentSmoke failed: " + message + "\n").utf8))
    default:
        break
    }
}
server.start()
let deadline = Date().addingTimeInterval(15)
while Date() < deadline {
    if case .running = server.status { break }
    Thread.sleep(forTimeInterval: 0.02)
}
if case .running = server.status {
    while true { Thread.sleep(forTimeInterval: 1) }
}
FileHandle.standardError.write(Data("CantaAgentSmoke server did not start\n".utf8))
exit(1)
SWIFT

if ! swiftc -swift-version 5 -module-cache-path "$CACHE/swift-modules" \
        "$ROOT"/Sources/CantaAgentKit/*.swift "$WORK/harness/main.swift" \
        -o "$HARNESS" > "$WORK/compile.log" 2>&1; then
    echo "    harness compilation failed:"
    tail -30 "$WORK/compile.log"
    exit 1
fi
echo "    ok"

echo "==> Starting server on an ephemeral loopback port"
"$HARNESS" "$LIBRARY" "$PORT_FILE" > "$SERVER_LOG" 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 300); do
    if [ -s "$PORT_FILE" ]; then
        break
    fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "    server exited early:"
        cat "$SERVER_LOG"
        exit 1
    fi
    sleep 0.05
done
PORT="$(cat "$PORT_FILE" 2>/dev/null)"
if [ -z "$PORT" ]; then
    echo "    server did not report a port:"
    cat "$SERVER_LOG"
    exit 1
fi
BASE="http://127.0.0.1:$PORT"
echo "    listening on $BASE"

echo "==> Running HTTP smoke checks"
python3 - "$BASE" "$FIXTURE" "$LIBRARY" <<'PY'
import json
import os
import sys
import urllib.error
import urllib.request

base, fixture, library = sys.argv[1:4]
png = open(os.path.join(fixture, "expected-png.bin"), "rb").read()
jpeg = open(os.path.join(fixture, "expected-jpeg.bin"), "rb").read()
secret = open(os.path.join(fixture, "secret-marker.txt"), "r", encoding="utf-8").read().strip()
port = int(base.rsplit(":", 1)[1])

failures = 0
checks = 0


def record(label, ok, detail=""):
    global failures, checks
    checks += 1
    if ok:
        print("    PASS  " + label)
    else:
        failures += 1
        print("    FAIL  " + label + (("  (" + detail + ")") if detail else ""))


def request(path, method="GET"):
    req = urllib.request.Request(base + path, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            return response.status, {k.lower(): v for k, v in response.headers.items()}, response.read()
    except urllib.error.HTTPError as error:
        return error.code, {k.lower(): v for k, v in error.headers.items()}, error.read()


def request_json(path):
    status, headers, body = request(path)
    try:
        payload = json.loads(body)
    except Exception:
        payload = None
    return status, headers, payload, body


def expect_json(label, path, status=200):
    actual_status, headers, payload, body = request_json(path)
    record(label + " -> HTTP " + str(status), actual_status == status, "got " + str(actual_status) + ": " + body[:200].decode("utf-8", "replace"))
    record(label + " content-type JSON", "application/json" in headers.get("content-type", ""), headers.get("content-type", ""))
    record(label + " valid JSON", payload is not None, "body: " + body[:200].decode("utf-8", "replace"))
    return payload if payload is not None else {}


print("  [health]")
health = expect_json("GET /health", "/health")
record("health status field", health.get("status") == "ok", str(health.get("status")))
record("health app field", health.get("app") == "Canta", str(health.get("app")))
record("health api field", health.get("api") == "v1", str(health.get("api")))
record("health version present", isinstance(health.get("version"), str) and health.get("version") != "", str(health.get("version")))
record("health pinCount == 7", health.get("pinCount") == 7, str(health.get("pinCount")))
record("health port == bound port", health.get("port") == port, str(health.get("port")))
alias = expect_json("GET /api/v1/health", "/api/v1/health")
record("health alias matches", alias == health)

print("  [library]")
library_payload = expect_json("GET /api/v1/library", "/api/v1/library")
stats = library_payload.get("stats", {})
record("library app", library_payload.get("app") == "Canta", str(library_payload.get("app")))
record("library stats.pins == 7", stats.get("pins") == 7, str(stats.get("pins")))
record("library stats.boards == 4", stats.get("boards") == 4, str(stats.get("boards")))
record("library stats.favorites == 1", stats.get("favorites") == 1, str(stats.get("favorites")))
pins = library_payload.get("pins", [])
record("library pins == 7", len(pins) == 7, str(len(pins)))
aurora = next((pin for pin in pins if pin.get("id") == "11111111-1111-4111-8111-111111111111"), {})
expected_original = base + "/api/v1/pins/11111111-1111-4111-8111-111111111111/image?variant=original"
expected_thumb = base + "/api/v1/pins/11111111-1111-4111-8111-111111111111/image?variant=thumb"
record("library imageURL absolute", aurora.get("imageURL") == expected_original, str(aurora.get("imageURL")))
record("library thumbnailURL absolute", aurora.get("thumbnailURL") == expected_thumb, str(aurora.get("thumbnailURL")))
ledger = next((pin for pin in pins if pin.get("id") == "22222222-2222-4222-8222-222222222222"), {})
record("library null thumbnailURL for pin without thumbnail", ledger.get("thumbnailURL") is None, str(ledger.get("thumbnailURL")))
record("library does not leak filesystem root", library not in json.dumps(library_payload), "filesystem path leaked")

print("  [pins]")
pins_payload = expect_json("GET /api/v1/pins", "/api/v1/pins?limit=2&offset=1")
record("pins envelope count", pins_payload.get("count") == 2, str(pins_payload.get("count")))
record("pins envelope total", pins_payload.get("total") == 7, str(pins_payload.get("total")))
record("pins envelope offset", pins_payload.get("offset") == 1, str(pins_payload.get("offset")))
record("pins envelope limit", pins_payload.get("limit") == 2, str(pins_payload.get("limit")))
tagged = expect_json("GET /api/v1/pins?tag=dashboard", "/api/v1/pins?tag=dashboard")
record("tag filter total", tagged.get("total") == 1, str(tagged.get("total")))
favorite = expect_json("GET /api/v1/pins?favorite=true", "/api/v1/pins?favorite=true")
record("favorite filter total", favorite.get("total") == 1, str(favorite.get("total")))
search = expect_json("GET /api/v1/pins?q=onboarding", "/api/v1/pins?q=onboarding")
record("search returns ledger pin", search.get("total") == 1 and search.get("pins", [{}])[0].get("title") == "Ledger onboarding", str(search.get("total")))
titles = expect_json("GET /api/v1/pins?sort=title", "/api/v1/pins?sort=title")
ordered = [pin.get("title") for pin in titles.get("pins", []) if not str(pin.get("title", "")).startswith("Hostile")]
record("sort=title order", ordered[:4] == ["Aurora analytics overview", "Ledger onboarding", "Noema field notes", "Zephyr pricing page"], str(ordered[:4]))
detail = expect_json("GET /api/v1/pins/{id}", "/api/v1/pins/11111111-1111-4111-8111-111111111111")
record("pin detail id", detail.get("id") == "11111111-1111-4111-8111-111111111111", str(detail.get("id")))
record("pin detail note", isinstance(detail.get("note"), str) and detail.get("note") != "", str(detail.get("note")))

print("  [images]")
status, headers, body = request("/api/v1/pins/11111111-1111-4111-8111-111111111111/image")
record("original image status", status == 200, str(status))
record("original content-type image/png", headers.get("content-type") == "image/png", headers.get("content-type", ""))
record("original bytes match fixture", body == png, str(len(body)) + " bytes")
status, headers, body = request("/api/v1/pins/11111111-1111-4111-8111-111111111111/image?variant=thumb")
record("thumbnail content-type image/jpeg", status == 200 and headers.get("content-type") == "image/jpeg", headers.get("content-type", ""))
record("thumbnail bytes match fixture", body == jpeg, str(len(body)) + " bytes")
status, headers, body = request("/api/v1/pins/22222222-2222-4222-8222-222222222222/image?variant=thumb")
record("thumbnail falls back to original", status == 200 and body == png and headers.get("content-type") == "image/png", headers.get("content-type", ""))
status, headers, body = request("/api/v1/pins/11111111-1111-4111-8111-111111111111/image", method="HEAD")
record("HEAD image status", status == 200, str(status))
record("HEAD image content-length", headers.get("content-length") == str(len(png)), headers.get("content-length", ""))
record("HEAD image has no body", body == b"", str(len(body)) + " bytes")

print("  [errors]")
for path, expected_status, expected_code in [
    ("/api/v1/pins/not-a-pin", 404, "pin_not_found"),
    ("/api/v1/pins/11111111-1111-4111-8111-111111111111/image?variant=huge", 400, "invalid_parameter"),
    ("/api/v1/pins?limit=0", 400, "invalid_parameter"),
    ("/api/v1/nope", 404, "not_found"),
]:
    payload = expect_json("GET " + path, path, status=expected_status)
    error = payload.get("error", {})
    record("error code for " + path, error.get("code") == expected_code, str(error.get("code")))
    record("error message for " + path, isinstance(error.get("message"), str) and error.get("message") != "", str(error.get("message")))

status, headers, body = request("/api/v1/library", method="POST")
record("POST returns 405", status == 405, str(status))
record("405 includes Allow", "GET" in headers.get("allow", ""), headers.get("allow", ""))
record("405 JSON code", b"method_not_allowed" in body, body[:150].decode("utf-8", "replace"))

print("  [traversal protection]")
for hostile_id, label in [
    ("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "relative escape"),
    ("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "absolute path"),
    ("cccccccc-cccc-4ccc-8ccc-cccccccccccc", "symlink escape"),
]:
    status, headers, body = request("/api/v1/pins/" + hostile_id + "/image")
    text = body.decode("utf-8", "replace")
    record("traversal blocked: " + label, status == 404 and "image_not_found" in text, str(status) + " " + text[:120])
    record("traversal did not leak secret: " + label, secret not in text and "root:" not in text)

print("  [discovery]")
status, headers, body = request("/docs")
docs = body.decode("utf-8", "replace")
record("/docs status", status == 200, str(status))
record("/docs is HTML", "text/html" in headers.get("content-type", ""), headers.get("content-type", ""))
record("/docs uses Canta accent", "#E60023" in docs)
record("/docs links OpenAPI", "/openapi.json" in docs)
record("/docs has no external CDN", "https://cdn" not in docs and "fonts.googleapis" not in docs and "@import" not in docs)
record("/docs mentions llms.txt", "/llms.txt" in docs)

openapi_payload = expect_json("GET /openapi.json", "/openapi.json")
record("OpenAPI version 3.1.0", openapi_payload.get("openapi") == "3.1.0", str(openapi_payload.get("openapi")))
paths = openapi_payload.get("paths", {})
required_paths = ["/health", "/api/v1/library", "/api/v1/pins", "/api/v1/pins/{id}", "/api/v1/pins/{id}/image", "/api/v1/context", "/docs", "/openapi.json", "/llms.txt"]
record("OpenAPI required paths", all(path in paths for path in required_paths), str(sorted(set(required_paths) - set(paths.keys()))))
servers = openapi_payload.get("servers", [])
record("OpenAPI server URL", bool(servers) and servers[0].get("url") == base, str(servers[:1]))

status, headers, body = request("/llms.txt")
llms = body.decode("utf-8", "replace")
record("/llms.txt status", status == 200, str(status))
record("/llms.txt plain text", "text/plain" in headers.get("content-type", ""), headers.get("content-type", ""))
record("/llms.txt headline", llms.startswith("# Canta Agent API"))
record("/llms.txt absolute links", base + "/api/v1/pins" in llms)

status, headers, body = request("/")
record("/ landing status", status == 200, str(status))
record("/ links to docs", b"/docs" in body)

print("  [CORS and methods]")
status, headers, body = request("/api/v1/pins", method="OPTIONS")
record("OPTIONS preflight 204", status == 204, str(status))
record("CORS allow origin", headers.get("access-control-allow-origin") == "*", headers.get("access-control-allow-origin", ""))
record("CORS allow methods", "GET" in headers.get("access-control-allow-methods", ""), headers.get("access-control-allow-methods", ""))
status, headers, body = request("/health")
record("GET CORS header", headers.get("access-control-allow-origin") == "*", headers.get("access-control-allow-origin", ""))
record("GET connection close", headers.get("connection") == "close", headers.get("connection", ""))

print("")
if failures:
    print("SMOKE TEST FAILED: " + str(failures) + " of " + str(checks) + " checks failed")
    sys.exit(1)
print("SMOKE TEST PASSED: " + str(checks) + " checks")
PY
SMOKE_STATUS=$?

if [ "$RUN_TESTS" = "1" ]; then
    echo "==> Running Swift Testing suite"
    FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
    INTEROP="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
    if [ -d "$FRAMEWORKS/Testing.framework" ]; then
        swift test --disable-sandbox --manifest-cache local \
            --cache-path "$WORK/spm-cache" --scratch-path "$WORK/swift-test" \
            -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
            -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
            -Xlinker -rpath -Xlinker "$INTEROP" || exit 1
    else
        swift test --disable-sandbox --manifest-cache local \
            --cache-path "$WORK/spm-cache" --scratch-path "$WORK/swift-test" || exit 1
    fi
fi

if [ "$SMOKE_STATUS" -ne 0 ]; then
    exit "$SMOKE_STATUS"
fi
echo "Agent API smoke test complete."
