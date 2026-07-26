# SCAFFOLDS IN PROGRESS - Phase 1 Quantum Compiler Hardening

This document marks quantum circuits that are **scaffolds**, not complete implementations. These are reference implementations used for Phase 1 correctness validation but are intentionally simplified for architecture verification.

**Status**: Phase 1 — Foundation & Correctness Focus
**Last Updated**: 2026-07-26

---

## Algorithm Status Matrix

| Algorithm | Implementation | What's Implemented | What's Stubbed | Status | Reference |
|-----------|---|---|---|---|---|
| **QFT (Quantum Fourier Transform)** | `circuit_qft()` in bob_circuit.f90:163-188 | Hadamard layer + simplified phase rotations | **Proper controlled-phase gates with 2π/2^k factors** | IN_PROGRESS_SCAFFOLD | Nielsen & Chuang Ch. 5 |
| **Inverse QFT** | NOT IMPLEMENTED | — | **Full inverse QFT with controlled phases** | TODO | Nielsen & Chuang §5.2 |
| **Grover Search** | `circuit_grover()` in bob_circuit.f90:205-237 | H initialization, Grover iterations, diffusion | **Programmable oracle (current: hardcoded CZ(q0, q_n))** | IN_PROGRESS_SCAFFOLD | Nielsen & Chuang §6.2 |
| **Quantum Phase Estimation** | `circuit_qpe()` in bob_circuit.f90:245-271 | Counting qubits, controlled unitary powers | **Proper inverse QFT (current: just H layer)** | IN_PROGRESS_SCAFFOLD | Nielsen & Chuang §5.2 |
| **Shor's Algorithm** | `circuit_shor()` in bob_circuit.f90:278-284 | Delegates to QPE for period finding | **Modular exponentiation, classical reduction phase, factorization** | IN_PROGRESS_SCAFFOLD | Nielsen & Chuang §6.3 |
| **Bell Pair** | `circuit_bell_pair()` in bob_circuit.f90:290-298 | Correct (\|Φ⁺⟩ state) | None — complete | COMPLETE | — |
| **Quantum Teleportation** | `circuit_teleportation()` in bob_circuit.f90:304-321 | Alice's measurement, Bob's corrections | **Proper classical control IR (see issue below)** | SEMANTIC_BUG | Nielsen & Chuang §1.3.7 |

---

## Detailed Scaffold Descriptions

### 1. Quantum Fourier Transform (QFT) — IN_PROGRESS_SCAFFOLD

**What's Implemented:**
- Lines 169-171: Hadamard on each qubit i
- Lines 172-177: Loop over controlled phase rotations with angle = π/2^(j-i)
- Lines 180-182: SWAP gates to reverse qubit order
- Lines 185-187: Measurement gates for readout

**Mathematical Issue:**
The current implementation approximates QFT but has a critical bug in the controlled phase gate construction. The phase angle should be 2π/2^(j-i), but the current code:
```fortran
angle = PI / real(ishft(1_i4, j - i), wp)  ! This computes π/2^(j-i), not 2π/2^(j-i)
call c%add_gate(GATE_CNOT, start + j, control=start + i, status=st)
call c%add_gate(GATE_ROTATION, start + i, angle=angle, status=st)
```

Problems:
1. **Missing controlled-phase semantics**: The code uses CNOT followed by a rotation. This is not the correct controlled-phase gate.
2. **Angle factor**: Missing factor of 2 in the denominator (should be 2π/2^(j-i))
3. **Non-composable**: The circuit ends with measurements, making it unsuitable for composition with other circuits.
4. **Measurement-early semantic**: A true QFT should be unitary and measurements should be optional for state preparation tasks.

**Why It's Still Useful (Phase 1):**
This structure is adequate for demonstrating the compiler pipeline and testing gate compilation. Phase 2 will implement the proper QFT with controlled-phase gates and verify the unitary property.

