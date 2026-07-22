# ADR-000: Architecture Foundation and Clean-Room Approach

**Status:** ACCEPTED  
**Date:** 2026-07-21  
**Deciders:** ROLE-SYSTEM-ARCHITECT, ROLE-INTEGRATOR  
**Tags:** architecture, clean-room, legal, foundation

## Context

We are building a quantum computing compiler and runtime system that must:
1. Support OpenQASM 2 and 3 as input languages
2. Introduce an experimental successor language (MetaQASM-4)
3. Integrate with IBM i operational patterns
4. Provide formal verification through Liquid Haskell and Lean 4
5. Remain legally independent from proprietary IBM implementations
6. Achieve production-grade quality with 15,000+ substantive lines of code

The project must navigate complex legal, technical, and verification requirements while maintaining clean-room development practices.

## Decision

We adopt a **multi-layered clean-room architecture** with the following principles:

### 1. Clean-Room Methodology

**Research → Specification → Implementation**

- **Research Phase:** Study only public sources (standards, documentation, papers)
- **Specification Phase:** Design original architecture based on public knowledge
- **Implementation Phase:** Write independent code from specifications

All external sources must be recorded in RESEARCH_LEDGER.md with provenance.

### 2. Language Strategy

**Input Languages:**
- OpenQASM 2.0 (public standard)
- OpenQASM 3.x (public standard, current version 3.1)

