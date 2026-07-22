# ADR-002: Type System Design

**Status**: ACCEPTED  
**Date**: 2026-07-21  
**Deciders**: Bob (ROLE-SYSTEM-ARCHITECT)  
**Related**: ADR-000, ADR-001

---

## Context

QATAAUM must support multiple quantum languages with different type systems:
- **OpenQASM 2**: Simple types (qreg, creg)
- **OpenQASM 3**: Rich type system (int, uint, float, angle, duration, complex, arrays)
- **MetaQASM-4**: Extended types with refinements and effects

The type system must:
1. Enforce quantum no-cloning theorem
2. Track qubit linearity (use-once semantics)
3. Support classical computation
4. Enable formal verification
5. Remain clean-room (not copy Qiskit types)

## Decision

We adopt a **stratified type system** with three layers:

### Layer 1: Base Types
```rust
enum BaseType {
    // Quantum types
    Qubit,              // Single qubit
    QubitArray(usize),  // Fixed-size qubit array
    
    // Classical types
    Bit,                // Single classical bit
    BitArray(usize),    // Fixed-size bit array
    Int(Option<usize>), // Signed integer (optional bit width)
    UInt(Option<usize>),// Unsigned integer (optional bit width)
    Float(Option<usize>),// Floating point (optional precision)
    Bool,               // Boolean
    
    // Quantum-specific types
    Angle(Option<usize>),   // Rotation angle (optional precision)
    Duration(Option<usize>),// Time duration (optional precision)
    Complex(Box<BaseType>), // Complex number
    
    // Aggregate types
    Array(Box<BaseType>, usize), // Fixed-size array
}
```

### Layer 2: Effect Types
```rust
enum Effect {
    Pure,           // No side effects
    Measure,        // Measurement effect
    Reset,          // Reset effect
    Pulse,          // Pulse-level effect
    IO,             // I/O effect
    Composite(Vec<Effect>), // Multiple effects
}

struct EffectType {
    base: BaseType,
    effect: Effect,
}
```

### Layer 3: Refinement Types (MetaQASM-4)
```rust
struct RefinementType {
    base: EffectType,
    predicate: Refinement,
}

enum Refinement {
    Range(i64, i64),        // Value in range
    NonZero,                // Non-zero value
    Positive,               // Positive value
    Normalized,             // Normalized quantum state
    Unitary,                // Unitary matrix
    Custom(String),         // Custom predicate
}
```

## Rationale

### Why Stratified Design?

1. **Incremental Complexity**: Start simple (OpenQASM 2), add features (OpenQASM 3), extend (MetaQASM-4)
2. **Verification Friendly**: Each layer has clear semantics
3. **Language Support**: Map each language to appropriate layer
4. **Clean-Room**: Independent design, not copied from Qiskit

### Qubit Linearity

Qubits must be **linear types** (use-once):
- Cannot be copied (no-cloning theorem)
- Cannot be discarded (must measure or reset)
- Can be moved (ownership transfer)

**Implementation**:
```rust
struct LinearQubit {
    id: QubitId,
    state: QubitState,
}

enum QubitState {
    Live,      // Can be used
    Measured,  // Has been measured
    Moved,     // Ownership transferred
}
```

### Effect Tracking

Effects must be tracked to ensure:
- Measurements are not ignored
- Side effects are sequenced correctly
- Pure functions remain pure

**Example**:
```qasm
// Measure has effect
bit result = measure q[0];  // Effect: Measure

// Cannot ignore measurement
measure q[0];  // ERROR: unused measurement result
```

## Consequences

### Positive

1. **Type Safety**: Catch errors at compile time
2. **No-Cloning Enforcement**: Quantum semantics preserved
3. **Effect Tracking**: Side effects explicit
4. **Verification Ready**: Types support formal proofs
5. **Language Flexibility**: Supports OpenQASM 2, 3, and MetaQASM-4

### Negative

1. **Implementation Complexity**: Three-layer system is complex
2. **Type Inference**: May require sophisticated inference
3. **Error Messages**: Type errors can be verbose
4. **Learning Curve**: Users must understand effects and linearity

### Mitigation

- **Gradual Typing**: Start with simple types, add complexity as needed
- **Clear Error Messages**: Explain type errors in user-friendly terms
- **Type Inference**: Infer types where possible to reduce annotations
- **Documentation**: Comprehensive type system guide

## Type Checking Rules

### Rule 1: Qubit Linearity
```
Γ ⊢ q : Qubit    q used exactly once in expression
─────────────────────────────────────────────────
Γ ⊢ expr : T
```

### Rule 2: Effect Sequencing
```
Γ ⊢ e1 : T1 ! ε1    Γ ⊢ e2 : T2 ! ε2
────────────────────────────────────
Γ ⊢ e1; e2 : T2 ! (ε1 ∪ ε2)
```

### Rule 3: Measurement Effect
```
Γ ⊢ q : Qubit
─────────────────────────────
Γ ⊢ measure q : Bit ! Measure
```

## Alternatives Considered

### Alternative 1: Simple Types Only
**Rejected**: Cannot express OpenQASM 3 or MetaQASM-4 features

### Alternative 2: Dependent Types
**Rejected**: Too complex for initial implementation, can add later

### Alternative 3: Copy Qiskit Type System
**Rejected**: Violates clean-room methodology

## Implementation Plan

1. **Phase 1** (COMPLETE): Basic types for OpenQASM 2
   - ✅ Qubit and Bit types
   - ✅ Register types (arrays)
   - ✅ Simple type checking

2. **Phase 2** (PENDING): OpenQASM 3 types
   - ⏳ Int, UInt, Float types
   - ⏳ Angle and Duration types
   - ⏳ Complex numbers
   - ⏳ Multi-dimensional arrays

3. **Phase 3** (PENDING): Effect types
   - ⏳ Effect tracking
   - ⏳ Measurement effects
   - ⏳ Pulse effects

4. **Phase 4** (PENDING): Refinement types (MetaQASM-4)
   - ⏳ Refinement predicates
   - ⏳ Liquid Haskell integration
   - ⏳ Proof obligations

## Related Decisions

- **ADR-000**: Architecture Foundation
- **ADR-001**: IR Family Design
- **ADR-005**: Formal Verification Strategy (pending)

---

**Decision**: ACCEPTED  
**Architect**: Bob (ROLE-SYSTEM-ARCHITECT)  
**Date**: 2026-07-21

// Made with Bob