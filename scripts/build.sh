#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo 'Install Apple Command Line Tools first: xcode-select --install' >&2
  exit 1
fi
APP="$PWD/build/VibeShot.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/module-cache
VERSION="${VERSION:-1.4.0}"
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
# Prefer a stable local signing identity so Screen Recording approval survives
# rebuilds. Ad-hoc signatures change identity every build, which makes macOS
# treat each build as a new app and ask for permission again.
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  # No -v: a local self-signed identity is reported as "not trusted" but is
  # still usable by codesign, and we want to pick it up automatically.
  if security find-identity -p codesigning 2>/dev/null | grep -q "\"VibeShot Dev\""; then
    SIGN_IDENTITY="VibeShot Dev"
  else
    SIGN_IDENTITY="-"
  fi
fi
codesign --force --sign "$SIGN_IDENTITY" --options runtime \
  --entitlements VibeShot/VibeShot/VibeShot.entitlements "$APP"
codesign --verify --strict "$APP"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "Built $APP ($ARCH, macOS 15+, ad-hoc signed)"
  echo "Tip: a stable self-signed identity stops macOS asking for Screen Recording again on each rebuild. See docs/BUILD_AND_RUN.md."
else
  echo "Built $APP ($ARCH, macOS 15+, signed with '$SIGN_IDENTITY')"
fi
