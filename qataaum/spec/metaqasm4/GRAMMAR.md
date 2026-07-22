# MetaQASM-4 Grammar Specification

**Status:** DRAFT - Original Experimental Language  
**Version:** 0.1.0  
**Date:** 2026-07-21

---

## ⚠️ Important Disclaimer

**MetaQASM-4 is NOT OpenQASM 4.**

OpenQASM 4 does not exist as a public standard. MetaQASM-4 is an **original experimental language** designed by the QATAAUM project as a research extension of OpenQASM 3.

---

## 1. Introduction

### 1.1 Purpose

MetaQASM-4 extends OpenQASM 3 with:
- **Typed Effects:** Monadic semantics for quantum operations
- **Linear Ownership:** Prevent qubit cloning at type level
- **Refinement Types:** Compile-time constraint verification
- **Capability Indexing:** Backend-specific type checking
- **Proof Obligations:** Formal verification integration

### 1.2 Design Goals

1. **Type Safety:** Catch errors at compile time
2. **Effect Tracking:** Make side effects explicit
3. **Resource Safety:** Prevent qubit cloning and use-after-free
4. **Backend Portability:** Abstract over hardware capabilities
5. **Formal Verification:** Enable proof-carrying code

### 1.3 Compatibility

- **Imports:** Can import OpenQASM 3 programs
- **Exports:** Can generate OpenQASM 3 output
- **Gradual Typing:** Mix typed and untyped code

---

## 2. Lexical Structure

### 2.1 Keywords

**OpenQASM 3 Keywords (inherited):**
```
METAQASM  include  def  gate  opaque  extern  box  let  const
qubit  bit  int  uint  float  angle  duration  bool  complex
if  else  for  while  switch  case  default  break  continue  return
measure  reset  barrier  delay  cal  defcal  defcalgrammar
```

**MetaQASM-4 New Keywords:**
```
circuit  measurement  dynamic  pulse  backend  proof  receipt
requires  ensures  where  forall  exists  refine  capability
linear  owned  borrowed  released  effect  monad  witness
```

### 2.2 Effect Monad Names

```
CircuitM  MeasureM  DynamicM  PulseM  BackendM  ProofM  ReceiptM
```

### 2.3 Type Annotations

```
:  ::  ->  =>  <-  |  &  @  #
```

---

## 3. Type System

### 3.1 Base Types

```metaqasm4
// Quantum types
Qubit                    // Single qubit
Qubit[n]                 // Qubit array
LiveQubit                // Refinement: qubit is live
MeasuredQubit            // Refinement: qubit has been measured

// Classical types (from OpenQASM 3)
bit, bit[n]
int, int[n]
uint, uint[n]
float, float[n]
angle
duration
bool
complex

// Refinement types
{x: Type | predicate(x)}
```

### 3.2 Effect Types

```metaqasm4
// Effect monad syntax
<EffectM> Type

// Examples
<CircuitM> (Qubit, Qubit)        // Pure circuit construction
<MeasureM> Bit                   // Measurement effect
<DynamicM> Qubit                 // Dynamic circuit effect
<PulseM> ()                      // Pulse effect
<BackendM> Result                // Backend execution effect
<ProofM> Witness                 // Proof obligation
<ReceiptM> Receipt               // Execution receipt
```

### 3.3 Linear Types

```metaqasm4
// Linear ownership
owned Qubit              // Owned qubit (must be consumed)
borrowed Qubit           // Borrowed qubit (must be returned)
released Qubit           // Released qubit (cannot be used)

// Linear function type
fn(owned Qubit) -> owned Qubit
```

### 3.4 Capability Types

```metaqasm4
// Backend capabilities as type constraints
backend<DynamicCircuits, MidCircuitMeasurement> {
    // Code requiring these capabilities
}

// Capability-indexed function
fn<C: Capability> process(backend: Backend<C>) -> Result
```

---

## 4. Effect Monads

### 4.1 CircuitM - Pure Circuit Construction

