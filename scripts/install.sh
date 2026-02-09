#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ghost-ime"
SRC="$ROOT/build/${APP_NAME}.app"
DEST_DIR="$HOME/Library/Input Methods"
DEST="$DEST_DIR/${APP_NAME}.app"

if [ ! -d "$SRC" ]; then
  echo "Build not found: $SRC" >&2
  echo "Run scripts/build.sh first." >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

echo "Installed to $DEST"
