# QATAAUM OpenQASM Compatibility Matrix

**Project:** QATAAUM AS400-PULSE-MONAD  
**Version:** 1.0  
**Last Updated:** 2026-07-21  
**Status:** Research Phase

---

## Purpose

This document defines QATAAUM's compatibility with OpenQASM standards and specifies the original MetaQASM-4 language extensions. All OpenQASM information is derived from public specifications documented in RESEARCH_LEDGER.md.

## Governing Principle

**PUBLIC SPECIFICATION IN. INDEPENDENT IMPLEMENTATION OUT. EVIDENCE OR SILENCE.**

---

## OpenQASM Standards Overview

### OpenQASM 2.0

**Status:** Public Standard (Stable)  
**Specification:** https://github.com/Qiskit/openqasm/tree/OpenQASM2.x  
**License:** Apache 2.0  
**QATAAUM Support:** PLANNED (Full parser and compiler)

**Key Features:**
- Quantum register declarations (`qreg`)
- Classical register declarations (`creg`)
- Gate definitions (`gate`)
- Quantum operations (U, CX, and derived gates)
- Measurements (`measure`)
- Conditional operations (`if`)
- Barriers (`barrier`)
- Reset (`reset`)

**Example:**
```qasm
OPENQASM 2.0;
include "qelib1.inc";

qreg q[2];
creg c[2];

h q[0];
cx q[0], q[1];
measure q -> c;
```

---

### OpenQASM 3.0 / 3.1

**Status:** Public Standard (Current: 3.1)  
**Specification:** https://openqasm.com/  
**License:** Apache 2.0  
**QATAAUM Support:** PLANNED (Full parser and compiler)

**Major Additions over 2.0:**
- Classical types (int, uint, float, bool, bit, angle, duration)
- Control flow (if/else, for, while, switch)
- Subroutines and functions
- Timing and scheduling (delay, duration types)
- Pulse grammar (OpenPulse)
- Extern declarations
- Arrays and complex types
- Aliasing
- Quantum phase estimation
- Improved gate modifiers

**Example:**
```qasm
OPENQASM 3.0;

// Classical types
int[32] shots = 1024;
duration gate_time = 100ns;

// Subroutine
def bell_pair(qubit q0, qubit q1) {
    h q0;
    cx q0, q1;
}

// Quantum program
qubit[2] q;
bit[2] c;

bell_pair(q[0], q[1]);
c = measure q;
```

---

## QATAAUM Language Support Matrix

### OpenQASM 2.0 Support

| Feature | Status | Priority | Notes |
|---------|--------|----------|-------|
| **Core Syntax** | | | |
| OPENQASM version declaration | PLANNED | HIGH | Required for compatibility |
| Include statements | PLANNED | HIGH | Standard library support |
| Comments | PLANNED | HIGH | Single-line and multi-line |
| **Declarations** | | | |
| qreg (quantum registers) | PLANNED | HIGH | Core quantum state |
| creg (classical registers) | PLANNED | HIGH | Measurement results |
| **Gates** | | | |
| U gate (universal single-qubit) | PLANNED | HIGH | Fundamental gate |
| CX gate (CNOT) | PLANNED | HIGH | Fundamental two-qubit gate |
| Standard gate library (qelib1.inc) | PLANNED | HIGH | H, X, Y, Z, S, T, etc. |
| Custom gate definitions | PLANNED | MEDIUM | User-defined gates |
| Gate modifiers (inv, pow) | PLANNED | MEDIUM | OpenQASM 2.0 extensions |
| **Operations** | | | |
| measure | PLANNED | HIGH | Quantum measurement |
| reset | PLANNED | HIGH | Qubit reset |
| barrier | PLANNED | HIGH | Optimization barrier |
| **Control Flow** | | | |
| if (classical condition) | PLANNED | MEDIUM | Conditional execution |
| **Compatibility** | | | |
| Full OpenQASM 2.0 compliance | PLANNED | HIGH | Standard compatibility |

---

### OpenQASM 3.x Support