```metaqasm4
circuit<CircuitM> bell_pair(
    q0: owned Qubit,
    q1: owned Qubit
) -> (owned Qubit, owned Qubit)
{
    q0' <- h(q0);
    (q0'', q1') <- cx(q0', q1);
    return (q0'', q1');
}
```

**Properties:**
- No side effects
- Deterministic
- Can be optimized freely
- No measurement or reset

### 4.2 MeasureM - Measurement Effects

```metaqasm4
measurement<MeasureM> measure_all(
    q: owned Qubit[n]
) -> bit[n]
{
    bit[n] results;
    for i in 0..n-1 {
        results[i] <- measure(q[i]);
    }
    return results;
}
```

**Properties:**
- Non-deterministic
- Collapses quantum state
- Cannot be reversed
- Produces classical bits

### 4.3 DynamicM - Dynamic Circuits

```metaqasm4
dynamic<DynamicM> adaptive_circuit(
    q: owned Qubit[n]
) -> bit[n]
    requires backend.supports(DynamicCircuits)
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
```

**Properties:**
- Real-time classical feedback
- Mid-circuit measurement
- Conditional operations
- Requires hardware support

### 4.4 PulseM - Pulse-Level Operations

```metaqasm4
pulse<PulseM> custom_gate(
    q: owned Qubit,
    amplitude: float,
    frequency: float
) -> owned Qubit
    requires backend.supports(PulseAccess)
{
    frame f = q.frame;
    waveform w = gaussian(amplitude, 40ns);
    play(f, w);
    return q;
}
```

**Properties:**
- Low-level hardware control
- Timing-aware
- Frame and waveform management
- Requires pulse access

### 4.5 BackendM - Backend Execution

```metaqasm4
backend<BackendM> execute_circuit(
    circuit: Circuit,
    shots: int
) -> Result
{
    job <- submit(circuit, shots);
    result <- wait(job);
    return result;
}
```

**Properties:**
- Asynchronous execution
- Job management
- Result retrieval
- Backend-specific

### 4.6 ProofM - Proof Obligations

```metaqasm4
proof<ProofM> verify_entanglement(
    q0: owned Qubit,
    q1: owned Qubit
) -> (owned Qubit, owned Qubit)
    ensures isEntangled(result.0, result.1)
{
    (q0', q1') <- bell_pair(q0, q1);
    witness <- generate_entanglement_proof(q0', q1');
    attach_witness(witness);
    return (q0', q1');
}
```

**Properties:**
- Generates proof obligations
- Attaches witnesses
- Enables formal verification
- Checked by proof system

### 4.7 ReceiptM - Execution Receipts

```metaqasm4
receipt<ReceiptM> seal_execution(
    circuit: Circuit,
    result: Result
) -> Receipt
{
    receipt <- create_receipt(
        circuit_hash: hash(circuit),
        result_hash: hash(result),
        backend: current_backend(),
        timestamp: now()
    );
    seal <- sign(receipt);
    return seal;
}
```

**Properties:**
- Deterministic provenance
- Cryptographic sealing
- Immutable record
- Audit trail

---

## 5. Refinement Types

### 5.1 Syntax

```metaqasm4
type TypeName = {x: BaseType | predicate(x)}
```

### 5.2 Examples

```metaqasm4
// Valid angle range
type ValidAngle = {θ: angle | 0 <= θ < 2*pi}

// Live qubit
type LiveQubit = {q: Qubit | isLive(q)}

// Measured bit
type MeasuredBit = {b: bit | isMeasured(b)}

// Non-zero integer
type NonZero = {n: int | n != 0}

// Positive duration
type PositiveDuration = {d: duration | d > 0ns}
```

### 5.3 Refinement Predicates

```metaqasm4
// Built-in predicates
isLive(q: Qubit) -> bool
isMeasured(q: Qubit) -> bool
isEntangled(q0: Qubit, q1: Qubit) -> bool
isConnected(q0: Qubit, q1: Qubit, backend: Backend) -> bool

// User-defined predicates
predicate isNormalized(state: StateVector) {
    sum(|state[i]|^2 for i in 0..len(state)-1) == 1.0
}
```

