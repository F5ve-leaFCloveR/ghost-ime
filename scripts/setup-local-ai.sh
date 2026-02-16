#!/usr/bin/env bash
set -euo pipefail

MODEL="${1:-llama3.2:1b}"
ENDPOINT="${GHOST_IME_AI_ENDPOINT:-http://127.0.0.1:11434/api/generate}"
APP_DIR="$HOME/Library/Application Support/ghost-ime"
CFG="$APP_DIR/ai_config.json"

mkdir -p "$APP_DIR"

cat > "$CFG" <<JSON
{
  "enabled": true,
  "endpoint": "$ENDPOINT",
  "model": "$MODEL",
  "temperature": 0.2,
  "maxTokens": 8,
  "timeoutSeconds": 3.0,
  "minPrefixLength": 2,
  "cacheTTLSeconds": 300
}
JSON

echo "Saved: $CFG"
echo "Model: $MODEL"
echo "Endpoint: $ENDPOINT"
echo "If needed: ollama pull $MODEL"
