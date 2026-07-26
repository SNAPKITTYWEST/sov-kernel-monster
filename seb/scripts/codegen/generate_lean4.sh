#!/bin/bash
# Generate Lean4 code from template
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE="$SEB_ROOT/contracts/lean4.template"
OUTPUT_DIR="$SEB_ROOT/verification/lean4"

echo "[Lean4] Copying template to verification directory..."
cp "$TEMPLATE" "$OUTPUT_DIR/SEB.lean"
echo "[Lean4] Generated: $OUTPUT_DIR/SEB.lean"

# Made with Bob
