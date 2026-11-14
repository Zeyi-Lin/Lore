#!/usr/bin/env bash
#
# Capture a window screenshot of Canta in a deterministic state.
# Usage:
#   ./scripts/screenshot-app.sh gallery
#   ./scripts/screenshot-app.sh agent
#   ./scripts/screenshot-app.sh capture
#   ./scripts/screenshot-app.sh detail "Aurora"
#   ./scripts/screenshot-app.sh batch
#   ./scripts/screenshot-app.sh large "Miso"
#
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-gallery}"
PIN_QUERY="${2:-Aurora}"
LANG_OVERRIDE="${SCREENSHOT_LANG:-}"
OUT="${3:-docs/screenshots/${MODE}.png}"
HOME_DIR="${CANTA_SCREENSHOT_HOME:-$PWD/.build/screenshot-library}"
APP="$PWD/dist/Canta.app"

mkdir -p docs/screenshots artifacts

# Compile the tiny window finder once.
if [ ! -x .build/tools/window-id ]; then
  mkdir -p .build/tools
  export SDKROOT="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
  export CLANG_MODULE_CACHE_PATH="$PWD/.build/cache/clang"
  export SWIFT_MODULECACHE_PATH="$PWD/.build/cache/swift"
  swiftc -target arm64-apple-macosx14.0 scripts/window-id.swift -o .build/tools/window-id
fi
if [ ! -x .build/tools/move-cursor ]; then
  cat > .build/tools/move-cursor.swift <<'SWIFT'
import CoreGraphics
CGWarpMouseCursorPosition(CGPoint(x: 2500, y: 1400))
SWIFT
  export SDKROOT="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
  export CLANG_MODULE_CACHE_PATH="$PWD/.build/cache/clang"
  export SWIFT_MODULECACHE_PATH="$PWD/.build/cache/swift"
  swiftc -target arm64-apple-macosx14.0 .build/tools/move-cursor.swift -o .build/tools/move-cursor
fi

pkill -x Canta >/dev/null 2>&1 || true
for _ in $(seq 1 25); do
  pgrep -x Canta >/dev/null 2>&1 || break
  sleep 0.2
done
if pgrep -x Canta >/dev/null 2>&1; then
  pkill -9 -x Canta >/dev/null 2>&1 || true
  sleep 0.5
fi

# Fresh (or reused) library. On a fresh directory the app installs the designed seed library.
if [ "${FRESH_LIBRARY:-1}" = "1" ]; then
  rm -rf "$HOME_DIR"
fi

defaults write studio.canta.library canta.debugHome -string "$HOME_DIR"
if [ "$MODE" = "large" ]; then
  defaults write studio.canta.library canta.debugShow -string detail
  defaults write studio.canta.library canta.debugLargeImage -bool true
else
  defaults write studio.canta.library canta.debugShow -string "$MODE"
  defaults delete studio.canta.library canta.debugLargeImage >/dev/null 2>&1 || true
fi
defaults write studio.canta.library canta.debugPin -string "$PIN_QUERY"
if [ -n "$LANG_OVERRIDE" ]; then
  defaults write studio.canta.library canta.debugLanguage -string "$LANG_OVERRIDE"
else
  defaults delete studio.canta.library canta.debugLanguage >/dev/null 2>&1 || true
fi

open -n "$APP"
sleep 7

# Bring Canta forward (colored window controls) without spawning another instance.
if [ -x .build/tools/activate-canta ]; then
  .build/tools/activate-canta >/dev/null 2>&1 || true
fi
osascript -e 'tell application "Canta" to activate' >/dev/null 2>&1 || true
.build/tools/move-cursor >/dev/null 2>&1 || true
sleep 1.5

if [ "$(pgrep -x Canta | wc -l | tr -d ' ')" != "1" ]; then
  echo "Expected exactly one Canta process before capture" >&2
  exit 1
fi

WINDOW_ID="$(.build/tools/window-id Canta | head -1 | awk '{print $1}')"
if [ -z "${WINDOW_ID:-}" ]; then
  echo "Canta window not found" >&2
  defaults delete studio.canta.library canta.debugShow >/dev/null 2>&1 || true
  defaults delete studio.canta.library canta.debugHome >/dev/null 2>&1 || true
  defaults delete studio.canta.library canta.debugPin >/dev/null 2>&1 || true
  exit 1
fi

screencapture -x -o -l "$WINDOW_ID" "$OUT"

defaults delete studio.canta.library canta.debugShow >/dev/null 2>&1 || true
defaults delete studio.canta.library canta.debugHome >/dev/null 2>&1 || true
defaults delete studio.canta.library canta.debugPin >/dev/null 2>&1 || true
defaults delete studio.canta.library canta.debugLanguage >/dev/null 2>&1 || true
defaults delete studio.canta.library canta.debugLargeImage >/dev/null 2>&1 || true

echo "Captured $OUT"

pkill -x Canta >/dev/null 2>&1 || true