| Feature | Status | Priority | Notes |
|---------|--------|----------|-------|
| **Core Syntax** | | | |
| OPENQASM 3.x version declaration | PLANNED | HIGH | Version compatibility |
| Include statements | PLANNED | HIGH | Module system |
| Comments | PLANNED | HIGH | Enhanced comment syntax |
| **Classical Types** | | | |
| bit, int, uint | PLANNED | HIGH | Basic types |
| float, angle, duration | PLANNED | HIGH | Quantum-specific types |
| bool | PLANNED | MEDIUM | Boolean type |
| complex | PLANNED | LOW | Complex numbers |
| Arrays | PLANNED | HIGH | Array types |
| **Quantum Types** | | | |
| qubit declarations | PLANNED | HIGH | Modern qubit syntax |
| qubit arrays | PLANNED | HIGH | Qubit indexing |
| **Control Flow** | | | |
| if/else | PLANNED | HIGH | Conditional branching |
| for loops | PLANNED | HIGH | Iteration |
| while loops | PLANNED | MEDIUM | Conditional iteration |
| switch/case | PLANNED | LOW | Pattern matching |
| break/continue | PLANNED | MEDIUM | Loop control |
| **Subroutines** | | | |
| def (subroutine definition) | PLANNED | HIGH | Function definitions |
| return statements | PLANNED | HIGH | Return values |
| Parameters and arguments | PLANNED | HIGH | Function parameters |
| **Timing** | | | |
| delay statements | PLANNED | HIGH | Explicit delays |
| duration literals | PLANNED | HIGH | Time specifications |
| box (timing blocks) | PLANNED | MEDIUM | Timing constraints |
| **Pulse Grammar (OpenPulse)** | | | |
| frame declarations | PLANNED | MEDIUM | Pulse frames |
| waveform declarations | PLANNED | MEDIUM | Pulse waveforms |
| play statements | PLANNED | MEDIUM | Pulse execution |
| capture statements | PLANNED | MEDIUM | Measurement pulses |
| set_frequency | PLANNED | LOW | Frequency control |
| shift_phase | PLANNED | LOW | Phase control |
| **Advanced Features** | | | |
| extern declarations | PLANNED | LOW | External functions |
| cal/defcal blocks | PLANNED | LOW | Calibration definitions |
| Aliasing | PLANNED | MEDIUM | Qubit aliasing |
| Gate modifiers (ctrl, negctrl, inv, pow) | PLANNED | HIGH | Enhanced modifiers |
| **Compatibility** | | | |
| Full OpenQASM 3.1 compliance | PLANNED | HIGH | Standard compatibility |

---

## MetaQASM-4: Original Experimental Language

**Status:** ORIGINAL CONTRIBUTION (NOT OpenQASM 4)  
**Important:** MetaQASM-4 is an experimental language designed by this project. It is **NOT** OpenQASM 4, which does not exist as a public standard.

### Design Goals

1. **Typed Effects:** Monadic semantics for quantum operations
2. **Linear Ownership:** Prevent qubit cloning at type level
3. **Refinement Types:** Compile-time constraint verification
4. **Capability Indexing:** Backend-specific type checking
5. **Proof Obligations:** Formal verification integration
6. **Deterministic Provenance:** Execution receipt generation

### Type System Extensions

#### Effect Monads

| Monad | Purpose | Example |
|-------|---------|---------|
| **CircuitM** | Pure circuit construction | `circuit<CircuitM> bell_pair(...)` |
| **MeasureM** | Measurement effects | `measurement<MeasureM> measure_all(...)` |
| **DynamicM** | Dynamic circuits with feedback | `dynamic<DynamicM> adaptive_circuit(...)` |
| **PulseM** | Pulse-level operations | `pulse<PulseM> custom_gate(...)` |
| **BackendM** | Backend-specific execution | `backend<BackendM> submit_job(...)` |
| **ProofM** | Proof obligation generation | `proof<ProofM> verify_circuit(...)` |
| **ReceiptM** | Execution receipt sealing | `receipt<ReceiptM> seal_result(...)` |

#### Linear Qubit Types

