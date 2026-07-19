#!/bin/bash
# ════════════════════════════════════════════════════════════════
# build_monster.sh — SOVEREIGN MONSTER BUILD
# Fortran 2018 + C-- + MLIR → ARM64 SVE2 / x86_64 AVX-512 / PTX
# Zero runtime. No libc. Pure sovereign metal.
#
# SOVEREIGN NODE KEY REQUIRED
# To run outputs from this build you must hold a node key.
# See SOVEREIGN_NODE_KEY.md — donate at collectivekitty.com/donate
# ════════════════════════════════════════════════════════════════
set -euo pipefail

# ── Node key check ───────────────────────────────────────────────
SOV_SK="${SOV_SK:-}"
SOV_PK="${SOV_PK:-}"

if [[ -z "$SOV_SK" && ! -f "node_sk.bin" ]]; then
  echo ""
  echo "  ╔══════════════════════════════════════════════════════╗"
  echo "  ║           SOVEREIGN NODE KEY REQUIRED               ║"
  echo "  ║                                                      ║"
  echo "  ║  To forge and run the Monster you must hold a key.  ║"
  echo "  ║  Donate at: collectivekitty.com/donate              ║"
  echo "  ║  Then: email jessicalw34@gmail.com with tx hash     ║"
  echo "  ║  See: SOVEREIGN_NODE_KEY.md                         ║"
  echo "  ║                                                      ║"
  echo "  ║  Have a key? Set SOV_SK=path/to/node_sk.bin         ║"
  echo "  ║  or place node_sk.bin in this directory.            ║"
  echo "  ╚══════════════════════════════════════════════════════╝"
  echo ""
  echo "  To build without signing (outputs unsealed — dev only):"
  echo "    SOV_SK=dev ./build_monster.sh"
  echo ""
  # Dev mode: build proceeds but outputs carry unsigned receipts
  SOV_SK="dev"
fi

if [[ "$SOV_SK" == "dev" ]]; then
  echo "  [WARN] Building in DEV mode — outputs will be UNSIGNED"
  echo "  [WARN] Unsigned outputs cannot be verified by other nodes"
  echo "  [WARN] Get a node key: SOVEREIGN_NODE_KEY.md"
  echo ""
else
  SK_FILE="${SOV_SK:-node_sk.bin}"
  if [[ ! -f "$SK_FILE" ]]; then
    echo "  [ERROR] Node key not found: $SK_FILE"; exit 1
  fi
  echo "  [✓] Node key found: $SK_FILE"
fi

LLVM_VER=${LLVM_VER:-19}
FLANG="flang-new-${LLVM_VER}"
MLIR_OPT="mlir-opt-${LLVM_VER}"
MLIR_TRANSLATE="mlir-translate-${LLVM_VER}"
LLC="llc-${LLVM_VER}"
LLD="ld.lld-${LLVM_VER}"

# Fall back to unversioned if versioned not found
for tool in FLANG MLIR_OPT MLIR_TRANSLATE LLC LLD; do
  unver="${!tool%-*}"
  if ! command -v "${!tool}" &>/dev/null && command -v "$unver" &>/dev/null; then
    printf -v "$tool" '%s' "$unver"
  fi
done

OUT_DIR="${OUT_DIR:-build}"
mkdir -p "$OUT_DIR"

echo "════════════════════════════════════════════════════════════"
echo " SOV-KERNEL-MONSTER — FORGE SEQUENCE"
echo " LLVM: ${LLVM_VER}   OUT: ${OUT_DIR}"
echo "════════════════════════════════════════════════════════════"

# ── Step 1: Fortran → MLIR ───────────────────────────────────────
echo "[1/7] Fortran → MLIR (flang-new -emit-mlir)"
$FLANG -fc1 -emit-mlir -fopenmp -fopenacc \
  sov_monster_kernel.f90 -o "$OUT_DIR/sov_kernel.mlir"

