#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/NanoRight.app"
APPEX_BUNDLE="$APP_BUNDLE/Contents/PlugIns/NanoRightFinder.appex"
SDK_PATH="$(xcrun --show-sdk-path --sdk macosx)"

echo "==> [1/5] Building NanoRightApp (release, arm64-only)..."
cd "$ROOT_DIR"
swift build -c release --arch arm64 ${SWIFT_BUILD_FLAGS:-}
HOST_BIN="$(swift build -c release --arch arm64 ${SWIFT_BUILD_FLAGS:-} --show-bin-path)/NanoRight"

echo "==> [2/5] Creating bundle structure..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APPEX_BUNDLE/Contents/MacOS"

cp "$HOST_BIN" "$APP_BUNDLE/Contents/MacOS/NanoRight"
cp "$ROOT_DIR/Resources/AppInfo.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT_DIR/Resources/ExtensionInfo.plist" "$APPEX_BUNDLE/Contents/Info.plist"

echo "==> [3/5] Generating original AppIcon.icns..."
swift "$ROOT_DIR/scripts/generate_icon.swift" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "==> [4/5] Compiling NanoRightFinder.appex (arm64-only, _NSExtensionMain)..."
xcrun swiftc \
  -O \
  -swift-version 5 \
  -target arm64-apple-macos14.0 \
  -sdk "$SDK_PATH" \
  -parse-as-library \
  -application-extension \
  -framework FinderSync \
  -framework AppKit \
  -framework Foundation \
  -framework UniformTypeIdentifiers \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$APPEX_BUNDLE/Contents/MacOS/NanoRightFinder" \
  "$ROOT_DIR/Sources/NanoRightCore/Models.swift" \
  "$ROOT_DIR/Sources/NanoRightCore/Localization.swift" \
  "$ROOT_DIR/Sources/NanoRightCore/ConfigStore.swift" \
  "$ROOT_DIR/Sources/NanoRightCore/ActionCommand.swift" \
  "$ROOT_DIR/Sources/NanoRightFinder/FinderSync.swift"

echo "==> [5/5] Code signing (ad-hoc, inside-out) and verifying..."
codesign --force --sign - \
  --entitlements "$ROOT_DIR/Resources/Extension.entitlements" \
  "$APPEX_BUNDLE"

codesign --force --sign - \
  --entitlements "$ROOT_DIR/Resources/App.entitlements" \
  "$APP_BUNDLE"

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

HOST_ARCH="$(lipo -archs "$APP_BUNDLE/Contents/MacOS/NanoRight")"
EXT_ARCH="$(lipo -archs "$APPEX_BUNDLE/Contents/MacOS/NanoRightFinder")"
if [[ "$HOST_ARCH" != "arm64" || "$EXT_ARCH" != "arm64" ]]; then
  echo "ERROR: Expected arm64-only binaries, got host='$HOST_ARCH', ext='$EXT_ARCH'" >&2
  exit 1
fi

echo "==> Build succeeded: $APP_BUNDLE (host=$HOST_ARCH, ext=$EXT_ARCH)"

# Also place a ready-to-open / drag-installable copy in the parent workspace directory
WORKSPACE_APP="$(cd "$ROOT_DIR/.." && pwd)/NanoRight.app"
rm -rf "$WORKSPACE_APP"
cp -R "$APP_BUNDLE" "$WORKSPACE_APP"
echo "==> Exported ready-to-install app: $WORKSPACE_APP"
