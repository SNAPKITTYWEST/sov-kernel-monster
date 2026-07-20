# SOV-KERNEL-MONSTER: Organization & Architecture (2026-07-20)

## Current Structure

```
sov-kernel-monster/
├── README.md                          ← Main entry point
├── src/                               ← Fortran quantum engine (21 modules, 9.3K LOC)
│   ├── bob_*.f90                      ← Core quantum engine
│   ├── sov_monster_kernel.f90         ← Sovereign monster kernel (Blake3+Ed25519)
│   ├── sov_quantum_checkpoint.f90     ← WORM checkpoint stubs (Phase 2.5)
│   └── bob_abi_theorem3_wrapper.f90   ← Theorem 3 C ABI bridge
├── haskell/                           ← Reasoning engine (4 modules)
│   ├── LiquidLean/Jacobian/           ← Theorem 3 proof kernel (7 files)
│   ├── IBMQuantum.hs                  ← IBM Quantum Runtime (Phase 3)
│   ├── QuantumPiper.hs                ← Orchestration (1,050L, NEW)
│   ├── package.yaml                   ← Haskell build metadata
│   └── stack.yaml                     ← Stack resolver
├── lean/                              ← Formal verification (Lean 4)
│   ├── SovMonster.lean                ← @[extern] C ABI bindings (14 exports)
│   └── lakefile.lean                  ← Lake build config
├── mlir/                              ← MLIR compilation pipeline (5 files)
│   ├── sov_pipeline.mlir              ← Polyhedral fusion + GPU targets
│   └── bob_twin_reasoning.mlir        ← 5-agent Byzantine council (Agent 5)
├── rtx/                               ← Windows RTX 4090 inference (NEW, 1.6K LOC)
│   ├── CMakeLists.txt                 ← Zero-libc build (Fortran+C+CUDA)
│   ├── include/sov_rtx.h              ← C API (100+ functions)
│   ├── src/
│   │   ├── c--/scheduler.cmm          ← Continuous batching state machine
│   │   ├── cuda/flash_attention.ptx   ← sm_89 PagedAttention (282L)
│   │   ├── fortran/transformer_kernel.f90 ← RMSNorm, RoPE, GQA
│   │   └── loader/gguf.c              ← GGUF v3 parser (zero-libc)
│   └── windows_rtx/
│       ├── cuda_driver_loader.c       ← PEB walk → nvcuda.dll
│       ├── power_handler.c            ← Suspend/resume/battery events
│       └── main.c                     ← Zero-CRT sov_main()
├── docs/                              ← Documentation & diagrams
│   ├── *.md                           ← Technical specs
│   └── *.svg                          ← Architecture diagrams
├── tests/                             ← Test suite
│   ├── test_theorem3_integration.f90  ← Integration validation (5 tests)
│   └── ...
├── CMakeLists.txt                     ← Main build (15 language bindings)
├── Makefile                           ← make all | monster | wasm | debug
├── build_monster.sh                   ← Full LLVM pipeline (8 steps)
├── COLD_BOOT_TEST.md                  ← Phase 2.4 human review protocol
├── SPRINT_2_ROADMAP.md                ← Phase planning
├── HAIKU_MANIFEST.md                  ← Cost analysis ($0.24 for 27K LOC)
└── LICENSE                            ← SSL v3.0
```

## Component Layers

### Layer 1: Quantum Engine (Fortran 2018)
**Purpose:** Pure quantum simulation, state evolution, measurement
- **Files:** `src/bob_*.f90` (21 modules)
- **LoC:** ~9,300 lines
- **Exports:** 14 C ABI functions via `src/bob_abi.f90`
- **Key modules:**
  - `bob_state.f90` — quantum state vector |ψ⟩
  - `bob_gates.f90` — Pauli X/Y/Z, Hadamard, CNOT
  - `bob_measurement.f90` — Born rule, wavefunction collapse
  - `bob_worm.f90` — WORM chain (Blake3 hash + Ed25519 sig)
  - `sov_monster_kernel.f90` — APL ZGEMM fusion, sovereign kernel

