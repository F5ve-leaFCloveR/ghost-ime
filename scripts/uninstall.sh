#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ghost-ime"
DEST="$HOME/Library/Input Methods/${APP_NAME}.app"

if [ -d "$DEST" ]; then
  rm -rf "$DEST"
  echo "Removed $DEST"
else
  echo "Not found: $DEST"
fi
