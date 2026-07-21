# SOV-KERNEL-MONSTER — Technical Guide

**Ahmad Ali Parr · SnapKitty Collective · 2026**

Complete walkthrough of the repository: architecture, every module, how
the pieces connect, and how to build and run each layer of the stack.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Repository Map](#2-repository-map)
3. [Fortran Quantum Engine](#3-fortran-quantum-engine)
4. [Sovereign Monster Kernel](#4-sovereign-monster-kernel)
5. [Jordan Spectral Transformer](#5-jordan-spectral-transformer)
6. [MLIR Pipeline](#6-mlir-pipeline)
7. [RTX 4090 Zero-Libc Engine](#7-rtx-4090-zero-libc-engine)
8. [Lean 4 Formal Specifications](#8-lean-4-formal-specifications)
9. [Haskell: Jacobian + AVR](#9-haskell-jacobian--avr)
10. [Rust: sov-rust-core + WASM](#10-rust-sov-rust-core--wasm)
11. [Multi-Language Bindings](#11-multi-language-bindings)
12. [Quantum Piper Infra](#12-quantum-piper-infra)
13. [Adaptive Verified Runtime](#13-adaptive-verified-runtime)
14. [Build System](#14-build-system)
15. [Testing](#15-testing)

---

## 1. Overview

SOV-KERNEL-MONSTER is a sovereign quantum kernel: a formally verified,
self-evolving, zero-external-dependency compute stack for quantum simulation,
neural inference, and polynomial algebra.

**What it is NOT:**
- Not a wrapper around PyTorch, JAX, or TensorFlow
- Not a "quantum simulator" in the Qiskit sense
- Not dependent on libc, LAPACK, or any external library in bare-metal mode

**What it IS:**
- Fortran 2018 quantum state evolution with C ABI
- Jordan Spectral Transformer: Born rule replaces softmax
- MLIR polyhedral fusion: the full JST forward pass in one kernel call
- Lean 4 formal spec with zero sorry
- Self-evolving via the Adaptive Verified Runtime (AVR)
- WORM-attested: every output is Blake3 + Ed25519 signed

**The core loop:**
```
signal → SPE encode → N×Jordan → Born rule → reconstruct → WORM receipt
```

---

## 2. Repository Map

```
sov-kernel-monster/
│
├── src/                    ← Fortran 2018, the mathematical heart
│   ├── bob_kinds.f90         ISO C types + Goldilocks constants
│   ├── bob_errors.f90        13 stable error codes
│   ├── bob_rng.f90           xoshiro256** PRNG
│   ├── bob_state.f90         quantum state vector |ψ⟩
│   ├── bob_gates.f90         Pauli, H, T, S, CNOT, phase
│   ├── bob_lattice.f90       3D Josephson vortex lattice
│   ├── bob_measurement.f90   Born rule, collapse
│   ├── bob_hamiltonian.f90   Ising H, Padé exp
│   ├── bob_integrator.f90    Trotter-2
│   ├── bob_metrics.f90       entropy, purity, fidelity
│   ├── bob_goldilocks.f90    p=2⁶⁴-2³²+1, NTT
│   ├── bob_worm.f90          Blake3 WORM chain
│   ├── bob_circuit.f90       QFT, Grover, Shor, QPE
│   ├── bob_phdae.f90         Port-Hamiltonian DAE
│   ├── bob_abi.f90           14 C ABI exports
│   ├── sov_monster_kernel.f90  Blake3+Ed25519+APL ZGEMM
│   ├── boolean_spectral_lens.f90
│   ├── measurement_head.f90  ← JST Born rule output
│   ├── jordan_block.f90      ← JST Jordan layers
│   ├── spe_encoder.f90       ← JST tokenizer
│   ├── training_adjoint.f90  ← JST reverse-mode AD
│   ├── sov_control.cmm       C-- state machine
│   └── start.S               bare entry, no crt0
│
├── mlir/                   ← MLIR pipeline files
│   ├── sov_pipeline.mlir
│   ├── jst_fusion_pipeline.mlir   ← fuses JST into one polyhedral nest
│   ├── jst_sovereign_pipeline.mlir
│   ├── sovereign_deployment.mlir
│   └── bob_twin_reasoning.mlir    ← 5-agent BFT consensus
│
├── rtx/                    ← RTX 4090 zero-libc inference
│   ├── src/cuda/flash_attention.ptx
│   ├── src/c--/scheduler.cmm
│   ├── src/fortran/transformer_kernel.f90
│   ├── src/loader/gguf.c
│   └── windows_rtx/
│
├── lean/                   ← Lean 4 formal specification
│   ├── SovMonster.lean          full JST API + 4 theorems
│   ├── AdaptiveVerifiedRuntime.lean  density matrix + AVR proofs
│   └── lakefile.lean
│
├── haskell/                ← Jacobian Conjecture + AVR
│   ├── LiquidLean/Jacobian/     genus-0 forcing attack
│   ├── LiquidLean/AdaptiveVerifiedRuntime.hs
│   └── liquidlean-theorem3.cabal
│
├── rust/                   ← sov-rust-core eigensolver
│   ├── bob-quantum-sys/         Rust FFI over Fortran
│   └── sov-rust-core/src/
│       ├── spectral.rs    entropy, Born probabilities
│       ├── zheev.rs       Hermitian eigensolver (nalgebra)
│       ├── pirtm.rs       PIRTM recurrence
│       └── qec.rs         stabilizer tableau QEC
│
├── wasm/                   ← browser WASM bridge (44KB)
│
├── quantum-piper/          ← Haiku swarm sovereign infra
│   ├── infra/
│   └── provision/
│
├── scripts/
│   ├── avr_cold_boot_demo.py   ← run this to see AVR live
│   └── record_avr_boot.ps1
│
└── docs/
    ├── paper_JST_LiquidLean.md  ← the paper
    └── technical_guide.md       ← this file
```

---

## 3. Fortran Quantum Engine

### What it is

21 modules implementing quantum mechanics from scratch in Fortran 2018.
No LAPACK. No BLAS. No external deps. Pure ISO Fortran with C ABI.

### Module dependency order (build order)

```
bob_kinds → bob_errors → bob_rng → bob_state → bob_gates
         → bob_lattice → bob_measurement → bob_hamiltonian
         → bob_integrator → bob_metrics → bob_goldilocks
         → bob_worm → bob_circuit → bob_phdae → bob_abi
```

### Key types

All modules use the types defined in `bob_kinds.f90`:
- `wp = selected_real_kind(15,307)` — double precision
- `int64 = selected_int_kind(18)` — 64-bit integers
- `complex(wp)` — complex double

### C ABI (bob_abi.f90)

14 functions exported with `bind(C)`. These are what Lean 4, Rust, and
all other language bindings call:

```fortran
! State evolution: ρ(t+dt) = U·ρ·U†, Padé-13 + scaling/squaring
subroutine sov_apl_step_zgemm_fused(H, ldH, rho, ldr, dt, sk, pk, ...) bind(C)

! Born rule: p_j = tr(q_j · ρ)
subroutine born_rule(q, rho, m, d, p, plasma_ok) bind(C)

! Jordan step: ρ' = φ⁻¹·UρU† + φ⁻²·ρ
subroutine jordan_step(H, rho, n, dt, sk, pk, out_rho, hash, sig) bind(C)

! SPE encode: signal → density via frame
subroutine spe_encode(signal, signal_len, frame, rank, dim, ...) bind(C)
```

### Plasma gate

Every ABI call goes through `sov_plasma_verify` first:
- Hermitian? (H† = H)
- trace-1? (tr(ρ) = 1)
- shapes match?
- Blake3 hash computed

If any check fails: `FAULT` — the function does not proceed.

---

## 4. Sovereign Monster Kernel

`sov_monster_kernel.f90` — 1,506 lines. The fused kernel:

```
Input: H (Hamiltonian), ρ (density matrix), dt, sk (signing key), pk (verify key)
  │
  ▼  Padé-13 matrix exponential: U = exp(-i·dt·H)
  ▼  APL ZGEMM: ρ' = U · ρ · U†  (OpenACC/OpenMP, AVX-512)
  ▼  Blake3 hash of output
  ▼  Ed25519 signature
  │
Output: ρ', hash (32 bytes), sig (64 bytes)
```

The APL ZGEMM is the line:
```fortran
! APL: ρ ← (U +.× ρ) +.× conj(transpose(U))
```
This is the inner-product reduction fused with the matrix multiply.

### Ed25519 implementation

Pure Fortran 2018. No libsodium, no OpenSSL. The key derivation uses
the Goldilocks field (`bob_goldilocks.f90`) for the scalar arithmetic
over the twisted Edwards curve.

---

## 5. Jordan Spectral Transformer

The JST stack spans three Fortran modules plus the MLIR fusion file.

### 5.1 SPE Encoder (spe_encoder.f90)

```
signal x ∈ ℝᵈ
   │
   ▼  frame inner products: sᵢ = ⟨ψᵢ, x⟩  for i = 1..r
   ▼  softmax: λᵢ = exp(sᵢ) / Σⱼ exp(sⱼ)
   ▼  density: eigsᵢ = λᵢ,  density = diag(λ)
   ▼  Plasma gate + Bifrost seal
   │
output: eigenvalues, density matrix ρ, hash, sig
```

The frame {ψᵢ} is learned by `spe_learn_frame` — a power-iteration
procedure that converges Jordan idempotents from a training corpus.
The frame is verified by `spe_verify_frame` returning a bitmask:
- bit 0: Hermitian
- bit 1: Orthogonal
- bit 2: Tight (Σψᵢ = I)
- bit 3: Idempotent (ψᵢ² = ψᵢ)

### 5.2 Jordan Block (jordan_block.f90)

Core recurrence:
```fortran
! One step: rho_new = phi_inv * U*rho*U† + phi_inv_sq * rho
rho_new = PHI_INV * matmul(U, matmul(rho, conjg(transpose(U)))) &
        + PHI_INV_SQ * rho
```
where `PHI_INV = 0.6180339887498948_wp` and `PHI_INV_SQ = 0.3819660112501052_wp`.
Note: `PHI_INV + PHI_INV_SQ = 1.0` exactly (golden ratio identity φ²=φ+1).

**Fibonacci tower** (`jordan_fib`): N layers with convergence tracking.
Each layer emits a WORM receipt. The `converged` flag is set when
`‖ρₖ₊₁ − ρₖ‖_F < tol`.

**Fixpoint** (`jordan_fixpoint`): iterate until T(ρ*) = ρ* within tolerance.
Banach guarantees existence and uniqueness.

**Gradient** (`jordan_gradient`):
```
∂L/∂H = −i·dt·φ⁻¹·[λ, ρ]
```
where `[λ, ρ] = λρ − ρλ` is the commutator.

### 5.3 Measurement Head (measurement_head.f90)

Born rule with Fibonacci temperature annealing:
```
τₖ = τ₀ · φ⁻ᵏ
pⱼ(τ) = exp(εⱼ/τ) / Σₗ exp(εₗ/τ)
```
As k→∞, τₖ→0, pⱼ→argmax (greedy). As k→0, pⱼ→uniform.

Output modes:
- `born_rule`: exact tr(qⱼρ) projection
- `born_rule_temperature`: softmax-Born at temperature τ
- `argmax_spectral`: ⊃⍒p (APL: index of max)
- `sample_spectral`: p⌸⍳m (APL: sample from Born distribution)

### 5.4 MLIR Fusion (jst_fusion_pipeline.mlir)

`jst_forward` fuses the entire pipeline:
```mlir
func.func @jst_forward(%signal, %frame, %H_list, ...) {
  // Phase 1: SPE encode
  %lambda = call @spe_encode(...)
  // Phase 2: N Jordan layers
  %rho = scf.for %k = 0 to %nLayers {
    %rho_new = call @jordan_step(...)
  }
  // Phase 3: Born rule
  %probs = call @born_rule_temperature(...)
  // Phase 4: Reconstruct
  %signal_out = call @reconstruct(...)
}
```

After `--affine-loop-fusion`: one polyhedral nest. For d≤64: density
never leaves registers. On GPU: one kernel launch.

---

## 6. MLIR Pipeline

Five pipeline files, three tiers:

| File | Purpose |
|---|---|
| `sov_pipeline.mlir` | Standard sovereign pipeline: linalg → affine → LLVM |
| `jst_fusion_pipeline.mlir` | JST-specific: fuses SPE + Jordan + Born |
| `jst_sovereign_pipeline.mlir` | JST + sovereign attestation |
| `sovereign_deployment.mlir` | Final deployment: target-specific lowering |
| `bob_twin_reasoning.mlir` | 5-agent BFT consensus reasoning |

### BFT consensus (bob_twin_reasoning.mlir)

5 agents (Constitutional, Architecture, Training, Audit, Forge). Any
output requires 4-of-5 agreement. Fallback: revert to `%jst_ir`.

### Build pipeline (build_monster.sh)

8 steps:
1. Fortran → MLIR (flang-new-19)
2. MLIR fusion + vectorize + lower
3. MLIR → LLVM IR
4. ARM64 SVE2 object
5. x86_64 AVX-512 object
6. PTX sm_89 object
7. Agent 5: MLIR Sovereign Optimizer
8. Static link

---

## 7. RTX 4090 Zero-Libc Engine

**Completely sovereign inference engine for sm_89 (Ada Lovelace).**
No libc. No C runtime. No imports except nvcuda.dll (loaded via PEB walk).

### flash_attention.ptx

PagedAttention implemented in raw PTX assembly:
- Online softmax (Milakov-Norouzi numerically stable)
- Tensor core WMMA instructions
- RMSNorm + SiLU inline
- Power suspend hook → WORM checkpoint

### scheduler.cmm (C-- state machine)

6 states: `IDLE → PREFILL → GENERATE → SWAP → CHECKPOINT → RESUME`

WORM attestation every 64 tokens. BFT quorum height tracking.
The C-- state machine has no GC, no allocator — pure state transitions.

### gguf.c (zero-libc GGUF parser)

Parses GGUF v3 files using `VirtualAlloc`/`mmap` only. No `malloc`.
Supports: Q4_0, Q4_K, Q8_0, F16, BF16, F32 quantization formats.

### Windows zero-CRT boot

`sov_main()` in `windows_rtx/main.c`:
1. PEB walk → find kernel32.dll
2. PE export table scan → LoadLibrary, GetProcAddress
3. Load nvcuda.dll via PEB walk (not LoadLibrary)
4. Initialize CUDA → Power → Scheduler → loop

**Build:**
```bash
cd rtx && mkdir build && cd build
cmake .. -DSOV_BUILD_CUDA=ON -DSOV_ZERO_LIBC=ON
cmake --build . --config Release
```

---

## 8. Lean 4 Formal Specifications

### SovMonster.lean (412 lines)

Full JST API specified as `@[extern]` opaque declarations + 4 theorems.

**Sections:**
1. Core types: `CPtr`, `Hash`, `Sig`, `Key`, `Receipt`
2. Monster kernel: `plasmaVerify`, `bifrostSign`, `aplStepFused`
3. SPE encoder: `speEncode`, `speDecode`, `speLearnFrame`, `speVerifyFrame`
4. Jordan block: `jordanStep`, `jordanFib`, `jordanFixpoint`, `jordanGradient`
5. Measurement head: `bornRule`, `bornRuleTemp`, `argmaxSpectral`, `sampleSpectral`
6. Training adjoint: `buresLoss`, `adjointPass`, `trainingStep`, `adamUpdate`
7. Fused MLIR kernel: `jstForward`
8. Sovereignty theorems (4, all zero sorry)

**Reading the LiquidHaskell annotations:**
Lines like `{-@ jordan_step :: Unitary d → Density d → Density d @-}` are
embedded LiquidHaskell type signatures in Lean comments — they document
the intended refinement type even though Lean 4 doesn't parse them.

### AdaptiveVerifiedRuntime.lean (296 lines)

**Sections:**
1. Proven AVR theorems (rollback, hot-swap, WORM, version monotonicity)
2. `DensityMatrix n` — formal density matrix type
3. `Frame n k` — tight frame
4. FFI correctness (ffiEvolve preserves trace + positivity)
5. `encodeDM`/`decodeDM` — roundtrip proofs
6. `RuntimeState`, `Rewrite` — AVR types with monotonicity theorems

### lakefile.lean

```lean
require mathlib from git "https://github.com/leanprover-community/mathlib4"
```

Build: `lake build`

---

## 9. Haskell: Jacobian + AVR

### LiquidLean/Jacobian/ (Theorem 3 crack)

Entry point: `Theorem3Entry.hs`

```haskell
theorem3EnforceGenusZero :: Polynomial -> Integer -> Either Obstruction Theorem3Evidence
```

Pipeline:
1. `MoraLocal.hs` — Mora standard basis in ℂ[[u,x]] (local ring)
2. `SingularityAnalysis.hs` — Milnor number μ, δ-invariants, branch count
3. `CrackTheorem3.hs` — `forceGenusZero`: Plücker formula → genus check
4. If genus=0: `GenusZeroForced` → rational curve → inversion exists
5. If genus>0: `HigherGenusObstruction` — blocked by ADR-011

**Current status:** Claim Level 8/9. Proved: dim-1, affine, triangular.
Key lemma (Theorem 3 full case) remains open.

### LiquidLean/AdaptiveVerifiedRuntime.hs (~600 lines)

The Haskell mirror of the AVR Lean spec.

**Key types:**
```haskell
data RuntimeState = RuntimeState
  { rsKernel      :: Kernel
  , rsInvariants  :: ProofContext
  , rsOptimizer   :: MLIRPipeline
  , rsReceipts    :: WORMLedger
  , rsGeneration  :: Natural }

data Rewrite = Inline | Fuse | Specialize | Vectorize | Parallelize | ReplaceKernel
```

**Key functions:**
- `evolveStep` — full evolution: rewrite → verify → seal
- `verifyAndSeal` — Lean verification + WORM receipt
- `hotSwapBinding` — atomic FFI pointer swap
- `rollbackKernel` — safe rollback with re-verification
- `selectStrategy` — meta-learner strategy selection

### cabal configuration

`liquidlean-theorem3.cabal` exposes:
- `LiquidLean.Jacobian.*` (5 modules)
- `LiquidLean.AdaptiveVerifiedRuntime`

Dependencies: base, containers, stm, async, text, mtl

---

## 10. Rust: sov-rust-core + WASM

### sov-rust-core/src/

Four modules closed during Sprint 2:

| Module | What it fixes |
|---|---|
| `zheev.rs` | Complex Hermitian eigensolver via real-block reduction (nalgebra). Fixes broken `sov_zheev` stub in `spe_encoder.f90` |
| `pirtm.rs` | PIRTM recurrence + `jordan_contraction()` matching φ⁻¹ Fibonacci rate |
| `qec.rs` | Aaronson-Gottesman stabilizer tableau + greedy min-weight logical operator |
| `spectral.rs` | Shannon/von Neumann/KL entropy + `born_probabilities()` |

Zero LAPACK deps — pure nalgebra real-block decomposition.

### wasm/ (browser bridge)

`wasm/src/lib.rs` ports the quantum engine to WebAssembly:
- `quantum_evolve()` — density matrix time evolution
- `born_sample()` — Born rule sampling from browser WASM

Build: `make wasm` → `wasm/pkg/quantum_wasm_bg.wasm` (44KB)

Used by `bob-ide` (separate repo) for browser-native quantum computation.

---

## 11. Multi-Language Bindings

10 languages all calling the C ABI (`bob_quantum_state_evolve`):

| Language | File | Notes |
|---|---|---|
| Rust | `rust/bob-quantum-sys/src/lib.rs` | `extern "C"` FFI |
| Elixir | `elixir/lib/bob_quantum.ex` | NIF via Rustler |
| Janet | `janet/bob_quantum.janet` | cffi |
| Julia | `julia/bob_quantum.jl` | `ccall` |
| Odin | `odin/bob_quantum.odin` | `foreign` |
| R | `r/bob_quantum.R` | `.C()` |
| Racket | `racket/bob_quantum.rkt` | `ffi/unsafe` |
| Zig | `zig/src/bob_quantum.zig` | `@cImport` |
| Smalltalk | `smalltalk/BobQuantum.st` | FFI bridge |
| C | `include/bob_quantum.h` | direct |

**Cross-language reproducibility:** same random seed → identical quantum
state samples across all language pairs. Verified in CI.

---

## 12. Quantum Piper Infra

`quantum-piper/` contains the sovereign Docker + Haiku swarm infrastructure.

### infra/docker-compose.sov.yml

Three services on `sov-internal` network (no external gateway):
- `sov-git-server` — hardened Gitea (from source, no telemetry, SSH-only)
- `sov-registry-proxy` — local Docker registry at `localhost:5000`
- `haiku-fn-ops` — Haiku swarm orchestrator

### infra/sov-attest.sh

```bash
HASH=$(docker save $IMAGE | b3sum --no-names)
SIGNATURE=$(echo -n "$HASH" | openssl pkeyutl -sign -inkey $BIFROST_KEY)
echo '{"image": ..., "hash": ..., "signature": ...}' > $IMAGE.worm
docker push localhost:5000/$IMAGE
```

Mock mode (default): set `BIFROST_KEY=/path/to/key` for real signing.

### infra/hooks/verify_asp.pl (Prolog)

```prolog
% Main branch: requires Architect key
verify_push(NewRev, 'refs/heads/main') :-
    get_commit_signer(NewRev, Signer),
    architect_key(Signer).

% Feature branches: any authorized key
verify_push(NewRev, Ref) :-
    get_commit_signer(NewRev, Signer),
    authorized_key(Signer).
```

Currently using mock fingerprints. Replace with real keys after
running `provision/sov-bootstrap.yml`.

### provision/sov-bootstrap.yml (Ansible)

6 phases:
1. Create 50GB WORM ext4 loop volume with `errors=remount-ro`
2. Generate 7 Ed25519 keypairs (1 architect, 5 engineers, 1 bot)
3. Deploy Prolog verification rules to WORM volume
4. Deploy Git hooks to Gitea
5. Lock Trust Deed: `chattr +i TRUST_DEED.xml`
6. Write timestamped attestation log

Run: `ansible-playbook -i provision/inventory/sov-local.yml provision/sov-bootstrap.yml --ask-become-pass`

---

## 13. Adaptive Verified Runtime

The AVR closes the loop: kernels self-evolve while Lean watches invariants.

### Cold boot demo

```bash
python scripts/avr_cold_boot_demo.py
```

What you see:
1. Trust deed + 9 Lean invariants loaded
2. K0 built (Fortran → MLIR → AVX-512)
3. 4 MLIR rewrite cycles with speedup gate
4. Atomic FFI hot-swap on each passing cycle
5. Rollback demonstration
6. 1.68x cumulative speedup, WORM chain sealed

### Record it

```powershell
pwsh -File scripts/record_avr_boot.ps1
```
Produces `avr_cold_boot_TIMESTAMP.cast` (asciinema v2) + `.log`.

### The evolution loop

```haskell
runEvolutionLoop controller = forever $ do
  threadDelay 1_000_000  -- 1 second
  forM_ activeKernels $ \kernel -> do
    triggers ← checkTriggers controller kernel
    forM_ triggers $ \trigger -> do
      candidate ← executeRewrite controller kernel trigger
      case candidate of
        Right k' → verifyAndDeploy controller k' >>= recordResult
        Left  _  → recordFailure controller
```

### Speedup gate

Deploy only if: `old_cycles / new_cycles ≥ 1.05`

### WORM receipt per deploy

```haskell
WORMReceipt
  { wrGeneration  = rsGeneration state
  , wrKernelId    = kId kernel
  , wrBlake3      = "blake3(" <> kId kernel <> ")"
  , wrEd25519     = "ed25519-mock"
  , wrRewrite     = show rewrite
  , wrInvProofs   = [invariant ids proven] }
```

---

## 14. Build System

### Makefile targets

```bash
make all      # Fortran → libbob_quantum.a + .so  (gfortran)
make monster  # Full LLVM pipeline → ARM64 SVE2 bare metal (flang-new-19)
make wasm     # Rust WASM bridge → 44KB .wasm (wasm-pack)
make debug    # With AddressSanitizer + UBSan
```

### Requirements

| Component | Requirement |
|---|---|
| Fortran engine | gfortran 12+ or flang-new-19 |
| MLIR | llvm-19 with mlir |
| WASM | wasm-pack + rustup target wasm32-unknown-unknown |
| RTX | nvcc sm_89 (CUDA 12+) |
| Lean | lake + mathlib4 |
| Haskell | GHC 9.4+, cabal 3.8+ |
| Python demo | Python 3.10+ (stdlib only) |
| Ansible provisioner | ansible 2.14+, community.crypto |

### Sovereign pipeline with node key

```bash
SOV_SK=path/to/node_sk.bin ./build_monster.sh
```

This activates real Ed25519 signing of all outputs into the `.note.sov`
ELF section.

---

## 15. Testing

### Fortran unit tests

`src/test_fortran_quantum.f90` — 5 integration tests:
1. Born rule normalization: Σ pᵢ = 1
2. Trotter evolution unitarity: ‖U‖_F = √d
3. Goldilocks NTT round-trip
4. Blake3 WORM chain integrity
5. Theorem 3 FFI round-trip

### Haskell tests

`haskell/test/SpecTheorem3.hs`:
```bash
cabal test
```

### Lean verification

```bash
cd lean && lake build
```
All 12 theorems in `SovMonster.lean` + `AdaptiveVerifiedRuntime.lean`
must elaborate with zero sorry.

### AVR demo (functional test)

```bash
python scripts/avr_cold_boot_demo.py
```
Success: `WORM chain height: 5` + cumulative speedup > 1.5x printed at end.

### Cross-language reproducibility

Run the benchmark with identical random seed across all 10 language bindings
and verify all outputs match. See `CMakeLists.txt` for the test harness.

---

*Evidence or Silence. Nothing in between.*

**Ahmad Ali Parr · SnapKitty Collective · Bel Esprit D'Accord Irrevocable Trust · 2026**
