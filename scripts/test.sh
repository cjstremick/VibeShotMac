#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
sources=()
for source in VibeShot/VibeShot/*.swift; do
  [[ "$source" == */VibeShotApp.swift ]] || sources+=("$source")
done
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx15.0" \
  -module-cache-path "$PWD/build/module-cache" \
  "${sources[@]}" Tests/RegressionTests.swift -o build/RegressionTests
./build/RegressionTests
