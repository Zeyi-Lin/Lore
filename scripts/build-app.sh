#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/cache/clang"
export SWIFT_MODULECACHE_PATH="$PWD/.build/cache/swift"
export TMPDIR="$PWD/.build/tmp"
mkdir -p "$TMPDIR"

swift build \
  --disable-sandbox \
  --manifest-cache local \
  --cache-path .build/spm-cache \
  --scratch-path .build \
  -c "$CONFIG" \
  --product Lore

ARCH_DIR=".build/arm64-apple-macosx/$CONFIG"
BINARY="$ARCH_DIR/Lore"
BUNDLE="$ARCH_DIR/Lore_Lore.bundle"

APP="dist/Lore.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/Lore"
if [ -d "$BUNDLE" ]; then
  cp -R "$BUNDLE" "$APP/Contents/Resources/Lore_Lore.bundle"
fi

# App icon (built from the designed 1024 master when available)
ICON_MASTER="Sources/Lore/Resources/AppIcon/icon_1024.png"
if [ -f "$ICON_MASTER" ]; then
  ICONSET=".build/AppIcon.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ICON_MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/appicon.icns"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>Lore</string>
    <key>CFBundleExecutable</key><string>Lore</string>
    <key>CFBundleIconFile</key><string>appicon</string>
    <key>CFBundleIdentifier</key><string>studio.lore.library</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Lore</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.1.0</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.graphics-design</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Lore — a visual library for humans and their agents.</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <!-- Private drag payload for sidebar rows and gallery cards. Declaring it
         keeps foreign drops (plain text from other apps) from matching a board
         row, and lets the system show a sane drag image. -->
    <key>UTExportedTypeDeclarations</key>
    <array>
      <dict>
        <key>UTTypeIdentifier</key><string>studio.lore.sidebar-drag</string>
        <key>UTTypeDescription</key><string>Lore drag</string>
        <key>UTTypeConformsTo</key><array><string>public.data</string></array>
      </dict>
    </array>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP ($CONFIG)"