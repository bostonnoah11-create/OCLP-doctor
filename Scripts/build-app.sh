#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${OCLP_DOCTOR_BUILD_ROOT:-$PROJECT_ROOT/.build}"
DESTINATION="${1:-$PROJECT_ROOT/dist}"
mkdir -p "$BUILD_ROOT/module-cache" "$DESTINATION"
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/module-cache"

BUILD_ARGS=(--package-path "$PROJECT_ROOT" --scratch-path "$BUILD_ROOT"
  --cache-path "$BUILD_ROOT/cache" --config-path "$BUILD_ROOT/config"
  --security-path "$BUILD_ROOT/security" --manifest-cache local
  --disable-sandbox --triple x86_64-apple-macosx12.0 -c release)
swift build "${BUILD_ARGS[@]}" --product OCLPDoctor
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
APP="$DESTINATION/OCLP Doctor.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/OCLPDoctor" "$APP/Contents/MacOS/OCLPDoctor"
# SwiftPM release binaries retain debug-map records with local build paths.
# Remove only debugging symbols from the distribution copy before signing.
/usr/bin/xcrun strip -S "$APP/Contents/MacOS/OCLPDoctor"
cp "$PROJECT_ROOT/LICENSE" "$PROJECT_ROOT/NOTICE" "$APP/Contents/Resources/"
ICONSET="$BUILD_ROOT/OCLPDoctor.iconset"
ICON_PNG="$BUILD_ROOT/AppIconPreview.png"
swift "$PROJECT_ROOT/Scripts/render-icon.swift" "$PROJECT_ROOT/Assets/AppIcon.svg" "$ICON_PNG" 1024
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  /usr/bin/sips -z "$SIZE" "$SIZE" "$ICON_PNG" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE_SIZE=$((SIZE * 2))
  /usr/bin/sips -z "$DOUBLE_SIZE" "$DOUBLE_SIZE" "$ICON_PNG" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
if ! /usr/bin/iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"; then
  printf 'Icon packaging failed for: %s\n' "$ICONSET" >&2
  printf '%s\n' \
    'Check the iconset PNG names and dimensions. If they are valid, re-run this script outside the restricted shell: macOS icon services can report "Invalid Iconset" for valid files inside a sandbox.' >&2
  exit 1
fi
cp "$ICON_PNG" "$APP/Contents/Resources/AppIconPreview.png"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>OCLPDoctor</string>
  <key>CFBundleIdentifier</key><string>org.oclpdoctor.OCLPDoctor</string>
  <key>CFBundleName</key><string>OCLP Doctor</string>
  <key>CFBundleDisplayName</key><string>OCLP Doctor</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>0.5.1</string>
  <key>CFBundleVersion</key><string>10</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict></plist>
PLIST
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --strict "$APP"
printf 'Built: %s\n' "$APP"
