#!/usr/bin/env bash
set -euo pipefail

echo "╔════════════════════════════════════════════════════════╗"
echo "║  SOV-KERNEL — SOVEREIGN AI CIVILIZATION BOOT          ║"
echo "╚════════════════════════════════════════════════════════╝"
echo

# Check prerequisites
if ! command -v cargo &> /dev/null; then
    echo "[ERROR] Rust/Cargo not found. Install from https://rustup.rs"
    exit 1
fi

# Optional: check for Haskell Stack
HASKELL_AVAILABLE=false
if command -v stack &> /dev/null; then
    HASKELL_AVAILABLE=true
    echo "[INFO] Haskell Stack found — AToKio will run"
else
    echo "[WARN] Haskell Stack not found — AToKio disabled (agents run headless)"
fi

# Optional: check for Erlang
ERLANG_AVAILABLE=false
if command -v erl &> /dev/null; then
    ERLANG_AVAILABLE=true
    echo "[INFO] Erlang found — SEB will run"
else
    echo "[WARN] Erlang not found — SEB disabled (agents run without supervision)"
fi

echo

# Build desktop binary
echo "[1/3] Building Rust desktop binary..."
cargo build --release --manifest-path "$(dirname "$0")/Cargo.toml"
echo "[1/3] ✓ Desktop binary built"
echo

# Boot
echo "[2/3] Launching sovereign civilization..."
echo

RUST_LOG=info "$(dirname "$0")"/target/release/sov-kernel boot