**Reference Implementation:**
- Nielsen & Chuang, Section 5.1: Quantum Fourier Transform
- Standard OpenQASM/Qiskit: `qft(qubits)` gate uses CPhase(2π/2^k) for each pair, then SWAPs

**Testing Requirement:**
- Compare circuit depth and gate counts to reference (Qiskit)
- Verify phase angles numerically match expected QFT matrix elements

---

### 2. Grover's Search Algorithm — IN_PROGRESS_SCAFFOLD

**What's Implemented:**
- Lines 211-213: Superposition initialization (H on all qubits)
- Lines 214-231: Grover iterations with:
  - Oracle: Hardcoded CZ(last qubit, controlled by q0)
  - Diffusion operator: H X CZ X H pattern on all qubits
- Lines 234-236: Measurement

**What's Stubbed:**
The **oracle is hardcoded** to a CZ gate between qubits 0 and (num_qubits-1). This marks the searched element as |00...01⟩ (all zeros, then a one), not configurable to arbitrary targets.

```fortran
! Line 218: Oracle hardcoded
if (num_qubits >= 2) then
  call c%add_gate(GATE_CZ, num_qubits - 1, control=0, status=st)
end if
```

**Why It's Still Useful:**
This scaffold demonstrates:
- How many iterations the algorithm requires: `grover_optimal_iterations()` computes ⌊π/4 · √(N/M)⌋ correctly
- How the diffusion operator amplifies amplitude toward marked states
- That Grover can run end-to-end in the compiler

**What's Missing for Full Grover:**
1. Programmable oracle interface (e.g., oracle_index parameter or callback)
2. Oracle generation for arbitrary Boolean functions
3. Marked element specification (currently hardcoded to last qubit)

**Reference Implementation:**
- Nielsen & Chuang, Section 6.2: Grover's Algorithm
- Standard: Oracle should mark target state |t⟩ with phase -1 (via unitary U_w), not just specific CZ

**Testing Requirement:**
- Verify iteration count matches expected amplitude amplification
- On 2-3 qubits with M=1 solution, verify output state has high amplitude at |01⟩

---

### 3. Quantum Phase Estimation (QPE) — IN_PROGRESS_SCAFFOLD

**What's Implemented:**
- Lines 253-255: Hadamard initialization on counting qubits
- Lines 257-261: Controlled unitary powers (controlled CNOTs simulating U^(2^i))
- Lines 264-265: **Simplified inverse QFT** (just Hadamard layer, NOT true QFT†)
- Lines 268-270: Measurement

**What's Stubbed:**
The inverse QFT (lines 264-265) is replaced with a single Hadamard layer:
```fortran
! Inverse QFT on counting qubits (simplified: just H layer)
do i = 0, num_counting - 1
  call c%add_gate(GATE_HADAMARD, i, status=st)
end do
```

This is **not** the inverse QFT. The true QFT† would have controlled phase gates and SWAPs. This simplification means the phase information is not properly extracted into the counting register.

**Mathematical Impact:**
- Correct QPE requires QFT† to convert phase interference into qubit measurement outcomes
- The simplified version will not accurately estimate eigenvalues
- For Phase 1 validation, this is acceptable; Phase 2 will use proper QFT†

**Why It's Still Useful:**
This scaffold demonstrates:
- How the controlled unitary powers are constructed
- How counting qubits are initialized and measured
- The overall circuit structure of phase estimation

**What's Missing for Full QPE:**
1. Inverse QFT with controlled-phase gates
2. Proper phase accumulation (currently lost)
3. Precision analysis (counting_qubits determines eigenvalue precision)

**Reference Implementation:**
- Nielsen & Chuang, Section 5.2: Quantum Phase Estimation
- Standard: Should use QFT† with CPhase gates, then measure

**Testing Requirement:**
- Apply to simple eigenstate (e.g., Z|0⟩, eigenvalue = 1)
- Verify counting register measures to expected phase (proportional to 2π eigenvalue)

