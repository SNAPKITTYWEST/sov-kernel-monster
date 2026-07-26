#!/bin/bash
# Generate OpenAPI specification from template
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE="$SEB_ROOT/contracts/openapi.template"
OUTPUT_DIR="$SEB_ROOT/docs/api"

mkdir -p "$OUTPUT_DIR"

echo "[OpenAPI] Copying template to docs/api directory..."
cp "$TEMPLATE" "$OUTPUT_DIR/openapi.yaml"
echo "[OpenAPI] Generated: $OUTPUT_DIR/openapi.yaml"

# Made with Bob
