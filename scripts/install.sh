#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_APP="$ROOT_DIR/build/NanoRight.app"
DEST_APP="/Applications/NanoRight.app"

if [[ ! -d "$SRC_APP" ]]; then
  echo "Building NanoRight.app first..."
  "$ROOT_DIR/scripts/build_app.sh"
fi

echo "==> Installing NanoRight.app to /Applications..."
rm -rf "$DEST_APP"
cp -R "$SRC_APP" "$DEST_APP"
xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$DEST_APP"
fi

echo "==> Registering and enabling NanoRightFinder extension..."
pluginkit -a "$DEST_APP/Contents/PlugIns/NanoRightFinder.appex" || true
pluginkit -e use -i com.nanoright.app.finder || true

echo "==> Launching NanoRight..."
open "$DEST_APP"
echo "Done! If the Finder context menu does not appear immediately, run: killall Finder"