```metaqasm4
// Linear ownership prevents cloning
circuit<CircuitM> no_cloning(q: Qubit) -> Qubit {
  // q is consumed and q' is produced
  q' <- h(q);
  return q';
  // Cannot use q again - compile error
}

// Explicit qubit pairs
circuit<CircuitM> entangle(q0: Qubit, q1: Qubit) -> (Qubit, Qubit) {
  q0' <- h(q0);
  (q0'', q1') <- cx(q0', q1);
  return (q0'', q1');
}
```

#### Refinement Constraints

```metaqasm4
// Refinement types for compile-time checking
type ValidAngle = {θ: Angle | 0 <= θ < 2π}
type LiveQubit = {q: Qubit | isLive(q)}
type MeasuredBit = {b: Bit | isMeasured(b)}

circuit<CircuitM> rotate(θ: ValidAngle, q: LiveQubit) -> LiveQubit {
  q' <- rz(θ, q);
  return q';
}
```

#### Capability-Indexed Types

```metaqasm4
// Backend capabilities as type constraints
backend<BackendM[DynamicCircuits, MidCircuitMeasurement]> 
adaptive_vqe(
  hamiltonian: Observable,
  initial_state: Qubit[n]
) -> (Qubit[n], Float) {
  // Only compiles for backends with required capabilities
  ...
}
```

### MetaQASM-4 Feature Matrix

| Feature | Status | Description |
|---------|--------|-------------|
| **Type System** | | |
| Effect monads | PLANNED | Monadic semantics for operations |
| Linear qubit types | PLANNED | Prevent cloning at type level |
| Refinement types | PLANNED | Compile-time constraints |
| Capability indexing | PLANNED | Backend-specific types |
| Dependent types (limited) | PLANNED | Type-level computation |
| **Syntax** | | |
| OpenQASM 3 base syntax | PLANNED | Compatible foundation |
| Type annotations | PLANNED | Explicit type declarations |
| Effect annotations | PLANNED | Monadic effect tracking |
| Proof annotations | PLANNED | Verification hints |
| **Semantics** | | |
| Monadic composition | PLANNED | Effect sequencing |
| Linear ownership | PLANNED | Resource tracking |
| Effect tracking | PLANNED | Side-effect analysis |
| Capability checking | PLANNED | Backend validation |
| **Verification** | | |
| Proof obligations | PLANNED | Formal verification hooks |
| Witness generation | PLANNED | Liquid Haskell integration |
| Receipt generation | PLANNED | Execution provenance |
| **Interoperability** | | |
| OpenQASM 3 import | PLANNED | Read OpenQASM 3 programs |
| OpenQASM 3 export | PLANNED | Generate OpenQASM 3 output |
| Gradual typing | PLANNED | Mix typed and untyped code |

### MetaQASM-4 Example

```metaqasm4
// MetaQASM-4 with full type annotations
METAQASM 4.0;

// Import OpenQASM 3 standard library
import openqasm3.stdgates;

// Type-safe circuit definition
circuit<CircuitM> bell_pair(
  q0: Qubit,
  q1: Qubit
) -> (Qubit, Qubit)
  requires isLive(q0) && isLive(q1)
  ensures isEntangled(result.0, result.1)
{
  q0' <- h(q0);
  (q0'', q1') <- cx(q0', q1);
  return (q0'', q1');
}

// Measurement with effect tracking
measurement<MeasureM> measure_bell(
  q0: Qubit,
  q1: Qubit
) -> (Bit, Bit)
  requires isLive(q0) && isLive(q1)
  ensures isMeasured(result.0) && isMeasured(result.1)
{
  b0 <- measure(q0);
  b1 <- measure(q1);
  return (b0, b1);
}

// Dynamic circuit with capability requirements
dynamic<DynamicM> adaptive_measurement(
  q: Qubit[n]
) -> Bit[n]
  requires backend.supports(DynamicCircuits)
  requires backend.supports(MidCircuitMeasurement)
{
  bit[n] results;
  for i in 0..n-1 {
    results[i] <- measure(q[i]);
    if results[i] == 1 {
      q[i+1] <- x(q[i+1]);  // Conditional gate
    }
  }
  return results;
}

// Main program with proof obligations
proof<ProofM> main() -> Receipt {
  qubit[2] q;
  
  // Circuit construction
  (q[0], q[1]) <- bell_pair(q[0], q[1]);
  
  // Measurement
  (bit b0, bit b1) <- measure_bell(q[0], q[1]);
  
  // Generate execution receipt
  receipt <- seal_execution(
    circuit_hash: hash(bell_pair),
    results: (b0, b1),
    backend: current_backend(),
    timestamp: now()
  );
  
  return receipt;
}
```