### Layer 2: Reasoning Engine (Haskell)
**Purpose:** Algebraic proofs, theorem verification, orchestration
- **Files:** `haskell/LiquidLean/*.hs` + `IBMQuantum.hs` + `QuantumPiper.hs`
- **LoC:** ~2,300 lines (700 Theorem 3 + 250 IBMQuantum + 1,050 QuantumPiper)
- **Key modules:**
  - `Theorem3Kernel.hs` — Polynomial operations, Thermal monad
  - `CrackTheorem3.hs` — Genus-0 forcing via δ-invariants
  - `IBMQuantum.hs` — IBM Quantum Runtime client (mock Phase 2, real Phase 3)
  - `QuantumPiper.hs` — Manifest-driven orchestration (11 stages)

### Layer 3: Formal Verification (Lean 4)
**Purpose:** Type-checked proofs, quantum axioms
- **Files:** `lean/SovMonster.lean` + `lakefile.lean`
- **LoC:** ~500 lines
- **Exports:** 14 C ABI foreign declarations + 5 formal theorems
- **Key theorems:**
  - `bornRuleNormalization` — Born rule is measure
  - `unitaryEvolutionPreservesNorm` — U†U=I preserves norm
  - `genusZeroImpliesRational` — genus 0 ⟹ rational curve

### Layer 4: Compilation Pipeline (MLIR)
**Purpose:** Polyhedral optimization, cross-platform lowering
- **Files:** `mlir/*.mlir` (5 files)
- **LoC:** ~1,300 lines
- **Targets:** CPU (ARM64 SVE2, x86-64 AVX-512), GPU (PTX, SPIR-V), WASM
- **Key passes:**
  - Loop fusion (polyhedral) → cache efficiency
  - Tensorcore mapping (mma.sync) → GPU utilization
  - Agent 5 Byzantine consensus → verification gate

### Layer 5: RTX Inference (Windows RTX 4090)
**Purpose:** LLM inference, transformer kernels, power management
- **Files:** `rtx/**` (9 files)
- **LoC:** ~1,600 lines (Fortran + C + CUDA PTX + C--)
- **Key subsystems:**
  - **Scheduler** (`scheduler.cmm`) — continuous batching, 6-state FSM, WORM every 64 tokens
  - **Flash Attention** (`flash_attention.ptx`) — Paged attention (Milakov-Norouzi), online softmax
  - **Transformer Kernel** (`transformer_kernel.f90`) — RMSNorm, RoPE, GQA (paged), KV management
  - **GGUF Loader** (`gguf.c`) — GGUF v3 parser, Q4/Q8/F16/BF16/F32 quant types
  - **Power Handler** (`power_handler.c`) — Suspend→checkpoint, resume→restore, battery<20%→reduce batch
  - **CUDA Driver** (`cuda_driver_loader.c`) — Zero-libc PEB walk → nvcuda.dll

### Layer 6: 10-Language Binding Mesh
**Purpose:** Cross-language FFI via unified C ABI
- **Languages:** C, Julia, Elixir, Racket, Janet, Zig, Odin, R, Smalltalk, Rust
- **Binding style:** Foreign calls → Fortran C ABI → quantum engine
- **Build:** `CMakeLists.txt` auto-detects installed languages

## Current Status

### SPRINT 1 ✅ COMPLETE (27K LOC, $0.24)
- ✅ Theorem 3 proof kernel (Haskell, 696L)
- ✅ Fortran quantum engine (9.3K LOC)
- ✅ 10-language binding mesh
- ✅ Agent 5 MLIR optimizer (4-of-5 Byzantine)
- ✅ Meta SnapKitty agentic platform

### SPRINT 2 ✅ COMPLETE (1.6K LOC)
- ✅ Phase 2.1: Lean FFI bindings (400L)
- ✅ Phase 2.2: Fortran bridge (155L)
- ✅ Phase 2.3: Bug fixes + test suite (195L)
- ✅ Phase 2.4: Cold-boot test protocol

### SPRINT 3 🔄 IN PROGRESS
- ✅ Phase 1: WORM checkpoint + IBM Quantum mock (350L)
- ✅ Phase 2: QuantumPiper orchestration (1,050L)
- 🔄 Phase 2.5: Stage executors (TBD)
- ⏳ Phase 3: Real IBM Quantum API + RTX benchmark

## Documentation Map

