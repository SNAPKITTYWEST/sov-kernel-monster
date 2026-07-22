# QATAAUM Liquid Haskell Refinement Layer

This directory contains the Liquid Haskell refinement type specifications for the QATAAUM quantum compiler. These refinements provide machine-checkable invariants and proof witnesses that can be consumed by the Rust runtime and independently verified in Lean 4.

## Overview

The refinement layer enforces critical correctness properties:

- **Qubit Linearity**: Qubits cannot be cloned (no-cloning theorem)
- **Resource Ownership**: Proper tracking of qubit allocation and release
- **Circuit Structure**: Gate arity and qubit set constraints
- **Scheduling Correctness**: No resource conflicts, valid timing
- **Pulse Validity**: Frame consistency, waveform constraints
- **Pass Preservation**: Compiler optimizations preserve semantics

## Modules

### Core Refinements

- **`QATAAUM.Refinements.Qubit`** (200 lines)
  - Linear qubit ownership types
  - No-cloning witnesses
  - State transition validation

- **`QATAAUM.Refinements.Circuit`** (230 lines)
  - Circuit structure refinements
  - Gate arity constraints
  - Semantic preservation witnesses

- **`QATAAUM.Refinements.Schedule`** (210 lines)
  - Timing constraint refinements
  - Resource conflict detection
  - Dependency ordering validation

- **`QATAAUM.Refinements.Pulse`** (210 lines)
  - Pulse-level refinements
  - Frame consistency checks
  - Waveform validity constraints

- **`QATAAUM.Refinements.Passes`** (200 lines)
  - Compiler pass correctness
  - Optimization preservation
  - Metric improvement tracking

- **`QATAAUM.Refinements.Witness`** (230 lines)
  - Unified witness aggregation
  - Proof export interface
  - Witness validation

## Total Implementation

- **6 modules**
- **1,280 substantive lines of Liquid Haskell**
- **50 lines of Cabal configuration**
- **Total: 1,330 lines**

## Key Refinement Types

### Qubit Linearity
```haskell
{-@ type QubitId = {v:Int | v >= 0} @-}

{-@ allocQubit :: qid:QubitId -> qs:QubitSet 
               -> {v:(Qubit, QubitSet) | isOwned (fst v) && Set.member qid (snd v)} @-}
```

### Gate Arity
```haskell
{-@ gateArity :: GateType -> {v:Int | v > 0 && v <= 3} @-}

{-@ validGateArity :: g:Gate -> {v:Bool | v <=> (len (gateQubits g) == gateArity (gateType g))} @-}
```

### Timing Constraints
```haskell
{-@ type Time = {v:Double | v >= 0.0} @-}
{-@ type Duration = {v:Double | v > 0.0} @-}

{-@ noOverlap :: op1:ScheduledOp -> op2:ScheduledOp -> Bool @-}
```

### Pass Preservation
```haskell
{-@ preservesSemantics :: pr:PassResult -> Bool @-}
{-@ preservesQubits :: pr:PassResult -> Bool @-}
{-@ preservesDepth :: pr:PassResult -> Bool @-}
```

## Witness Generation

Witnesses are generated during compilation and can be:

1. **Validated** by Liquid Haskell's SMT solver
2. **Exported** to JSON for Rust runtime consumption
3. **Translated** to Lean 4 for independent verification

Example witness bundle:
```haskell
WitnessBundle {
  id = "compile-20260722-001",
  timestamp = "2026-07-22T07:27:00Z",
  valid = True,
  witnesses = [
    LinearityWitness{qid=0, alloc=True, used=True, released=True},
    CircuitWitness{arity=True, qubits=True, noclone=True},
    ScheduleWitness{noconf=True, timing=True, deps=True}
  ]
}
```

## Building

```bash
cabal build
```

## Running Liquid Haskell Verification

```bash
liquid src/QATAAUM/Refinements/Qubit.hs
liquid src/QATAAUM/Refinements/Circuit.hs
liquid src/QATAAUM/Refinements/Schedule.hs
liquid src/QATAAUM/Refinements/Pulse.hs
liquid src/QATAAUM/Refinements/Passes.hs
liquid src/QATAAUM/Refinements/Witness.hs
```

## Integration with Rust Runtime

The Rust compiler can import witness data:

```rust
use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
struct WitnessBundle {
    id: String,
    timestamp: String,
    valid: bool,
    witnesses: Vec<UnifiedWitness>,
}
```

## Integration with Lean 4

Witnesses can be translated to Lean 4 theorems:

```lean
theorem qubit_linearity (q : QubitId) (alloc used released : Bool) :
  alloc ∧ used ∧ released → LinearityValid q := by
  intro h
  -- Proof from witness
```

## Clean-Room Compliance

All refinements are based on:

- **Linear type theory** (Wadler 1990)
- **Quantum no-cloning theorem** (Wootters & Zurek 1982)
- **Affine type systems** (Altenkirch & Grattage 2005)
- **Compiler correctness** (Leroy 2009, CompCert)
- **Standard scheduling theory** (Graham 1966, Kelley & Walker 1959)

No proprietary IBM code or internal specifications are used.

## License

Apache-2.0

## Authors

QATAAUM Project Contributors