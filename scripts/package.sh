#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ARCH=arm64 ./scripts/build.sh
cp build/VibeShot.app/Contents/MacOS/VibeShot build/VibeShot-arm64
ARCH=x86_64 ./scripts/build.sh
lipo -create build/VibeShot-arm64 build/VibeShot.app/Contents/MacOS/VibeShot -output build/VibeShot-universal
mv build/VibeShot-universal build/VibeShot.app/Contents/MacOS/VibeShot
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  if security find-identity -p codesigning 2>/dev/null | grep -q "\"VibeShot Dev\""; then
    SIGN_IDENTITY="VibeShot Dev"
  else
    SIGN_IDENTITY="-"
  fi
fi
codesign --force --sign "$SIGN_IDENTITY" --options runtime --entitlements VibeShot/VibeShot/VibeShot.entitlements build/VibeShot.app
codesign --verify --strict build/VibeShot.app
lipo -archs build/VibeShot.app/Contents/MacOS/VibeShot
ditto -c -k --sequesterRsrc --keepParent build/VibeShot.app build/VibeShot.zip