---

## 6. Linear Ownership

### 6.1 Ownership Rules

1. **Qubits are linear:** Each qubit has exactly one owner
2. **Use-once:** Owned qubits must be consumed exactly once
3. **No cloning:** Cannot duplicate qubit references
4. **Explicit transfer:** Ownership transfer is explicit

### 6.2 Ownership Annotations

```metaqasm4
// Owned (default for qubits)
fn process(q: owned Qubit) -> owned Qubit

// Borrowed (temporary access)
fn inspect(q: borrowed Qubit) -> float

// Released (cannot be used)
fn discard(q: owned Qubit) -> released Qubit
```

### 6.3 Ownership Transfer

```metaqasm4
circuit<CircuitM> transfer_example() {
    qubit q;                    // q is owned
    q' <- h(q);                 // q consumed, q' is new owner
    // q cannot be used here
    q'' <- x(q');               // q' consumed, q'' is new owner
    measure(q'');               // q'' consumed
}
```

---

## 7. Capability System

### 7.1 Capability Declarations

```metaqasm4
capability DynamicCircuits {
    mid_circuit_measurement: bool,
    classical_feedback: bool,
    max_branches: int
}

capability PulseAccess {
    custom_waveforms: bool,
    frame_control: bool,
    timing_resolution: duration
}
```

### 7.2 Capability Requirements

```metaqasm4
fn<C: DynamicCircuits> adaptive_vqe(
    hamiltonian: Observable,
    backend: Backend<C>
) -> float
    requires C.mid_circuit_measurement
    requires C.classical_feedback
{
    // Implementation
}
```

### 7.3 Capability Checking

```metaqasm4
// Compile-time capability check
if backend.supports(DynamicCircuits) {
    result <- adaptive_circuit(qubits);
} else {
    error("Backend does not support dynamic circuits");
}
```

---

## 8. Proof Obligations

### 8.1 Preconditions and Postconditions

```metaqasm4
circuit<CircuitM> rotate(
    θ: ValidAngle,
    q: LiveQubit
) -> LiveQubit
    requires isLive(q)
    requires 0 <= θ < 2*pi
    ensures isLive(result)
{
    q' <- rz(θ, q);
    return q';
}
```

### 8.2 Invariants

```metaqasm4
circuit<CircuitM> loop_example(
    q: owned Qubit[n]
) -> owned Qubit[n]
    invariant forall i. isLive(q[i])
{
    for i in 0..n-1 {
        q[i] <- h(q[i]);
    }
    return q;
}
```

### 8.3 Witness Attachment

```metaqasm4
proof<ProofM> verified_circuit(
    q: owned Qubit
) -> owned Qubit
{
    q' <- some_operation(q);
    witness <- generate_correctness_proof(q');
    attach_witness(witness);
    return q';
}
```

---

## 9. Complete Example

```metaqasm4
METAQASM 4.0;

// Import OpenQASM 3 standard library
import openqasm3.stdgates;

// Type definitions
type ValidAngle = {θ: angle | 0 <= θ < 2*pi};
type LiveQubit = {q: Qubit | isLive(q)};

// Pure circuit construction
circuit<CircuitM> bell_pair(
    q0: owned LiveQubit,
    q1: owned LiveQubit
) -> (owned LiveQubit, owned LiveQubit)
    requires isLive(q0) && isLive(q1)
    ensures isEntangled(result.0, result.1)
{
    q0' <- h(q0);
    (q0'', q1') <- cx(q0', q1);
    return (q0'', q1');
}

// Measurement with effect tracking
measurement<MeasureM> measure_bell(
    q0: owned LiveQubit,
    q1: owned LiveQubit
) -> (bit, bit)
    requires isLive(q0) && isLive(q1)
{
    b0 <- measure(q0);
    b1 <- measure(q1);
    return (b0, b1);
}

// Dynamic circuit with capability requirements
dynamic<DynamicM> adaptive_measurement(
    q: owned Qubit[n]
) -> bit[n]
    requires backend.supports(DynamicCircuits)
    requires backend.supports(MidCircuitMeasurement)
{
    bit[n] results;
    for i in 0..n-1 {
        results[i] <- measure(q[i]);
        if results[i] == 1 {
            q[i+1] <- x(q[i+1]);
        }
    }
    return results;
}

// Main program with proof obligations
proof<ProofM> main() -> Receipt {
    // Allocate qubits
    qubit[2] q;
    
    // Create Bell pair
    (q[0], q[1]) <- bell_pair(q[0], q[1]);
    
    // Measure
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

## 10. Grammar (EBNF)

```ebnf
(* MetaQASM-4 Grammar *)

