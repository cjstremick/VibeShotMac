#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
# Refuse to run a second instance competing for the same global shortcut.
if pgrep -x VibeShot >/dev/null; then
  echo 'Quit the running VibeShot from its menu-bar menu, then run this script again.' >&2
  exit 1
fi
open "$PWD/build/VibeShot.app"
