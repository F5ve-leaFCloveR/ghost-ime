#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ghost-ime"
MODULE_NAME="GhostIME"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/${APP_NAME}.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"

mkdir -p "$MACOS_DIR" "$RES_DIR"

SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"

xcrun swiftc \
  -module-name "$MODULE_NAME" \
  -sdk "$SDKROOT" \
  -O \
  -framework Cocoa \
  -framework InputMethodKit \
  "$ROOT/src/main.swift" \
  "$ROOT/src/AppDelegate.swift" \
  "$ROOT/src/InputController.swift" \
  "$ROOT/src/Predictor.swift" \
  -o "$MACOS_DIR/$APP_NAME"

cp "$ROOT/resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT/resources/ghost-ime.icns" "$RES_DIR/ghost-ime.icns"
cp "$ROOT/resources/words.txt" "$RES_DIR/words.txt"

echo "Built $APP_DIR"