program = version_decl , { import_decl } , { statement } ;

version_decl = "METAQASM" , real_literal , ";" ;

import_decl = "import" , identifier , { "." , identifier } , ";" ;

statement = type_decl
          | circuit_decl
          | measurement_decl
          | dynamic_decl
          | pulse_decl
          | backend_decl
          | proof_decl
          | receipt_decl
          ;

type_decl = "type" , identifier , "=" , type_expr , ";" ;

circuit_decl = "circuit" , "<" , "CircuitM" , ">" , identifier ,
               "(" , param_list , ")" , [ "->" , type_expr ] ,
               [ requires_clause ] , [ ensures_clause ] ,
               block ;

measurement_decl = "measurement" , "<" , "MeasureM" , ">" , identifier ,
                   "(" , param_list , ")" , [ "->" , type_expr ] ,
                   [ requires_clause ] ,
                   block ;

(* Similar for other effect monads *)

type_expr = base_type
          | effect_type
          | refinement_type
          | linear_type
          | capability_type
          ;

effect_type = "<" , monad_name , ">" , type_expr ;

refinement_type = "{" , identifier , ":" , type_expr , "|" , predicate , "}" ;

linear_type = ownership_modifier , type_expr ;

ownership_modifier = "owned" | "borrowed" | "released" ;

requires_clause = "requires" , predicate , { "&&" , predicate } ;

ensures_clause = "ensures" , predicate , { "&&" , predicate } ;

predicate = expression ;

(* Rest of grammar similar to OpenQASM 3 with extensions *)
```

---

## 11. Semantics

### 11.1 Type Checking

1. **Effect checking:** Verify effect annotations match operations
2. **Linearity checking:** Ensure qubits used exactly once
3. **Refinement checking:** Verify predicates at compile time
4. **Capability checking:** Ensure backend supports required features

### 11.2 Proof Obligations

1. **Preconditions:** Must hold before function call
2. **Postconditions:** Must hold after function return
3. **Invariants:** Must hold throughout loop execution
4. **Refinements:** Must satisfy type predicates

### 11.3 Witness Generation

1. **Liquid Haskell:** Generates SMT-based witnesses
2. **Lean 4:** Checks witnesses for validity
3. **Runtime:** Optionally checks witnesses during execution

---

## 12. Implementation Status

- [ ] Lexer
- [ ] Parser
- [ ] Type checker
- [ ] Effect checker
- [ ] Linearity checker
- [ ] Refinement checker
- [ ] Capability checker
- [ ] Proof obligation generator
- [ ] Witness generator (Liquid Haskell)
- [ ] Witness checker (Lean 4)
- [ ] Code generator (to OpenQASM 3)

---

## 13. References

- OpenQASM 3 Specification: https://openqasm.com/
- Liquid Haskell: https://ucsd-progsys.github.io/liquidhaskell/
- Lean 4: https://lean-lang.org/
- Linear Types: Wadler, "Linear Types Can Change the World"
- Effect Systems: Lucassen & Gifford, "Polymorphic Effect Systems"

---

**Document Status:** DRAFT  
**Last Updated:** 2026-07-21  
**Maintained By:** ROLE-SYSTEM-ARCHITECT

**End of MetaQASM-4 Grammar Specification**