# ADR-003: Optimization Pass Architecture

**Status**: ACCEPTED  
**Date**: 2026-07-21  
**Deciders**: Bob (ROLE-SYSTEM-ARCHITECT)  
**Related**: ADR-000, ADR-001

---

## Context

Quantum circuits require optimization to:
1. Reduce gate count (minimize errors)
2. Reduce circuit depth (minimize decoherence)
3. Adapt to hardware constraints
4. Improve execution fidelity

The optimization system must:
- Support multiple independent passes
- Allow pass composition and ordering
- Preserve circuit semantics
- Enable verification of transformations
- Remain clean-room (not copy Qiskit passes)

## Decision

We adopt a **Pass Manager Architecture** with:

### 1. Pass Interface
```rust
trait OptimizationPass {
    fn name(&self) -> &str;
    fn run(&mut self, program: &mut GateProgram);
    fn preserves_semantics(&self) -> bool;
    fn requires(&self) -> Vec<PassId>;
    fn invalidates(&self) -> Vec<PassId>;
}
```

### 2. Pass Manager
```rust
struct PassManager {
    passes: Vec<Box<dyn OptimizationPass>>,
    max_iterations: usize,
    stats: OptimizationStats,
}
```

### 3. Core Optimization Passes

**Implemented**:
- ✅ **Gate Cancellation**: Remove inverse gate pairs (H-H, X-X, CX-CX)
- ✅ **Rotation Folding**: Combine consecutive rotations (Rz(θ1) + Rz(θ2) = Rz(θ1+θ2))

**Planned**:
- ⏳ **Commutation Analysis**: Reorder commuting gates
- ⏳ **Dead Code Elimination**: Remove unused operations
- ⏳ **Constant Propagation**: Evaluate constant expressions
- ⏳ **Peephole Optimization**: Local pattern matching
- ⏳ **Template Matching**: Replace gate sequences with equivalents

## Rationale

### Why Pass Manager?

1. **Modularity**: Each pass is independent
2. **Composability**: Combine passes in different orders
3. **Testability**: Test each pass in isolation
4. **Extensibility**: Easy to add new passes
5. **Verification**: Verify each pass separately

### Why Iterative Execution?

Some optimizations enable others:
```
H-X-H → Z  (commutation)
Z-Z → I    (cancellation)
```

Running passes iteratively finds more optimizations.

### Why Semantic Preservation?

**Critical**: Optimizations must not change circuit behavior
- Formal verification required
- Property-based testing
- Equivalence checking

## Consequences

### Positive

1. **Flexible Optimization**: Easy to add/remove/reorder passes
2. **Verifiable**: Each pass can be proven correct
3. **Measurable**: Track optimization metrics
4. **Maintainable**: Clear separation of concerns

### Negative

1. **Overhead**: Pass manager adds execution cost
2. **Complexity**: Managing pass dependencies
3. **Convergence**: Iterative passes may not converge

### Mitigation

- **Pass Ordering**: Optimize pass execution order
- **Dependency Tracking**: Automatically resolve dependencies
- **Iteration Limits**: Prevent infinite loops

## Implementation Status

**Phase 1** (COMPLETE):
- ✅ Pass Manager (24 tests passing)
- ✅ Gate Cancellation Pass
- ✅ Rotation Folding Pass
- ✅ Optimization Statistics

**Phase 2** (PENDING):
- ⏳ Commutation Analysis
- ⏳ Dead Code Elimination
- ⏳ Template Matching

## Alternatives Considered

### Alternative 1: Monolithic Optimizer
**Rejected**: Hard to test, verify, and extend

### Alternative 2: Copy Qiskit Passes
**Rejected**: Violates clean-room methodology

### Alternative 3: No Optimization
**Rejected**: Unoptimized circuits have poor fidelity

## Related Decisions

- **ADR-000**: Architecture Foundation
- **ADR-001**: IR Family Design
- **ADR-006**: Verification Strategy (pending)

---

**Decision**: ACCEPTED  
**Architect**: Bob (ROLE-SYSTEM-ARCHITECT)  
**Date**: 2026-07-21

// Made with Bob