**Original Languages:**
- **MetaQASM-4:** Experimental typed quantum assembly language
  - NOT OpenQASM 4 (which doesn't exist as a public standard)
  - Extends OpenQASM 3 with typed effects, monadic semantics, refinement types
  - Original contribution of this project
  
- **ShadowRPG-Q:** IBM i-inspired operational control language
  - NOT an IBM product
  - Original job control and quantum orchestration DSL

### 3. Multi-Language Implementation

**Systems Core:** Rust
- Compiler, IR, optimizer, simulator, runtime
- Memory-safe, deterministic, high-performance
- C-compatible FFI for IBM i integration

**Operational Control:** RPG / RPG-compatible layer
- IBM i job management, queues, journals
- Portable emulation when native IBM i unavailable
- ShadowRPG-Q parser and executor

**Verification:** Liquid Haskell + Lean 4
- Liquid Haskell: Refinement types, witness generation
- Lean 4: Formal proofs, theorem checking
- No sorry/admit in accepted proofs

**Infrastructure:** MLIR + LLVM
- Quantum dialect design
- Lowering passes
- Code generation

**Interface:** WebAssembly
- Portable execution
- Browser and server deployment

**Governance:** Prolog
- Symbolic policy enforcement
- Capability reasoning

### 4. Python Prohibition

Python is **PROHIBITED** from:
- Production runtime
- Build system
- Compiler pipeline
- Test infrastructure
- Deployment

Rationale: Ensure independence from Python-based Qiskit implementation.

### 5. Intermediate Representation Family

**QATAAUM IR** (9 levels):
1. Source AST (lossless syntax)
2. Typed Quantum AST (resolved, typed)
3. QATAAUM-CFG (control flow graph)
4. QATAAUM-SSA (static single assignment)
5. QATAAUM-GATE (hardware-independent gates)
6. QATAAUM-TOPO (topology-aware, routed)
7. QATAAUM-SCHEDULE (time-aware, scheduled)
8. QATAAUM-PULSE (pulse-level, provider-neutral)
9. QATAAUM-EXEC (executable package with proofs)

Each IR level has:
- Formal syntax
- Type system
- Verification conditions
- Transformation rules

### 6. Hybrid Finite-State Machine

Classical IBM i control states + Quantum execution states:

**States:** RECEIVED → VALIDATED → PARSED → TYPED → IR_GENERATED → PROOF_OBLIGATIONS → OPTIMIZED → TARGET_SELECTED → ROUTED → SCHEDULED → PULSE_LOWERED → VERIFIED → QUEUED → EXECUTING → MEASURED → MITIGATED → RECEIPT_SEALED → COMPLETED

**Error States:** FAILED, RECOVERING, REJECTED

All transitions are:
- Deterministic
- Journaled
- Replayable
- Cryptographically sealed

### 7. Processor Abstraction

Processors are **data**, not hard-coded assumptions:

**Profile Schema:**
- Provider, family, revision
- Qubit count, connectivity graph
- Native instruction families
- Timing constraints
- Capability flags
- Public evidence references
- UNKNOWN markers for undocumented properties

**Public Processors:**
- Eagle, Osprey, Condor (historical)
- Heron r1, r2, r3 (public revisions)
- Nighthawk r1 (public revision, Dec 2025)

**Hypothetical Processors:**
- Heron r4, Nighthawk r2+ (unless publicly documented)
- Must be explicitly labeled as hypothetical

### 8. Formal Verification Strategy

**Liquid Haskell Layer:**
- Refinement types for qubit linearity
- Effect tracking for measurements
- Resource ownership for pulses
- Dependency ordering for scheduling
- Witness generation for Rust runtime

**Lean 4 Layer:**
- Syntax and semantics formalization
- Compiler pass preservation theorems
- FSM transition correctness
- Receipt chain verification
- No sorry/admit in accepted proofs

**Integration:**
- Liquid Haskell generates witnesses
- Rust runtime checks witnesses
- Lean 4 audits witness validity
- Property-based testing in Rust/Haskell

### 9. Quality Gates

Before release, ALL must pass:
- ✅ All sources in research ledger
- ✅ No proprietary code used
- ✅ MetaQASM-4 labeled as experimental
- ✅ No invented processor facts
- ✅ No Python in production
- ✅ FSM deterministic and journaled
- ✅ 15,000+ substantive lines
- ✅ No source padding
- ✅ Deterministic builds
- ✅ All tests pass
- ✅ Lean proofs complete (no sorry)
- ✅ Liquid Haskell refinements pass
- ✅ All ADRs documented

## Consequences

### Positive

✅ **Legal Safety:** Clean-room process protects against IP claims  
✅ **Independence:** Not dependent on Qiskit implementation details  
✅ **Verification:** Formal proofs provide high assurance  
✅ **Flexibility:** Original languages enable research and innovation  
✅ **IBM i Integration:** Native operational patterns for enterprise deployment  
✅ **Portability:** WASM enables broad deployment  
✅ **Transparency:** All decisions documented in ADRs  

### Negative

⚠️ **Complexity:** Multi-language stack increases build complexity  
⚠️ **Effort:** Clean-room process requires extensive documentation  
⚠️ **Toolchain:** Requires Rust, RPG, Haskell, Lean, MLIR, LLVM  
⚠️ **Learning Curve:** Team must understand multiple paradigms  
⚠️ **Verification Cost:** Formal proofs require significant effort  

### Risks

🔴 **Public Specification Gaps:** Some processor details may be undocumented  
🔴 **Toolchain Availability:** IBM i tooling may not be universally available  
🔴 **Proof Complexity:** Some theorems may be impractical to prove  
🔴 **Performance:** Multi-layer architecture may have overhead  

### Mitigations

- Mark unknown processor properties explicitly
- Provide portable RPG-compatible layer
- Prioritize critical proofs, document proof gaps
- Optimize hot paths, benchmark continuously

## Alternatives Considered

### Alternative 1: Fork Qiskit
**Rejected:** Would not be clean-room, would inherit Python dependency, would not achieve IBM i integration goals.

### Alternative 2: Pure Python Implementation
**Rejected:** Violates clean-room independence goal, not suitable for IBM i integration.

### Alternative 3: Single-Language Implementation
**Rejected:** No single language satisfies all requirements (systems programming, formal verification, IBM i integration).

### Alternative 4: No Formal Verification
**Rejected:** Verification is a core project goal and differentiator.

## References

- RESEARCH_LEDGER.md
- CLEAN_ROOM_BOUNDARY.md
- OpenQASM 3 Specification: https://openqasm.com/
- MLIR Documentation: https://mlir.llvm.org/
- Liquid Haskell: https://ucsd-progsys.github.io/liquidhaskell/
- Lean 4: https://lean-lang.org/

## Notes

This ADR establishes the foundation for all subsequent architectural decisions. All future ADRs must be consistent with these principles or explicitly supersede them with justification.

**Next ADRs:**
- ADR-001: MetaQASM-4 Type System
- ADR-002: QATAAUM IR Design
- ADR-003: Hybrid FSM Specification
- ADR-004: ShadowRPG-Q Language Design
- ADR-005: Processor Capability Model

---

**Approved by:** ROLE-SYSTEM-ARCHITECT  
**Review Date:** 2026-07-21  
**Status:** ACCEPTED