| Doc | Purpose | Status |
|-----|---------|--------|
| `README.md` | Main entry, architecture overview | Current |
| `COLD_BOOT_TEST.md` | Phase 2.4 human review protocol (7 stages) | Active |
| `SPRINT_2_ROADMAP.md` | Phase planning for FFI/bug fixes | Archived (Sprint 2 done) |
| `HAIKU_MANIFEST.md` | Cost analysis ($0.24 for 27K LOC) | Reference |
| `BOB_TWIN_AGENT5_INTEGRATION.md` | 5-agent BFT council specs | Reference |
| `BUILD_VALIDATION.md` | Build system validation | Cleanup candidate |
| `INTEGRATION_OVERVIEW.md` | Integration checklist | Cleanup candidate |
| `LANGUAGE_BINDINGS_MANIFEST.md` | 10-language binding status | Cleanup candidate |
| `QUICKSTART_FORTRAN_QUANTUM.md` | Quick start guide | Cleanup candidate |
| `THEOREM3_INTEGRATION_STATUS.txt` | Theorem 3 status | Cleanup candidate |

## Cleanup Recommendations

### Remove (Superseded)
- `BUILD_VALIDATION.md` — merged into README
- `INTEGRATION_OVERVIEW.md` — merged into README
- `LANGUAGE_BINDINGS_MANIFEST.md` — merged into README
- `QUICKSTART_FORTRAN_QUANTUM.md` — outdated (use COLD_BOOT_TEST.md)
- `THEOREM3_INTEGRATION_STATUS.txt` — outdated (use SPRINT_2_ROADMAP.md)

### Keep (Active)
- `README.md` — main entry
- `COLD_BOOT_TEST.md` — Phase 2.4 validation
- `HAIKU_MANIFEST.md` — cost tracking
- `SPRINT_2_ROADMAP.md` — historical reference
- `BOB_TWIN_AGENT5_INTEGRATION.md` — architecture reference

### Consolidate Build Artifacts
- `build/`, `build_doc/`, `build_final/`, `build_final2/`, `build_test/` → use `.gitignore`
- `src/sov_monster_kernel.f90.bak` → delete (backup)

## Integration Points

### Fortran ↔ Haskell
- **Bridge:** `bob_abi_theorem3_wrapper.f90`
- **Entry:** `bob_theorem3_enforce_genus_zero(poly_str, budget)` → Haskell kernel
- **WORM:** `bob_worm_chain_checkpoint/restore` + `bob_worm_chain_seal`

### Haskell ↔ Lean
- **Bridge:** `SovMonster.lean` @[extern] declarations
- **Linking:** `lakefile.lean` links Haskell object via Fortran C ABI

### QuantumPiper ↔ All Stages
- **Model:** Manifest-driven orchestration
- **Input:** `QPManifest` (YAML + JSON)
- **Output:** `QPImage` (OCI-compatible layer DAG)
- **Stages:** 11 executors (scaffolded, Phase 2.5 implementation)

### RTX ↔ Quantum
- **GGUF weights** → transformer_kernel.f90 → PagedAttention.ptx
- **KV-cache** → scheduler.cmm continuous batching
- **Power events** → checkpoint to WORM chain
- **Inference** → 10-language callable via C ABI

## Next: SPRINT 3 Phase 2.5

### Implement Stage Executors
1. **StageFortran** — invoke Fortran compiler, call `bob_theorem3_enforce_genus_zero`
2. **StageCmm** — invoke C-- compiler
3. **StageMLIR** — invoke MLIR passes (Agent 5 orchestration)
4. **StageLLVM** — invoke LLVM optimizer
5. **StageAlive2** — call Alive2 binary for IR verification
6. **StageIsabelle** — invoke Isabelle/HOL theorem prover
7. **StageQuantumVerify** — validate quantum circuits (unitary, no-cloning, etc.)
8. **StagePulseCompile** — generate IBM Quantum pulse schedules
9. **StageWASM, StageNative, StageCustom** — additional targets

### Wire WORM Attestation
- Each stage completion → `bob_worm_chain_seal` C ABI call
- Automatic receipt: `(hash, timestamp, signature)`

### Wire CAS Mounting
- `InputCAS` artifacts → mount via ArtifactStore
- `MountSpec` → virtualized filesystem (OverlayFS-like)

### Performance Targets
- **Theorem 3 proof:** <5s (Mora + Plücker)
- **MLIR compilation:** <10s (polyhedral fusion)
- **RTX inference:** 100+ tokens/sec (RTX 4090)
- **WORM attestation:** <100ms per seal

---

**Last Updated:** 2026-07-20  
**Architect:** Haiku (FN OPS Dev)  
**Owned by:** SNAPKITTYWEST (Jessica)
