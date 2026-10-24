#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo 'Install Apple Command Line Tools first: xcode-select --install' >&2
  exit 1
fi
APP="$PWD/build/VibeShot.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/module-cache
VERSION="${VERSION:-1.3.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
ARCH="${ARCH:-$(uname -m)}"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1;; esac
xcrun swiftc -O -swift-version 5 -target "$ARCH-apple-macosx15.0" \
  -module-cache-path "$PWD/build/module-cache" \
  -module-name VibeShot VibeShot/VibeShot/*.swift -o "$APP/Contents/MacOS/VibeShot"
# A normal .icns lets the command-line build use the existing icon without actool/Xcode.
mkdir -p build/AppIcon.iconset
cp VibeShot/VibeShot/Assets.xcassets/AppIcon.appiconset/*.png build/AppIcon.iconset/
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
python3 - "$APP/Contents/Info.plist" "$VERSION" "$BUILD_NUMBER" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(dict(CFBundleExecutable='VibeShot', CFBundleIdentifier='com.stremick.VibeShot',
        CFBundleName='VibeShot', CFBundleDisplayName='VibeShot', CFBundlePackageType='APPL',
        CFBundleShortVersionString=sys.argv[2], CFBundleVersion=sys.argv[3],
        CFBundleIconFile='AppIcon', LSMinimumSystemVersion='15.0', LSUIElement=True,
        NSHighResolutionCapable=True, NSPrincipalClass='NSApplication',
        LSApplicationCategoryType='public.app-category.utilities'), f)
PY
codesign --force --sign - --options runtime \
  --entitlements VibeShot/VibeShot/VibeShot.entitlements "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($ARCH, macOS 15+)"
