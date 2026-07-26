#!/bin/bash
# Generate Python code from template
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE="$SEB_ROOT/contracts/python.template"
OUTPUT_DIR="$SEB_ROOT/clients/python"

echo "[Python] Copying template to client directory..."
cp "$TEMPLATE" "$OUTPUT_DIR/seb_client.py"
echo "[Python] Generated: $OUTPUT_DIR/seb_client.py"

# Made with Bob
