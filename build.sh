#!/bin/bash
# Builds Quick Draw.app into ./build, versioned from the VERSION file.
#   --install   also copy the app to ~/Applications
#   --dmg       also package build/QuickDraw-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP="build/Quick Draw.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/AppIcon.iconset

swiftc -O -swift-version 5 QuickDraw.swift -o "$APP/Contents/MacOS/QuickDraw"

# Icon: the binary renders its own cowboy, sips/iconutil turn it into an .icns
"$APP/Contents/MacOS/QuickDraw" --render-icon build/icon.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) build/icon.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Quick Draw</string>
  <key>CFBundleDisplayName</key><string>Quick Draw</string>
  <key>CFBundleIdentifier</key><string>com.adrianocastro.quickdraw</string>
  <key>CFBundleExecutable</key><string>QuickDraw</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built $APP ($VERSION, build $BUILD_NUMBER)"

for arg in "$@"; do
  case "$arg" in
    --install)
      mkdir -p ~/Applications
      rm -rf ~/Applications/"Quick Draw.app"
      cp -R "$APP" ~/Applications/
      echo "Installed to ~/Applications/Quick Draw.app"
      ;;
    --dmg)
      DMG="build/QuickDraw-${VERSION}.dmg"
      STAGE="build/dmg"
      mkdir -p "$STAGE"
      cp -R "$APP" "$STAGE/"
      ln -s /Applications "$STAGE/Applications"
      hdiutil create -volname "Quick Draw ${VERSION}" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
      rm -rf "$STAGE"
      echo "Packaged $DMG"
      ;;
  esac
done
