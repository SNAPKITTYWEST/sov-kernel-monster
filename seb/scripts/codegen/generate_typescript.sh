#!/bin/bash
# Generate TypeScript code from template
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE="$SEB_ROOT/contracts/typescript.template"
OUTPUT_DIR="$SEB_ROOT/clients/typescript"

echo "[TypeScript] Copying template to client directory..."
cp "$TEMPLATE" "$OUTPUT_DIR/index.ts"
echo "[TypeScript] Generated: $OUTPUT_DIR/index.ts"

# Made with Bob