---

### 4. Shor's Algorithm — IN_PROGRESS_SCAFFOLD

**What's Implemented:**
- Lines 278-283: Delegates entirely to `circuit_qpe()` for period finding
- Computes `counting = num_qubits / 2` as the precision

**What's Stubbed (Nearly Everything):**
- **Modular exponentiation circuit**: No reversible a^x mod N construction
- **Quantum order-finding**: Only period-finding via QPE; does not find order of a modulo N
- **Classical reduction**: No Euclidean algorithm for extracting factors from the period
- **Integer factorization**: No algorithm to convert period r into factors of N

Current code:
```fortran
function circuit_shor(num_qubits) result(c)
  integer(i4), intent(in) :: num_qubits
  type(bob_circuit_t) :: c
  integer(i4) :: counting
  counting = max(1, num_qubits / 2)
  c = circuit_qpe(counting, counting)
end function circuit_shor
```

This is essentially **just the phase estimation part**, not the factorization algorithm.

**Why It's Still Useful:**
This scaffold demonstrates:
- How a quantum subroutine (order-finding via QPE) integrates into the compiler
- Proper qubit allocation for period-finding precision
- That the circuit compiles and runs end-to-end

**What's Missing for Full Shor:**
1. **Reversible modular exponentiation**: Construct U|x⟩ = |a^x mod N⟩ circuit (polynomial gates)
2. **Classical reduction**: Post-quantum, use Euclidean algorithm on period r to find factors
3. **Eigenstate preparation**: Prepare equal superposition over x ∈ [0, N) on second register
4. **Full algorithm**: Repeat period-finding until gcd(r, N) yields non-trivial factor

**Reference Implementation:**
- Nielsen & Chuang, Section 6.3: Shor's Factoring Algorithm
- Beauregard, "Circuit for Shor's algorithm using 2n+3 qubits" (2002)
- Standard: Full circuit has ~6n qubits, ~O(n³) gates for n-bit factorization

**Testing Requirement:**
- Verify period-finding for known modular exponentiation (e.g., order of 2 mod 15)
- Classical post-processing to extract factors

---

## Issue: Quantum Teleportation Semantic Bug

**Location**: `circuit_teleportation()` in bob_circuit.f90:304-321

**Bug Description:**
Lines 318-319 use the measurement results as if they are still quantum qubits:
```fortran
call c%add_measure(0, 0, status=st)      ! Measure q0 → c0
call c%add_measure(1, 1, status=st)      ! Measure q1 → c1
! ... then treat c0, c1 as quantum control?
call c%add_gate(GATE_PAULI_X, 2, control=1, status=st)  ! c1 is classical!
call c%add_gate(GATE_PAULI_Z, 2, control=0, status=st)  ! c0 is classical!
```

**The Problem:**
The IR does not distinguish between:
1. **Quantum control**: `CNOT(target, control)` — gate applied if control qubit is in state |1⟩
2. **Classical control**: `if classical_bit == 1 then apply gate` — gate applied based on measurement result

The current implementation conflates these by overloading the `control` field in `bob_gate_t`.

**Phase 1 Workaround:**
For Phase 1, this is documented as a known limitation. The IR needs a **classical control gate type** to properly express feed-forward from measurement to conditioned operations. This will be implemented in Phase 1B (Task 3.1).

**Correct Structure (Future):**
```fortran
! Teleportation with proper IR:
call c%add_measure(0, 0, status=st)  ! Measure q0 → classical bit c[0]
call c%add_measure(1, 1, status=st)  ! Measure q1 → classical bit c[1]
! Apply X if c[1] == 1 (classical control)
call c%add_gate(GATE_COND_X, 2, classical_condition=1, status=st)
! Apply Z if c[0] == 1 (classical control)
call c%add_gate(GATE_COND_Z, 2, classical_condition=0, status=st)
call c%add_measure(2, 2, status=st)
```

