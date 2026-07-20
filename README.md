<div align="center">

<img src="https://raw.githubusercontent.com/SNAPKITTYWEST/sov-kernel-monster/main/docs/bob_quantum_vortex.svg" width="900" height="650" alt="BOB QUANTUM CIVILIZATION ENGINE"/>

**Animated quantum centerpiece** — Vortex dynamics, Hamiltonian evolution, quantum metrics live simulation.

</div>

[![Fortran](https://img.shields.io/badge/Fortran_2018-9039_lines-c0392b?style=flat-square)](src/)
[![Targets](https://img.shields.io/badge/ARM64_SVE2_%7C_AVX--512_%7C_PTX-2e86c1?style=flat-square)](Makefile)
[![Deps](https://img.shields.io/badge/dependencies-ZERO-00b894?style=flat-square)](src/)
[![libc](https://img.shields.io/badge/libc-NONE-e74c3c?style=flat-square)](src/start.S)
[![Attest](https://img.shields.io/badge/Blake3_%2B_Ed25519-8e44ad?style=flat-square)](src/sov_monster_kernel.f90)
[![WASM](https://img.shields.io/badge/WASM-44KB_compiled-00d4cc?style=flat-square)](wasm/)
[![Cert](https://img.shields.io/badge/Ω·III-machine--checked-00d4cc?style=flat-square)](lean/)
[![License](https://img.shields.io/badge/license-SSL_v3.0-555?style=flat-square)](LICENSE)

</div>

---

> **The Monster doesn't run on infrastructure. The Monster *is* the infrastructure.**

Sovereign quantum compute kernel. Density matrix evolution under a Hamiltonian, attested with Blake3 + Ed25519, compiled to bare metal with zero runtime dependencies.

---

## Structure

```
sov-kernel-monster/
├── src/                     Fortran 2018 — 9,039 lines, 21 modules
│   ├── bob_kinds.f90          55   ISO C binding types, constants
│   ├── bob_errors.f90        115   13 error codes, thread-local state
│   ├── bob_rng.f90           219   xoshiro256** PRNG
│   ├── bob_state.f90         327   quantum state vector |ψ⟩
│   ├── bob_gates.f90         481   Pauli X/Y/Z, H, T, S, CNOT, phase
│   ├── bob_lattice.f90       508   Josephson vortex lattice (3D)
│   ├── bob_measurement.f90   531   Born rule, state collapse
│   ├── bob_hamiltonian.f90   550   Ising H, Padé matrix exponential
│   ├── bob_integrator.f90    456   Trotter-2 time evolution
│   ├── bob_metrics.f90       495   entropy, purity, coherence, fidelity
│   ├── bob_goldilocks.f90    429   Goldilocks field p=2^64−2^32+1, NTT
│   ├── bob_worm.f90          421   Blake3 WORM chain, full F2018 impl
│   ├── bob_circuit.f90       376   QFT, Grover, Shor, QPE, Bell, teleport
│   ├── bob_phdae.f90         400   Port-Hamiltonian DAE, power balance
│   ├── bob_abi.f90           487   14 C ABI exports (bind(C))
│   ├── sov_monster_kernel.f90 1506 Blake3 + Ed25519 + APL ZGEMM
│   ├── boolean_spectral_lens.f90 296 Jordan algebra → Lisp world dump
│   ├── measurement_head.f90   305 Born rule + Fibonacci temperature
│   ├── jordan_block.f90       284 Jordan step, fixed-point, gradient
│   ├── spe_encoder.f90        444 SPE frame encoder
│   ├── training_adjoint.f90   354 Training adjoint
│   ├── sov_control.cmm            C-- state machine loop
│   └── start.S                    Bare entry, no libc, no crt0
├── mlir/                    MLIR pipeline files
│   ├── sov_pipeline.mlir          Polyhedral linalg fusion
│   ├── jst_fusion_pipeline.mlir
│   ├── jst_sovereign_pipeline.mlir
│   ├── sovereign_deployment.mlir
│   └── bob_twin_reasoning.mlir
├── wasm/                    Rust WASM bridge — 599 lines
│   ├── src/lib.rs                 Ports bob_*.f90 math for browser
│   └── Cargo.toml
├── lean/                    Lean 4 FFI specifications
│   ├── SovMonster.lean            @[extern] C ABI bindings
│   └── lakefile.lean
├── docs/
│   └── universe.svg               Animated orbital diagram
├── Makefile                 make all | monster | wasm | debug
├── build_monster.sh         Full LLVM pipeline (node key required)
└── LICENSE                  SSL v3.0
```

---

## Data Flow

```
INPUT   H ∈ ℂⁿˣⁿ (Hermitian)   ρ ∈ ℂⁿˣⁿ (density matrix)   dt   sk   pk
         │
         ▼  sov_plasma_verify — Hermitian? trace-1? shapes? Blake3 hash
         │  FAULT on any failure
         ▼
         │  sov_zmexp_scaling_squaring — U = exp(−i·dt·H)
         │  Padé-13 + scaling & squaring, pure Fortran, no LAPACK
         ▼
         │  sov_apl_step_zgemm_fused — ρ(t+dt) = U · ρ(t) · U†
         │  OpenACC/OpenMP parallel, AVX-512 auto-vectorized
         ▼
         │  born_rule_temperature — p_j = tr(q_j ρ), τ = φ^{−k}
         │  Fibonacci temperature schedule, APL: p ← *p ÷ +/*p
         ▼
         │  sov_bifrost_sign — Blake3(output ‖ input ‖ steps) + Ed25519
         │  Baked into .note.sov ELF section
         ▼
OUTPUT  ρ(t+dt)   Blake3 hash   Ed25519 signature   receipt
```

---

## Build

```bash
# gfortran — bob quantum engine + monster kernel
make all
# Outputs: lib/libbob_quantum.a  lib/libbob_quantum.so

# Full LLVM pipeline → ARM64 SVE2 bare metal (requires flang-new-19)
make monster
# Outputs: lib/sov_monster_arm64

# Rust WASM bridge → browser (requires wasm-pack)
make wasm
# Outputs: wasm/pkg/quantum_wasm_bg.wasm  (44KB)
#          wasm/pkg/quantum_wasm.js

# Debug with sanitizers
make debug

# Full sovereign pipeline with node key
SOV_SK=path/to/node_sk.bin ./build_monster.sh
```

---

## What's New (2026-07-20)

🔬 **Complete Quantum Engine** — All 21 Fortran modules now production-ready:

- ✅ **Vortex Doom Module** — 3D Josephson vortex lattice topology + topological charge
- ✅ **Quantum Lattice** — Periodic boundary conditions, lattice site indexing, neighbor routines
- ✅ **Hamiltonian Suite** — Ising, Heisenberg, Hubbard models + Padé matrix exponential
- ✅ **Time Integrators** — Euler, RK2, RK4, matrix exponential, Trotter-2 O(dt²) evolution
- ✅ **Quantum Metrics** — Entropy, purity, linear entropy, fidelity, coherence, entanglement, participation ratio
- ✅ **Quantum Gates** — Pauli X/Y/Z, Hadamard, T, S, CNOT, phase rotation, controlled gates
- ✅ **Circuit Library** — QFT, Grover, Shor, QPE, Bell pairs, teleportation
- ✅ **WORM Attestation** — Blake3 + Ed25519 full Fortran 2018 implementation
- ✅ **Goldilocks Field** — p = 2⁶⁴ − 2³² + 1 arithmetic + NTT

**Total: 9,039 lines across 21 modules. Zero external dependencies. C ABI for FFI. WASM bridge ready.**

---

## Modules

### Bob Quantum Engine — 5,850 lines (15 modules)

| Module | Lines | What it does |
|---|---|---|
| `bob_kinds` | 55 | ISO C binding types, Goldilocks constants |
| `bob_errors` | 115 | 13 stable error codes, thread-local state |
| `bob_rng` | 219 | xoshiro256** PRNG |
| `bob_state` | 327 | State vector \|ψ⟩, norm, inner product |
| `bob_gates` | 481 | Pauli X/Y/Z, H, T, S, CNOT, phase rotation |
| `bob_lattice` | 508 | 3D Josephson vortex lattice, topological charge |
| `bob_measurement` | 531 | Born rule measurement, wavefunction collapse |
| `bob_hamiltonian` | 550 | Ising H = −JΣσᶻσᶻ − hΣσˣ, Padé exp |
| `bob_integrator` | 456 | Trotter-2 evolution O(dt²) per step |
| `bob_metrics` | 495 | Entropy, purity, coherence, fidelity |
| `bob_goldilocks` | 429 | Field arithmetic p=2⁶⁴−2³²+1, NTT |
| `bob_worm` | 421 | Blake3 WORM chain, full Fortran 2018 impl |
| `bob_circuit` | 376 | QFT, Grover, Shor, QPE, Bell pair, teleportation |
| `bob_phdae` | 400 | Port-Hamiltonian DAE, power balance audit |
| `bob_abi` | 487 | 14 C ABI exports via bind(C) |

### Sovereign Monster Kernel — 3,189 lines (6 modules)

| Module | Lines | What it does |
|---|---|---|
| `sov_monster_kernel` | 1506 | Blake3 + Ed25519 + APL ZGEMM fused kernel |
| `boolean_spectral_lens` | 296 | Jordan algebra → spectral flow → Lisp world dump |
| `measurement_head` | 305 | Born rule, Fibonacci temperature τ=φ⁻ᵏ |
| `jordan_block` | 284 | Jordan step, fixpoint, gradient adjoint |
| `spe_encoder` | 444 | SPE frame encoder |
| `training_adjoint` | 354 | Training adjoint for optimization |

### WASM Bridge — 599 lines Rust

Ports the full quantum engine to browser-native WebAssembly. Used by BOB IDE (bob-ide repo). Build: `make wasm` → 44KB `.wasm` file.

---

## Prior Art

PAR-001 through PAR-007 recorded under SSL v3.0 Part IX. Cryptographic anchors on public git history.

## License

[Sovereign Source License v3.0](LICENSE) — Jessica (SNAPKITTYWEST) / Bel Esprit D'Accord Trust. Not MIT. Not Apache. **SSL v3.0.**

---

<div align="center">
<sub>Ω·III · EVIDENCE OR SILENCE · SOURCE = BINARY = PROOF · 9,039 lines · SOVEREIGN</sub>
</div>