---

## Compatibility Strategy

### OpenQASM 2.0 → QATAAUM

1. **Parse** OpenQASM 2.0 syntax
2. **Translate** to QATAAUM-IR (Level 0: Source AST)
3. **Type** with default effect annotations
4. **Compile** through standard pipeline

### OpenQASM 3.x → QATAAUM

1. **Parse** OpenQASM 3.x syntax
2. **Translate** to QATAAUM-IR (Level 0: Source AST)
3. **Infer** types and effects where possible
4. **Compile** through standard pipeline

### MetaQASM-4 → QATAAUM

1. **Parse** MetaQASM-4 syntax
2. **Type-check** with full effect system
3. **Generate** proof obligations
4. **Verify** refinement constraints
5. **Compile** through standard pipeline

### QATAAUM → OpenQASM 3.x

1. **Lower** from QATAAUM-IR
2. **Erase** type annotations
3. **Erase** effect annotations
4. **Generate** OpenQASM 3.x output

---

## Implementation Phases

### Phase 1: OpenQASM 2.0 Support
- Lexer and parser
- AST construction
- Basic gate set
- Measurement and reset
- Simple conditionals

### Phase 2: OpenQASM 3.x Core
- Extended type system
- Control flow
- Subroutines
- Timing primitives

### Phase 3: OpenQASM 3.x Advanced
- Pulse grammar
- Calibration blocks
- Advanced gate modifiers
- Full standard compliance

### Phase 4: MetaQASM-4 Foundation
- Effect monad syntax
- Linear type checking
- Basic refinement types

### Phase 5: MetaQASM-4 Advanced
- Full refinement system
- Capability indexing
- Proof obligation generation
- Verification integration

---

## Testing Strategy

### Compliance Testing

**OpenQASM 2.0:**
- Parse all examples from specification
- Roundtrip testing (parse → print → parse)
- Semantic equivalence testing

**OpenQASM 3.x:**
- Parse all examples from specification
- Type checking validation
- Control flow correctness
- Timing constraint validation

**MetaQASM-4:**
- Type system soundness
- Linear ownership enforcement
- Effect tracking correctness
- Refinement constraint validation

### Interoperability Testing

- OpenQASM 2.0 → QATAAUM → OpenQASM 3.x
- OpenQASM 3.x → QATAAUM → OpenQASM 3.x
- MetaQASM-4 → QATAAUM → OpenQASM 3.x
- Mixed-mode programs

---

## Known Limitations

### OpenQASM 2.0
- Limited type system
- No subroutines
- No timing control
- No pulse-level access

### OpenQASM 3.x
- Complex type system requires careful implementation
- Pulse grammar is extensive
- Calibration blocks may require backend-specific handling
- Some features may not be fully specified

### MetaQASM-4
- **Experimental language** - not standardized
- Requires sophisticated type checker
- Proof obligation generation is complex
- May not be compatible with all backends
- Learning curve for users

---

## References

See RESEARCH_LEDGER.md for complete source provenance.

**Public Specifications:**
- OpenQASM 2.0: https://github.com/Qiskit/openqasm/tree/OpenQASM2.x
- OpenQASM 3.x: https://openqasm.com/
- OpenPulse: https://openqasm.com/language/pulses.html

**Related Documents:**
- PUBLIC_ARCHITECTURE_REPORT.md
- ADRs/ADR-000-architecture-foundation.md
- spec/metaqasm4/ (to be created)

---

**Document Status:** INITIAL DRAFT  
**Next Update:** After Phase R1 completion and specification phase  
**Maintained By:** ROLE-SYSTEM-ARCHITECT

**End of OpenQASM Compatibility Matrix**