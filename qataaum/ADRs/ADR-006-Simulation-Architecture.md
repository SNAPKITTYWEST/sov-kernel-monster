# ADR-006: Simulation Architecture

**Status**: ACCEPTED  
**Date**: 2026-07-21  
**Deciders**: Bob (ROLE-SYSTEM-ARCHITECT), ROLE-RUST-RUNTIME  
**Related**: ADR-000, ADR-001

---

## Context

QATAAUM requires quantum circuit simulation for:
1. Testing and validation
2. Algorithm development
3. Small-scale execution
4. Verification of compiler correctness

The simulator must:
- Support multiple simulation methods
- Scale to reasonable qubit counts
- Provide accurate results
- Integrate with the compiler pipeline
- Remain clean-room (not copy Qiskit simulator)

## Decision

We adopt a **Multi-Method Simulation Architecture**:

### 1. State-Vector Simulator (IMPLEMENTED)
**Status**: ✅ COMPLETE (11 tests passing)

**Method**: Full state vector |ψ⟩ = Σ αᵢ|i⟩
**Complexity**: O(2ⁿ) space, O(2ⁿ) time per gate
**Qubit Limit**: ~20-25 qubits (practical)

**Features**:
- Exact simulation
- All quantum gates supported
- Measurement with state collapse
- Deterministic (seeded RNG)

**Implementation**:
```rust
struct StateVector {
    amplitudes: Vec<Complex64>,  // 2^n amplitudes
    num_qubits: usize,
}
```

### 2. Density-Matrix Simulator (PLANNED)
**Status**: ⏳ PENDING

**Method**: Density matrix ρ = |ψ⟩⟨ψ|
**Complexity**: O(4ⁿ) space, O(8ⁿ) time per gate
**Qubit Limit**: ~10-15 qubits (practical)

**Features**:
- Mixed states
- Noise modeling
- Decoherence
- Open quantum systems

### 3. Stabilizer Simulator (PLANNED)
**Status**: ⏳ PENDING

**Method**: Stabilizer formalism (Gottesman-Knill)
**Complexity**: O(n²) space, O(n²) time per gate
**Qubit Limit**: 1000+ qubits

**Features**:
- Clifford gates only
- Efficient for QEC codes
- Fast simulation
- Limited gate set

### 4. Decision-Diagram Simulator (FUTURE)
**Status**: ⏳ FUTURE

**Method**: Binary decision diagrams
**Complexity**: Variable (depends on circuit structure)
**Qubit Limit**: 100+ qubits (for structured circuits)

**Features**:
- Exploits circuit structure
- Symbolic simulation
- Good for certain circuit classes

## Rationale

### Why Multiple Methods?

Different methods have different trade-offs:
- **State-vector**: Exact, general, limited scale
- **Density-matrix**: Noise modeling, very limited scale
- **Stabilizer**: Fast, limited gates, large scale
- **Decision-diagram**: Structured circuits, variable performance

### Why State-Vector First?

1. **General Purpose**: Supports all gates
2. **Exact Results**: No approximation
3. **Verification**: Needed for compiler testing
4. **Practical Scale**: 20 qubits sufficient for testing

## Implementation Status

### State-Vector Simulator ✅
**Complete**: 11 tests passing

**Features Implemented**:
- Single-qubit gates (X, Y, Z, H, S, T, Rx, Ry, Rz)
- Two-qubit gates (CX, CZ, SWAP)
- Three-qubit gates (Toffoli)
- Measurement with collapse
- Classical bit storage
- Deterministic execution

**Test Coverage**:
- Basic gates
- Entanglement (Bell states, GHZ states)
- Superposition
- Measurement
- Multi-qubit operations

### Density-Matrix Simulator ⏳
**Planned Features**:
- All state-vector features
- Noise channels (depolarizing, amplitude damping, phase damping)
- Kraus operators
- Partial trace
- Fidelity calculation

## Consequences

### Positive

1. **Flexible**: Choose simulator based on needs
2. **Scalable**: Different methods for different scales
3. **Accurate**: Exact simulation where possible
4. **Testable**: Verify compiler correctness

### Negative

1. **Complexity**: Multiple simulators to maintain
2. **Memory**: State-vector requires exponential memory
3. **Speed**: Simulation is slow for large circuits

### Mitigation

- **Lazy Evaluation**: Only simulate when needed
- **Caching**: Reuse simulation results
- **Parallelism**: Use multi-threading where possible
- **Approximation**: Use stabilizer for Clifford circuits

## Performance Targets

### State-Vector Simulator
- **10 qubits**: <1ms per gate
- **15 qubits**: <10ms per gate
- **20 qubits**: <100ms per gate
- **25 qubits**: <1s per gate (if memory available)

### Density-Matrix Simulator
- **5 qubits**: <10ms per gate
- **10 qubits**: <1s per gate
- **15 qubits**: <10s per gate

## Alternatives Considered

### Alternative 1: Only State-Vector
**Rejected**: Cannot model noise, limited scale

### Alternative 2: Only Stabilizer
**Rejected**: Cannot simulate non-Clifford gates

### Alternative 3: Copy Qiskit Aer
**Rejected**: Violates clean-room methodology

### Alternative 4: Use External Simulator
**Rejected**: Want self-contained system

## Related Decisions

- **ADR-000**: Architecture Foundation
- **ADR-001**: IR Family Design
- **ADR-004**: Hardware Abstraction Layer

---

**Decision**: ACCEPTED  
**Architect**: Bob (ROLE-SYSTEM-ARCHITECT)  
**Date**: 2026-07-21

// Made with Bob