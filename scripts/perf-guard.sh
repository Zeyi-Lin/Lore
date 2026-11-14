#!/usr/bin/env bash
# Runs the data-layer benchmark against a synthetic library and fails when a
# metric regresses past its budget. Intended for local pre-push / CI checks.
#
#   ./scripts/perf-guard.sh            # 1 000 pins
#   ./scripts/perf-guard.sh --pins 5000
set -euo pipefail
cd "$(dirname "$0")/.."

PINS=1000
if [ "${1:-}" = "--pins" ]; then PINS="${2:-1000}"; fi

APP="$PWD/dist/Canta.app/Contents/MacOS/Canta"
if [ ! -x "$APP" ]; then
  APP="$PWD/.build/arm64-apple-macosx/release/Canta"
fi
if [ ! -x "$APP" ]; then
  echo "Build the app first: ./scripts/build-app.sh release" >&2
  exit 2
fi

HOME_DIR="$PWD/.build/perf-guard/library-$PINS"
rm -rf "$HOME_DIR"
mkdir -p "$HOME_DIR"
python3 - "$PINS" "$HOME_DIR/library.json" <<'PY'
import json, sys, uuid, datetime
count = int(sys.argv[1])
out = sys.argv[2]
boards = ["Web dashboards", "Mobile flows", "Landing pages", "Editorial", "Unsorted"]
words = ["atlas", "pulse", "sable", "miso", "aurora", "cadence", "terrain", "orbit"]
now = datetime.datetime(2026, 11, 13, 9, 12, 0)
pins = []
for i in range(count):
    stamp = (now + datetime.timedelta(hours=i)).strftime("%Y-%m-%dT%H:%M:%SZ")
    pins.append({
        "id": str(uuid.uuid4()),
        "title": f"Quiet {words[i % len(words)]} dashboard {i}",
        "note": "Frosted panels float on a soft gradient; 12px borders and 28px blur keep the data friendly.",
        "image": f"Images/{i}.png",
        "thumbnail": f"Thumbnails/{i}.jpg",
        "width": 1440, "height": 1000, "fileSize": 500000,
        "createdAt": stamp, "updatedAt": stamp,
        "tags": ["dark ui", "cards", "gradient"],
        "board": boards[i % len(boards)],
        "colors": ["#171412", "#FAF8F5", "#E60023"],
        "favorite": i % 7 == 0,
        "kind": "screenshot"
    })
json.dump({"version": 1, "pins": pins}, open(out, "w"))
PY

OUTPUT=$(CANTA_HOME="$HOME_DIR" CANTA_BENCH_JSON=1 "$APP" --bench 2>/dev/null | grep '^CANTA_BENCH_JSON ' | head -1 | sed 's/^CANTA_BENCH_JSON //')
if [ -z "${OUTPUT:-}" ]; then
  echo "perf-guard: benchmark produced no JSON output" >&2
  exit 3
fi

python3 - "$PINS" "$OUTPUT" <<'PY'
import json, sys
pins = int(sys.argv[1])
payload = json.loads(sys.argv[2])
metrics = payload["metrics"]
# Budgets: generous ceilings, sized so normal noise cannot fail them but a
# regression back to the pre-P1 algorithms will.
budgets = {
    "memo_hit_ms": 0.01,
    "models_hit_ms": 0.01,
    "search_scan_ms": 8.0 + pins * 0.002,
    "board_ms": 6.0,
    "columns_ms": 6.0,
    "decode_ms": 20.0 + pins * 0.02,
}
failures = []
print(f"pins {payload['pins']}")
for key, budget in budgets.items():
    value = metrics.get(key)
    if value is None:
        failures.append(f"{key}: missing")
        continue
    ok = value <= budget
    print(f"  {'PASS' if ok else 'FAIL'}  {key:<16} {value:9.4f} ms  (<= {budget:.2f})")
    if not ok:
        failures.append(f"{key}: {value:.4f} > {budget:.2f}")
if failures:
    print("perf-guard: FAILED\n  " + "\n  ".join(failures))
    sys.exit(1)
print("perf-guard: PASSED")
PY
