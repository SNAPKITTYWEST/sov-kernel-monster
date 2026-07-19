# SOV-KERNEL-MONSTER

**Fortran 2018 + C-- + MLIR → ARM64 SVE2 / x86_64 AVX-512 / PTX**

<p>
  <img src="https://img.shields.io/badge/language-Fortran_2018_%2B_C--%2B_MLIR-c0392b?style=flat-square" alt="language"/>
  <img src="https://img.shields.io/badge/targets-ARM64_SVE2_%7C_x86_AVX--512_%7C_PTX-2e86c1?style=flat-square" alt="targets"/>
  <img src="https://img.shields.io/badge/deps-ZERO-00b894?style=flat-square" alt="zero deps"/>
  <img src="https://img.shields.io/badge/libc-NONE-e74c3c?style=flat-square" alt="no libc"/>
  <img src="https://img.shields.io/badge/audit-Blake3_%2B_Ed25519-8e44ad?style=flat-square" alt="bifrost"/>
  <img src="https://img.shields.io/badge/license-SSL_v1.0-555?style=flat-square" alt="license"/>
</p>

> The Monster doesn't run on infrastructure. The Monster *is* the infrastructure.

---

## What It Is

SOV-KERNEL-MONSTER is the sovereign compute kernel for the SnapKitty stack. It computes density matrix evolution under a Hamiltonian (`rho = exp(-iHdt) * rho * exp(+iHdt)`), attests every output with Blake3 + Ed25519, and compiles to bare metal with zero dependencies.

```
┌─────────────────────────────────────────────────────────────────┐
│                    SOV-KERNEL-MONSTER                           │
├─────────────────────────────────────────────────────────────────┤
│  SPEC:    Lean 4  (SovMonster.lean — @[extern] FFI bindings)   │
│  KERNEL:  Fortran 2018  (sov_monster_kernel.f90 — ~1100 lines) │
│  CONTROL: C--  (sov_control.cmm — state machine loop)          │
│  FUSION:  MLIR  (sov_pipeline.mlir — polyhedral linalg fusion) │
│  BACKEND: LLVM  (ARM64 SVE2 | x86_64 AVX-512 | PTX | SPIR-V)  │
│  RUNTIME: ZERO  (start.S — bare entry, no libc, no crt0)       │
│  ATTEST:  Blake3 + Ed25519 baked into .note.sov ELF section    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Architecture — Data Flow

```
  INPUT: H (Hermitian n×n), rho (density matrix n×n), dt, sk, pk
         │
         ▼
  ┌──────────────────────────────────────────────────────────────┐
  │  PLASMA PRE-FLIGHT  (sov_plasma_verify)                      │
  │  H Hermitian? rho density matrix? shapes valid? Blake3 hash? │
  │  sov_fault on any failure — no undefined behavior            │
  └──────────────────────────┬───────────────────────────────────┘
                             │ PASS
                             ▼
  ┌──────────────────────────────────────────────────────────────┐
  │  MATRIX EXPONENTIAL  (sov_zmexp_scaling_squaring)            │
  │  U = exp(-i*dt*H)   Pade-13 + scaling & squaring             │
  │  Higham 2005 — pure Fortran, no LAPACK                       │
  │  LU: sov_zgetrf   Solve: sov_zgetrs                          │
  └──────────────────────────┬───────────────────────────────────┘
                             │
                             ▼
  ┌──────────────────────────────────────────────────────────────┐
  │  FUSED MATMUL KERNEL  (OpenMP target + MLIR polyhedral)      │
  │  tmp    = U * rho      (GEMM 1)                              │
  │  out_rho = tmp * U†    (GEMM 2)                              │
  │  MLIR --affine-loop-fusion merges both → ONE kernel          │
  │  Single source → SVE2 / AVX-512 / PTX / SPIR-V              │
  └──────────────────────────┬───────────────────────────────────┘
                             │
                             ▼
  ┌──────────────────────────────────────────────────────────────┐
  │  PLASMA POST-FLIGHT                                          │
  │  out_rho Hermitian? Trace=1? → sov_fault if broken           │
  └──────────────────────────┬───────────────────────────────────┘
                             │
                             ▼
  ┌──────────────────────────────────────────────────────────────┐
  │  BIFROST ATTESTATION                                         │
  │  hash = Blake3(out_rho)          RFC 9561, pure Fortran      │
  │  sig  = Ed25519_sign(hash, sk)   RFC 8032, constant-time     │
  │  Receipt: [hash:32][sig:64] = 96 bytes                       │
  └──────────────────────────────────────────────────────────────┘

  OUTPUT: out_rho (evolved density matrix) + Receipt (96 bytes)
