# ADR-001: QATAAUM IR Family Design

**Status**: ACCEPTED  
**Date**: 2026-07-21  
**Deciders**: Bob (ROLE-SYSTEM-ARCHITECT)  
**Related**: ADR-000 (Architecture Foundation)

---

## Context

QATAAUM requires a multi-level intermediate representation (IR) to transform OpenQASM source code through progressive lowering stages, from high-level quantum circuits to hardware-executable instructions. The IR must support:

1. Multiple quantum languages (OpenQASM 2, OpenQASM 3, MetaQASM-4)
2. Classical control flow and dynamic circuits
3. Hardware-independent optimization
4. Target-specific compilation (routing, scheduling, pulse)
5. Formal verification at each stage
6. Clean-room implementation without copying Qiskit internals

## Decision

We adopt a **9-level IR family** (QATAAUM-IR-0 through QATAAUM-IR-8) with explicit transformations between levels:

### IR Level 0: Source AST
- **Purpose**: Lossless syntax representation
- **Content**: Direct parse tree from OpenQASM/MetaQASM-4
- **Properties**: Preserves comments, formatting, source locations
- **Verification**: Parser roundtrip property

### IR Level 1: Typed Quantum AST
- **Purpose**: Semantic validation and type checking
- **Content**: Resolved names, types, dimensions, scopes
- **Properties**: Well-typed, no undefined symbols
- **Verification**: Type soundness, linearity checking

### IR Level 2: QATAAUM-CFG
- **Purpose**: Control flow graph representation
- **Content**: Basic blocks, terminators, dominance tree
- **Properties**: Single entry, structured control flow
- **Verification**: CFG well-formedness, reachability

### IR Level 3: QATAAUM-SSA
- **Purpose**: Static single assignment form
- **Content**: Phi nodes, def-use chains, dominance frontiers
- **Properties**: Each variable defined exactly once
- **Verification**: SSA invariants, dominance properties

### IR Level 4: QATAAUM-GATE
- **Purpose**: Hardware-independent gate representation
- **Content**: Quantum gates, measurements, classical operations
- **Properties**: Basis-independent, topology-independent
- **Verification**: Gate semantics preservation

### IR Level 5: QATAAUM-TOPO
- **Purpose**: Target-coupled placement and routing
- **Content**: Physical qubit assignments, SWAP insertions
- **Properties**: Respects connectivity constraints
- **Verification**: Routing legality, semantic equivalence

### IR Level 6: QATAAUM-SCHEDULE
- **Purpose**: Time-aware operation scheduling
- **Content**: Timestamped operations, resource reservations
- **Properties**: No resource conflicts, respects dependencies
- **Verification**: Schedule validity, timing constraints

### IR Level 7: QATAAUM-PULSE
- **Purpose**: Provider-neutral pulse representation
- **Content**: Frames, waveforms, captures, calibrations
- **Properties**: Hardware-agnostic pulse abstraction
- **Verification**: Pulse timing, resource exclusivity

### IR Level 8: QATAAUM-EXEC
- **Purpose**: Backend execution package
- **Content**: Executable instructions, metadata, proof receipts
- **Properties**: Self-contained, deterministic, verifiable
- **Verification**: Execution receipt integrity

## Rationale

### Why 9 Levels?

1. **Separation of Concerns**: Each level addresses a distinct compilation phase
2. **Incremental Verification**: Verify properties at each transformation
3. **Optimization Opportunities**: Different passes operate at different levels
4. **Target Independence**: Levels 0-4 are hardware-agnostic
5. **Clean-Room Safety**: Clear boundaries prevent accidental copying

### Why Not Fewer Levels?

- **Monolithic IR**: Would mix concerns (syntax, semantics, hardware)
- **Loss of Verification Points**: Harder to prove correctness
- **Optimization Conflicts**: Passes would interfere with each other

### Why Not More Levels?

- **Complexity**: More levels increase transformation overhead
- **Diminishing Returns**: 9 levels cover all necessary abstractions
- **Implementation Burden**: Each level requires builders, verifiers, tests

## Consequences

### Positive

1. **Clear Transformation Path**: Each lowering step is well-defined
2. **Verification Friendly**: Properties can be checked at each level
3. **Optimization Flexibility**: Passes can target specific levels
4. **Hardware Portability**: Levels 0-4 are target-independent
5. **Clean-Room Compliance**: Independent design from Qiskit

### Negative

1. **Implementation Complexity**: 9 levels require significant code
2. **Transformation Overhead**: Multiple passes increase compile time
3. **Memory Usage**: Intermediate representations consume memory
4. **Testing Burden**: Each level needs comprehensive tests

### Mitigation

- **Lazy Lowering**: Only lower to required level for given operation
- **IR Caching**: Reuse intermediate results when possible
- **Incremental Compilation**: Transform only changed portions
- **Parallel Passes**: Run independent transformations concurrently

## Alternatives Considered

### Alternative 1: MLIR-Based IR
**Rejected**: MLIR is excellent but would require:
- Learning MLIR dialect design
- Potential coupling to LLVM ecosystem
- Less control over verification strategy
- Harder to integrate with Liquid Haskell/Lean 4

### Alternative 2: Single-Level IR
**Rejected**: Would mix all concerns in one representation:
- Harder to verify correctness
- Optimization passes would conflict
- No clear separation of hardware-independent vs hardware-specific

### Alternative 3: Copy Qiskit's IR Design
**Rejected**: Violates clean-room methodology:
- Would copy proprietary design decisions
- Legal risk
- Not independently derived

## Implementation Plan

1. **Phase 1** (COMPLETE): Implement IR Levels 0-4
   - ✅ Source AST (parser output)
   - ✅ Typed AST (semantic analysis)
   - ✅ CFG (control flow graph)
   - ✅ SSA (static single assignment)
   - ✅ GATE (hardware-independent gates)

2. **Phase 2** (PENDING): Implement IR Levels 5-6
   - ⏳ TOPO (placement and routing)
   - ⏳ SCHEDULE (timing and resource allocation)

3. **Phase 3** (PENDING): Implement IR Levels 7-8
   - ⏳ PULSE (pulse-level representation)
   - ⏳ EXEC (execution package)

## Verification Strategy

Each IR level must have:
1. **Builder**: Constructs IR from previous level
2. **Verifier**: Checks IR invariants
3. **Printer**: Human-readable output
4. **Tests**: Unit tests for transformations
5. **Properties**: Formal properties (Liquid Haskell/Lean 4)

## Related Decisions

- **ADR-000**: Architecture Foundation
- **ADR-002**: Type System Design (pending)
- **ADR-003**: Optimization Pass Architecture (pending)
- **ADR-004**: Hardware Abstraction Layer (pending)

---

**Decision**: ACCEPTED  
**Architect**: Bob (ROLE-SYSTEM-ARCHITECT)  
**Date**: 2026-07-21

// Made with Bob