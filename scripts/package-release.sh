#!/usr/bin/env bash
# Builds dist/Lore.app and wraps it into dist/Lore-v<version>.dmg — the exact
# asset shape the in-app updater expects, with a guided Finder install window.
#
#   ./scripts/package-release.sh              # swift build (release), then DMG
#   ./scripts/package-release.sh --no-build   # reuse the existing dist/Lore.app
#
# The script stops at the artifact: it never tags, pushes, or calls gh. Publishing
# is a separate, explicit step — see docs/RELEASING.md.
#
# Output: dist/Lore-v<version>.dmg (UDZO, volume "Lore <version>") + SHA-256.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  cat <<'USAGE'
Usage: scripts/package-release.sh [--no-build]

Builds the release app bundle and packages it as dist/Lore-v<version>.dmg.

Options:
  --no-build   package the existing dist/Lore.app instead of running swift build
  -h, --help   show this help
USAGE
}

BUILD=1
for arg in "$@"; do
  case "$arg" in
    --no-build) BUILD=0 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# The version has exactly one source: Sources/Lore/Version.swift. This is the
# same extraction scripts/build-app.sh uses to stamp Info.plist, so the DMG name,
# the bundle, and Settings → About can never disagree (see docs/RELEASING.md).
VERSION="$(sed -n 's/.*static let current = "\([0-9][0-9.]*\)".*/\1/p' Sources/Lore/Version.swift | head -1)"
if [ -z "$VERSION" ]; then
  echo "Could not read LoreVersion.current from Sources/Lore/Version.swift" >&2
  exit 1
fi
if ! printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Refusing to package: version '$VERSION' is not X.Y.Z" >&2
  exit 1
fi

APP="dist/Lore.app"
if [ "$BUILD" -eq 1 ]; then
  ./scripts/build-app.sh release
fi

if [ ! -d "$APP" ]; then
  echo "Missing $APP. Run without --no-build (or run ./scripts/build-app.sh release)." >&2
  exit 1
fi

# Cross-check the bundle that will ship against the version source. This is the
# check that catches a stale dist/Lore.app when --no-build reuses an old build.
PLIST="$APP/Contents/Info.plist"
if [ ! -f "$PLIST" ]; then
  echo "Missing $PLIST; rebuild with ./scripts/build-app.sh release" >&2
  exit 1
fi
if ! BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null)"; then
  echo "Could not read CFBundleShortVersionString from $PLIST" >&2
  exit 1
fi
if [ "$BUILT_VERSION" != "$VERSION" ]; then
  echo "Version mismatch: Sources/Lore/Version.swift says $VERSION but $APP says $BUILT_VERSION" >&2
  echo "Rebuild the app (drop --no-build) so the bundle matches the version source." >&2
  exit 1
fi
if ! BUILT_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST" 2>/dev/null)"; then
  echo "Could not read CFBundleIdentifier from $PLIST" >&2
  exit 1
fi
if [ "$BUILT_ID" != "studio.lore.library" ]; then
  echo "Refusing to package: bundle id is '$BUILT_ID', expected 'studio.lore.library'" >&2
  exit 1
fi

# Stage exactly what the DMG should contain: the app at the root, the usual
# /Applications symlink, and the Finder background. The updater mounts the image
# read-only and copies Lore.app out of it; nothing runs from the image itself.
if [ ! -f scripts/dmg-background.png ]; then
  echo "Missing scripts/dmg-background.png; run python3 scripts/make-dmg-background.py." >&2
  exit 1
fi

STAGE=".build/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/Lore.app"
ln -s /Applications "$STAGE/Applications"
cp scripts/dmg-background.png "$STAGE/.background/background.png"

mkdir -p dist
DMG="dist/Lore-v$VERSION.dmg"
rm -f "$DMG"
VOLUME="Lore $VERSION"
MOUNT="/Volumes/$VOLUME"
RWTMP=".build/Lore-$VERSION-rw.dmg"
rm -f "$RWTMP"

if [ -e "$MOUNT" ]; then
  echo "Volume '$VOLUME' is already mounted; detach it before packaging." >&2
  exit 1
fi

# Finder can only write .DS_Store into a writable image, so build a UDRW
# intermediate, apply the window layout, then compress it to the final UDZO.
hdiutil create -quiet \
  -volname "$VOLUME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDRW \
  "$RWTMP"

hdiutil attach -quiet -nobrowse -readwrite "$RWTMP"
# Layout is best-effort so a headless/CI machine can still cut a valid (plain)
# image when Finder Automation is unavailable.
if ! osascript scripts/dmg-layout.applescript "$VOLUME"; then
  echo "warning: Finder layout failed; shipping a plain DMG window" >&2
fi
sync
osascript -e "tell application \"Finder\" to close window of disk \"$VOLUME\"" >/dev/null 2>&1 || true
sleep 0.5
if ! hdiutil detach "$MOUNT" >/dev/null; then
  hdiutil detach -force "$MOUNT" >/dev/null
fi

hdiutil convert "$RWTMP" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$RWTMP"

if [ ! -s "$DMG" ]; then
  echo "hdiutil did not produce $DMG" >&2
  exit 1
fi

SIZE_BYTES="$(stat -f%z "$DMG")"
SIZE_HUMAN="$(du -h "$DMG" | awk '{print $1}')"
SHA256="$(shasum -a 256 "$DMG" | awk '{print $1}')"

cat <<EOF

Packaged Lore $VERSION
  DMG      $DMG
  Size     $SIZE_HUMAN ($SIZE_BYTES bytes)
  Volume   Lore $VERSION
  SHA-256  $SHA256

Nothing was tagged, pushed, or uploaded. To publish, run the release checklist
in docs/RELEASING.md:
  git add Sources/Lore/Version.swift
  git commit -m "Bump to $VERSION"
  git tag -a "v$VERSION" -m "Lore $VERSION"
  git push origin main && git push origin "v$VERSION"
  gh release create "v$VERSION" "$DMG" --verify-tag --title "Lore $VERSION" --notes-file /tmp/release-notes.md
EOF