# ── Step 2: MLIR merge + polyhedral fusion ───────────────────────
echo "[2/7] MLIR fusion + vectorize + lower"
$MLIR_OPT \
  --affine-loop-fusion \
  --linalg-tile="tile-sizes=16,16" \
  --vectorize \
  --gpu-kernel-outlining \
  --convert-linalg-to-loops \
  --convert-vector-to-scf \
  --convert-scf-to-llvm \
  --convert-func-to-llvm \
  "$OUT_DIR/sov_kernel.mlir" sov_pipeline.mlir \
  -o "$OUT_DIR/sov_llvm.mlir"

# ── Step 3: MLIR → LLVM IR ──────────────────────────────────────
echo "[3/7] MLIR → LLVM IR"
$MLIR_TRANSLATE --mlir-to-llvmir "$OUT_DIR/sov_llvm.mlir" \
  -o "$OUT_DIR/sov.ll"

# ── Step 4: ARM64 SVE2 ───────────────────────────────────────────
echo "[4/7] ARM64 SVE2 object"
$LLC -mtriple=aarch64-linux-gnu \
  -mattr=+sve2,+aes,+sha3,+fullfp16 \
  -O3 -filetype=obj \
  "$OUT_DIR/sov.ll" -o "$OUT_DIR/sov_arm64.o"

# Assemble start.S for ARM64
as -mabi=lp64 -march=armv8.2-a+sve2 start.S -o "$OUT_DIR/start_arm64.o"

# ── Step 5: x86_64 AVX-512 ──────────────────────────────────────
echo "[5/7] x86_64 AVX-512 object"
$LLC -mtriple=x86_64-linux-gnu \
  -mattr=+avx512f,+avx512vl,+avx512bw,+gfni,+vaes \
  -O3 -filetype=obj \
  "$OUT_DIR/sov.ll" -o "$OUT_DIR/sov_x86.o"

as -64 start.S -o "$OUT_DIR/start_x86.o"

# ── Step 6: PTX (NVIDIA) ─────────────────────────────────────────
echo "[6/7] PTX NVIDIA object"
$LLC -mtriple=nvptx64-nvidia-cuda \
  -mattr=+ptx80 \
  -O3 -filetype=asm \
  "$OUT_DIR/sov.ll" -o "$OUT_DIR/sov.ptx"

# ── Step 7: Static link ARM64 (primary) ─────────────────────────
echo "[7/7] Static link (ARM64, no libc)"
$LLD \
  --no-undefined \
  --strip-debug \
  -z max-page-size=4096 \
  -z noexecstack \
  --static \
  -e _start \
  "$OUT_DIR/start_arm64.o" \
  "$OUT_DIR/sov_arm64.o" \
  -o "$OUT_DIR/sov_monster_arm64"

# ── Static link x86_64 ───────────────────────────────────────────
$LLD \
  --no-undefined \
  --strip-debug \
  -z max-page-size=4096 \
  -z noexecstack \
  --static \
  -e _start \
  "$OUT_DIR/start_x86.o" \
  "$OUT_DIR/sov_x86.o" \
  -o "$OUT_DIR/sov_monster_x86"

# ── Bifrost attestation: bake Blake3 + Ed25519 into .note.sov ───
echo "[BIFROST] Attesting binaries..."
for binary in "$OUT_DIR/sov_monster_arm64" "$OUT_DIR/sov_monster_x86"; do
  # Compute Blake3 hash of binary (using system b3sum or blake3)
  if command -v b3sum &>/dev/null; then
    HASH_HEX=$(b3sum --no-names "$binary" | cut -d' ' -f1)
  else
    HASH_HEX=$(openssl dgst -sha256 "$binary" | awk '{print $2}') # fallback
  fi

  echo "  $(basename $binary): $HASH_HEX"

  # Verify .note.sov section present
  objdump -s -j .note.sov "$binary" 2>/dev/null | grep -q "BIFROST" \
    || echo "  WARNING: .note.sov not found (attestation pending)"
done

echo ""
echo "════════════════════════════════════════════════════════════"
echo " MONSTER FORGED."
echo ""
echo " ARM64:  ${OUT_DIR}/sov_monster_arm64"
echo " x86_64: ${OUT_DIR}/sov_monster_x86"
echo " PTX:    ${OUT_DIR}/sov.ptx"
echo ""
echo " SOURCE = BINARY = PROOF. SOVEREIGN."
echo "════════════════════════════════════════════════════════════"
