#!/usr/bin/env bash
# Measures how expensive one window-resize layout pass is.
#
#   ./scripts/resize-bench.sh                # 1 000 pins
#   ./scripts/resize-bench.sh --pins 5000
#   ./scripts/resize-bench.sh --pins 1000 --build
#
# The app is launched with a synthetic library built from the shipped seed
# images, then the window width is swept the way a drag does. `layout` is the
# number that matters: it is how much of a frame budget a resize frame spends
# before anything is drawn. Release builds only — debug is ~10x slower.
#
# The benchmark needs an unlocked GUI session: SwiftUI does not create the
# window while the session is inactive, and the run will time out.
set -euo pipefail
cd "$(dirname "$0")/.."

PINS=1000
BUILD=0
while [ $# -gt 0 ]; do
  case "$1" in
    --pins) PINS="${2:-1000}"; shift 2 ;;
    --build) BUILD=1; shift ;;
    *) echo "usage: $0 [--pins N] [--build]" >&2; exit 2 ;;
  esac
done

APP="$PWD/dist/Lore.app"
if [ "$BUILD" = "1" ] || [ ! -x "$APP/Contents/MacOS/Lore" ]; then
  ./scripts/build-app.sh release
fi

if pgrep -x Lore >/dev/null 2>&1; then
  echo "resize-bench: quit Lore first (the benchmark drives its own window)" >&2
  exit 2
fi

HOME_DIR="$PWD/.build/resize-bench/library-$PINS"
rm -rf "$HOME_DIR"
mkdir -p "$HOME_DIR"
cp -R Sources/Lore/Resources/Seed/Images "$HOME_DIR/Images"
cp -R Sources/Lore/Resources/Seed/Thumbnails "$HOME_DIR/Thumbnails"
python3 - "$PINS" "$HOME_DIR/library.json" <<'PY'
import json, os, sys, uuid, datetime

count = int(sys.argv[1])
out = sys.argv[2]
seed = json.load(open("Sources/Lore/Resources/Seed/seed.json"))["pins"]
order = sorted(seed, key=lambda p: p["createdAt"])
boards = ["Web dashboards", "Mobile flows", "Landing pages", "Editorial", "Linear/Settings"]
start = datetime.datetime(2026, 11, 13, 9, 12, 0)
pins = []
for i in range(count):
    template = order[i % len(order)]
    stamp = (start + datetime.timedelta(hours=i)).strftime("%Y-%m-%dT%H:%M:%SZ")
    pins.append({
        "id": str(uuid.uuid4()),
        "title": f"{template['title'].split(' — ')[0]} · reference {i}",
        "note": template["note"],
        "image": template["image"],
        "thumbnail": template["thumbnail"],
        "width": template["width"],
        "height": template["height"],
        "fileSize": template["fileSize"],
        "createdAt": stamp,
        "updatedAt": stamp,
        "tags": template["tags"],
        "board": boards[i % len(boards)],
        "colors": template["colors"],
        "favorite": i % 7 == 0,
        "kind": template["kind"],
    })
json.dump({"version": 1, "pins": pins}, open(out, "w"))
print(f"resize-bench: {count} pins in {os.path.dirname(out)}")
PY

# One app launch per attempt. SwiftUI occasionally launches without creating its
# window (the session gets busy or the previous instance is still shutting
# down), which looks like "no output" — retry rather than fail the run.
# A launch through LaunchServices (`open`) is how a user starts the app, and it
# is the only reliable way to get a window when the session is busy. stdout is
# not connected in that case, so the app mirrors its report to a file.
quit_app() {
  pkill -f "Lore --resize-bench" 2>/dev/null || true
  pkill -x Lore 2>/dev/null || true
  for _ in $(seq 1 20); do
    pgrep -x Lore >/dev/null 2>&1 || break
    sleep 0.2
  done
  sleep 2
}

run_launchservices() {
  local out="${TMPDIR:-/tmp}/lore-resize-bench-$$.log"
  rm -f "$out"
  open -n "$APP" --args --resize-bench -lore.debugHome "$HOME_DIR" -lore.benchOutput "$out"
  for _ in $(seq 1 150); do
    [ -s "$out" ] && break
    sleep 1
  done
  sleep 0.3
  grep "RESIZE_BENCH" "$out" 2>/dev/null
}

run_direct() {
  local out="${TMPDIR:-/tmp}/lore-resize-bench-direct-$$.log"
  : >"$out"
  "$APP/Contents/MacOS/Lore" --resize-bench -lore.debugHome "$HOME_DIR" >"$out" 2>&1 &
  local pid=$!
  for _ in $(seq 1 150); do
    grep -q "RESIZE_BENCH grid-relayouts" "$out" && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done
  sleep 0.3
  grep "RESIZE_BENCH" "$out"
}

for attempt in 1 2; do
  quit_app
  if run_launchservices; then exit 0; fi
  quit_app
  if run_direct; then exit 0; fi
  echo "resize-bench: attempt $attempt produced no result" >&2
done
echo "resize-bench: no result after 2 attempts (is the GUI session active?)" >&2
exit 3
