#!/usr/bin/env bash
#
# Capture a window screenshot of Lore in a deterministic state.
# Usage:
#   ./scripts/screenshot-app.sh gallery
#   ./scripts/screenshot-app.sh agent
#   ./scripts/screenshot-app.sh settings
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
HOME_DIR="${LORE_SCREENSHOT_HOME:-$PWD/.build/screenshot-library}"
APP="$PWD/dist/Lore.app"

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

pkill -x Lore >/dev/null 2>&1 || true
for _ in $(seq 1 25); do
  pgrep -x Lore >/dev/null 2>&1 || break
  sleep 0.2
done
if pgrep -x Lore >/dev/null 2>&1; then
  pkill -9 -x Lore >/dev/null 2>&1 || true
  sleep 0.5
fi

# Fresh (or reused) library. On a fresh directory the app installs the designed seed library.
if [ "${FRESH_LIBRARY:-1}" = "1" ]; then
  rm -rf "$HOME_DIR"
fi

defaults write studio.lore.library lore.debugHome -string "$HOME_DIR"
if [ "$MODE" = "large" ]; then
  defaults write studio.lore.library lore.debugShow -string detail
  defaults write studio.lore.library lore.debugLargeImage -bool true
else
  defaults write studio.lore.library lore.debugShow -string "$MODE"
  defaults delete studio.lore.library lore.debugLargeImage >/dev/null 2>&1 || true
fi
defaults write studio.lore.library lore.debugPin -string "$PIN_QUERY"
if [ -n "$LANG_OVERRIDE" ]; then
  defaults write studio.lore.library lore.debugLanguage -string "$LANG_OVERRIDE"
else
  defaults delete studio.lore.library lore.debugLanguage >/dev/null 2>&1 || true
fi

open -n "$APP"
sleep 7

# Bring Lore forward (colored window controls) without spawning another instance.
if [ -x .build/tools/activate-lore ]; then
  .build/tools/activate-lore >/dev/null 2>&1 || true
fi
osascript -e 'tell application "Lore" to activate' >/dev/null 2>&1 || true
.build/tools/move-cursor >/dev/null 2>&1 || true
sleep 1.5

if [ "$(pgrep -x Lore | wc -l | tr -d ' ')" != "1" ]; then
  echo "Expected exactly one Lore process before capture" >&2
  exit 1
fi

if [ "$MODE" = "settings" ]; then
  # The Settings panel is the narrowest Lore window; the main gallery is wide.
  WINDOW_ID="$(.build/tools/window-id Lore | awk '{print $2"\t"$1}' | sort -t x -k1n | head -1 | awk -F '\t' '{print $2}')"
else
  WINDOW_ID="$(.build/tools/window-id Lore | head -1 | awk '{print $1}')"
fi
if [ -z "${WINDOW_ID:-}" ]; then
  echo "Lore window not found" >&2
  defaults delete studio.lore.library lore.debugShow >/dev/null 2>&1 || true
  defaults delete studio.lore.library lore.debugHome >/dev/null 2>&1 || true
  defaults delete studio.lore.library lore.debugPin >/dev/null 2>&1 || true
  exit 1
fi

screencapture -x -o -l "$WINDOW_ID" "$OUT"

defaults delete studio.lore.library lore.debugShow >/dev/null 2>&1 || true
defaults delete studio.lore.library lore.debugHome >/dev/null 2>&1 || true
defaults delete studio.lore.library lore.debugPin >/dev/null 2>&1 || true
defaults delete studio.lore.library lore.debugLanguage >/dev/null 2>&1 || true
defaults delete studio.lore.library lore.debugLargeImage >/dev/null 2>&1 || true

echo "Captured $OUT"

pkill -x Lore >/dev/null 2>&1 || true