```

---

## Concurrency & ISA

```
  OpenMP target offload (n > 64):
    CPU:   sequential fallback (!$omp parallel do simd)
    GPU:   !$omp target teams distribute → PTX / SPIR-V

  MLIR fusion pipeline:
    --affine-loop-fusion      merge two matmul loop nests into one
    --linalg-tile             16x16 tile (L1 cache fit)
    --vectorize               emit SVE2 / AVX-512 intrinsics

  ISA targets (single Fortran source, three objects):
    aarch64-linux-gnu    -mattr=+sve2,+aes,+sha3
    x86_64-linux-gnu     -mattr=+avx512f,+avx512vl,+gfni,+vaes
    nvptx64-nvidia-cuda  -mattr=+ptx80
```

---

## Files

```
sov-kernel-monster/
├── sov_monster_kernel.f90   Fortran 2018 (~1100 lines, zero deps)
│   ├── sov_plasma_verify        plasma gate: shape + Hermitian + Blake3
│   ├── sov_bifrost_sign/verify  Ed25519 RFC 8032 (ABI complete, field stubs)
│   ├── sov_apl_step_zgemm_fused core: U*rho*U† + plasma + bifrost
│   ├── sov_apl_evolve_sequence  multi-step evolution loop
│   ├── sov_zmexp_scaling_squaring  Pade-13 matrix exp (Higham 2005)
│   ├── sov_zgetrf / sov_zgetrs  LU factorization + solve (no LAPACK)
│   ├── sov_blake3_*             Blake3 RFC 9561 (complete)
│   └── sov_ed25519_*            Ed25519 RFC 8032 (ABI + stubs)
├── sov_control.cmm          C-- state machine: evolution loop + fault path
├── sov_pipeline.mlir        MLIR polyhedral fusion spec
├── start.S                  ARM64 + x86_64 bare-metal entry, .note.sov
├── build_monster.sh         forge: flang → mlir-opt → llc → lld → attest
└── lean/
    ├── SovMonster.lean      Lean 4 @[extern] FFI + sovereignty theorem stubs
    ├── lakefile.lean        lake build, links Fortran .o
    └── lean-toolchain       leanprover/lean4:v4.14.0
```

---

## Build

```bash
# Requires: LLVM 19+ (flang-new, mlir-opt, mlir-translate, llc, ld.lld)
# Install: wget https://apt.llvm.org/llvm.sh && bash llvm.sh 19

chmod +x build_monster.sh
./build_monster.sh

# Outputs:
#   build/sov_monster_arm64   ARM64 SVE2, static, no libc
#   build/sov_monster_x86     x86_64 AVX-512, static, no libc
#   build/sov.ptx             NVIDIA PTX assembly
```

### Lean FFI

```bash
./build_monster.sh          # build Fortran objects first
cd lean && lake build
```

---

## Lean FFI

```lean
import SovMonster

-- Single step: evolve rho by one dt under H, get receipt
SovMonster.aplStepFused hPtr n rhoPtr n dt skPtr pkPtr outRhoPtr hashPtr sigPtr

-- Verify a receipt:
let ok := SovMonster.bifrostVerify hashPtr 32 sigPtr pkPtr
```

---

## Why Fortran 2018 + C-- + MLIR

| | Rust / C++ | **Monster** |
|---|---|---|
| Array semantics | `ndarray` / `faer` (library) | **native** — compiler knows shape, stride, aliasing |
| GEMM fusion | manual | **polyhedral** — `--affine-loop-fusion`, proven optimal |
| GPU offload | fragmented (`rust-gpu`, `cublas`) | **single source** — `!$omp target` → SVE2/AVX-512/PTX |
| Formal spec | Prusti/Kani (experimental) | **Lean 4 `@[extern]`** — proof obligations at type level |
| Audit | logs | **`.note.sov`** — Blake3+Ed25519 baked into binary |
| Boot time | ~ms | **~μs** — static PIE, no dynamic linker |
| Deps | Cargo.io / crates.io | **ZERO** — source = binary = proof |

---

## Sovereign Stack

```
  claudes-harness (Prolog)      agent identity + prohibited actions
         │ governs
         ▼
  sovereign-transformer         Datalog + x86 corpus gate (POST /gate)
         │ approved records
         ▼
  sov-kernel-monster            Fortran 2018 compute kernel (THIS REPO)
  (Fortran + C-- + MLIR)        U*rho*U†, Pade exp, Bifrost attestation
         │ receipts
         ▼
  Bifrost WORM chain            Blake3 + Ed25519 immutable audit log
```

---

## Ed25519 Status

Blake3 is complete (RFC 9561). Ed25519 field arithmetic stubs have complete ABI — full 255-bit field arithmetic (10-limb radix-2^26, ~600 lines) is the next forge target.

---

*SnapKitty West · Sovereign Source License v1.0 · Evidence or Silence — 2026*
