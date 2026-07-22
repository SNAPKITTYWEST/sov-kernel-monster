# ADR-005: Formal Verification Strategy

**Status**: ACCEPTED  
**Date**: 2026-07-21  
**Deciders**: Bob (ROLE-SYSTEM-ARCHITECT), ROLE-HASKELL-VERIFIER, ROLE-LEAN-AUDITOR  
**Related**: ADR-000, ADR-001, ADR-002

---

## Context

QATAAUM requires formal verification to ensure:
1. Compiler correctness (transformations preserve semantics)
2. Type safety (no runtime type errors)
3. Qubit linearity (no-cloning theorem enforced)
4. Resource safety (no use-after-free, no double-measurement)
5. Deterministic execution (reproducible results)

The verification strategy must:
- Use machine-checkable proofs
- Integrate with Rust implementation
- Support incremental verification
- Remain clean-room (independent proofs)

## Decision

We adopt a **Three-Layer Verification Strategy**:

### Layer 1: Liquid Haskell Refinement Types
**Purpose**: Express and verify refinement properties

**Responsibilities**:
- Define typed monadic semantics of MetaQASM-4
- Express resource ownership and linearity
- Generate machine-checkable witnesses
- Verify lowering pass invariants

**Example Refinements**:
```haskell
{-@ type LiveQubit = {q:Qubit | isLive q} @-}
{-@ type UsedQubit = {q:Qubit | not (isLive q)} @-}

{-@ measure :: LiveQubit -> (Bit, UsedQubit) @-}
```

### Layer 2: Lean 4 Formal Proofs
**Purpose**: Prove compiler correctness theorems

**Responsibilities**:
- Formalize syntax and semantics
- Prove transformation preservation
- Audit Liquid Haskell witnesses
- Verify scheduling invariants

**Key Theorems**:
```lean
theorem parser_roundtrip : ∀ (src : String),
  parse (print (parse src)) = parse src

theorem gate_cancellation_preserves_semantics : ∀ (prog : Program),
  ⟦optimize prog⟧ = ⟦prog⟧

theorem routing_preserves_semantics : ∀ (prog : Program) (topo : Topology),
  ⟦route prog topo⟧ = ⟦prog⟧
```

### Layer 3: Property-Based Testing (Rust)
**Purpose**: Validate properties on concrete examples

**Responsibilities**:
- Generate random test cases
- Check properties hold
- Find counterexamples
- Complement formal proofs

**Example Properties**:
```rust
#[quickcheck]
fn prop_gate_cancellation_reduces_gates(prog: GateProgram) -> bool {
    let optimized = optimize(prog.clone());
    optimized.gate_count() <= prog.gate_count()
}
```

## Rationale

### Why Three Layers?

1. **Liquid Haskell**: Refinement types for resource safety
2. **Lean 4**: Full formal proofs for correctness
3. **Property Testing**: Practical validation

Each layer complements the others:
- Liquid Haskell: Fast, automatic, limited expressiveness
- Lean 4: Expressive, manual, complete proofs
- Property Testing: Concrete, fast feedback

### Why Not Just One?

- **Liquid Haskell alone**: Cannot prove all theorems
- **Lean 4 alone**: Too slow for all properties
- **Testing alone**: Cannot prove correctness

## Verification Targets

### High Priority (Must Verify)
1. ✅ Parser roundtrip (property tested)
2. ⏳ Type soundness (Liquid Haskell)
3. ⏳ Qubit linearity (Liquid Haskell)
4. ⏳ Gate cancellation preserves semantics (Lean 4)
5. ⏳ Rotation folding preserves semantics (Lean 4)
6. ⏳ Routing preserves semantics (Lean 4)

### Medium Priority (Should Verify)
7. ⏳ SSA construction correctness
8. ⏳ CFG well-formedness
9. ⏳ Scheduling validity
10. ⏳ Pulse timing correctness

### Low Priority (Nice to Have)
11. ⏳ Optimization termination
12. ⏳ Compilation determinism
13. ⏳ Receipt chain integrity

## Proof Policy

**Strict Rules**:
1. ❌ No `sorry` in accepted proofs
2. ❌ No `admit` in accepted proofs
3. ❌ No theorem-conclusion axioms
4. ✅ Every theorem must report effective axioms
5. ✅ Axioms must be justified

## Consequences

### Positive

1. **High Assurance**: Machine-checked correctness
2. **Bug Prevention**: Catch errors before runtime
3. **Documentation**: Proofs document invariants
4. **Confidence**: Users trust verified compiler

### Negative

1. **Development Time**: Proofs take time to write
2. **Expertise Required**: Need Liquid Haskell and Lean 4 skills
3. **Maintenance**: Proofs must be updated with code
4. **Tooling**: Requires proof assistant setup

### Mitigation

- **Incremental Verification**: Verify critical parts first
- **Training**: Document proof patterns
- **Automation**: Use tactics and automation where possible
- **Prioritization**: Focus on high-value proofs

## Implementation Plan

**Phase 1** (PENDING):
- ⏳ Set up Liquid Haskell environment
- ⏳ Define core refinement types
- ⏳ Verify qubit linearity

**Phase 2** (PENDING):
- ⏳ Set up Lean 4 environment
- ⏳ Formalize syntax and semantics
- ⏳ Prove parser roundtrip

**Phase 3** (PENDING):
- ⏳ Prove gate cancellation correctness
- ⏳ Prove rotation folding correctness
- ⏳ Prove routing correctness

## Alternatives Considered

### Alternative 1: No Formal Verification
**Rejected**: Cannot guarantee correctness

### Alternative 2: Only Testing
**Rejected**: Testing shows presence of bugs, not absence

### Alternative 3: Copy Qiskit Proofs
**Rejected**: Qiskit doesn't have formal proofs; violates clean-room

### Alternative 4: Use Coq Instead of Lean 4
**Rejected**: Lean 4 has better ergonomics and metaprogramming

## Related Decisions

- **ADR-000**: Architecture Foundation
- **ADR-001**: IR Family Design
- **ADR-002**: Type System Design

---

**Decision**: ACCEPTED  
**Architect**: Bob (ROLE-SYSTEM-ARCHITECT)  
**Date**: 2026-07-21

// Made with Bob