**Reference:**
- Nielsen & Chuang, Section 1.3.7: Quantum Teleportation
- OpenQASM 3 standard: Classical memory and feed-forward gates

---

## Depth Calculation Bug

**Location**: `circuit_depth()` in bob_circuit.f90:146-150

**Current Implementation (WRONG):**
```fortran
pure function circuit_depth(this) result(d)
  class(bob_circuit_t), intent(in) :: this
  integer(i4) :: d
  d = this%num_gates  ! BUG: Returns gate count, not depth!
end function circuit_depth
```

**Definition Mismatch:**
- **What it should be** (logical depth): The number of sequential layers needed to execute all gates, accounting for parallelization
- **What it is** (gate count): The total number of gates in the circuit

Example: A circuit with 8 gates executed in parallel (all on different qubits) should have depth = 1, but this function returns depth = 8.

**Correct Definition:**
Logical depth = 1 + max(activation layer of last qubit across all gates)

Algorithm:
1. Initialize depth[i] = 0 for each qubit i
2. For each gate in order:
   - layer[gate] = max(depth[control], depth[target]) + 1
   - depth[control] ← layer[gate]
   - depth[target] ← layer[gate]
3. Return max(depth[i]) across all qubits

**Phase 1 Fix:**
- Rename `circuit_depth()` → `circuit_gate_count()`
- Implement new `circuit_logical_depth()` with correct algorithm
- Update C ABI: Add `bob_circuit_logical_depth()` function
- Add tests verifying known circuit depths

**Reference:**
- QASM standard: Circuit depth is the longest critical path of dependencies
- Qiskit: `circuit.depth()` computes logical depth with this algorithm

---

## Phase 1 Deliverables Checklist

- [x] **SCAFFOLDS_IN_PROGRESS.md** — This document (documentation of known gaps)
- [ ] **Rename depth method** — Task 1.2 (circuit_depth → gate_count, add logical_depth)
- [ ] **Fix logical_depth implementation** — Task 2.1 (proper layer-based algorithm)
- [ ] **Implement inverse QFT** — Task 2.2 (exact_inverse_qft with 2π/2^k phases)
- [ ] **Add explicit rotation gates** — Task 2.3 (GATE_RX, GATE_RY, GATE_RZ)
- [ ] **Add classical control IR** — Task 3.1 (GATE_MEASURE_STORE, GATE_COND_GATE)
- [ ] **Fix teleportation circuit** — Task 3.2 (use classical IR in example)
- [ ] **Update README "What Runs Today"** — Task 5.2 (mark algorithms as IN_PROGRESS_SCAFFOLD)
- [ ] **Add property tests** — Task 5.1 (QFT unitarity, depth correctness)

---

## How to Use This Document

1. **For developers**: Read the "What's Stubbed" section before implementing a circuit module that depends on QFT, Grover, or Shor
2. **For reviewers**: Check this document when PR comments suggest "why doesn't this circuit work?" — likely because a scaffold is incomplete
3. **For testers**: Use the "Testing Requirement" section to write property tests that validate the scaffolds
4. **For researchers**: Phase 2 will complete these scaffolds; this document tracks the gap between Phase 1 (architecture) and Phase 2 (full algorithms)

---

## References

- **Nielsen & Chuang, "Quantum Computation and Quantum Information"** (2010)
  - Ch. 5: Quantum Algorithms (QFT, QPE)
  - Ch. 6: Quantum Search and Factoring (Grover, Shor)
  - Sec. 1.3.7: Quantum Teleportation
- **OpenQASM 2.0 & 3.0 Specifications**
- **Qiskit Terra Documentation**: Gate implementations and circuit depth definition
- **Beauregard, S. "Circuit for Shor's algorithm using 2n+3 qubits"** (2003)

---

**Author**: SnapKitty Quantum Compiler Team
**Date**: 2026-07-26
**Status**: Phase 1 - ACTIVE HARDENING
