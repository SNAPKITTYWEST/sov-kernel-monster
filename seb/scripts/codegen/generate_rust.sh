#!/bin/bash
# Generate Rust code from template
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE="$SEB_ROOT/contracts/rust.template"
OUTPUT_DIR="$SEB_ROOT/kernel"

echo "[Rust] Copying template to kernel directory..."
cp "$TEMPLATE" "$OUTPUT_DIR/event_envelope.rs"
echo "[Rust] Generated: $OUTPUT_DIR/event_envelope.rs"

# Made with Bob
