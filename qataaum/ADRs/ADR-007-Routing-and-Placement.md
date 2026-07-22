# ADR-007: Routing and Placement Strategy

**Status**: ACCEPTED  
**Date**: 2026-07-21  
**Deciders**: Bob (ROLE-SYSTEM-ARCHITECT)  
**Related**: ADR-000, ADR-001, ADR-004

---

## Context

Quantum hardware has limited connectivity - not all qubit pairs can interact directly. QATAAUM must:
1. Map logical qubits to physical qubits (placement)
2. Insert SWAP gates to enable non-adjacent interactions (routing)
3. Minimize SWAP overhead
4. Respect hardware topology
5. Use clean-room algorithms (not copy Qiskit)

## Decision

We adopt a **Two-Phase Routing Strategy**:

### Phase 1: Initial Placement
**Goal**: Map logical qubits to physical qubits

**Algorithm**: Greedy placement with lookahead
```
1. Analyze circuit gate dependencies
2. Build interaction graph
3. Find high-interaction qubit pairs
4. Place them on adjacent physical qubits
5. Iteratively place remaining qubits
```

### Phase 2: SWAP Routing
**Goal**: Insert SWAPs to enable non-adjacent gates

**Algorithm**: SABRE-inspired (public algorithm)
```
1. Maintain front layer of executable gates
2. For each non-executable gate:
   a. Find shortest path between qubits
   b. Insert SWAP on path
   c. Update qubit mapping
3. Execute front layer gates
4. Repeat until circuit complete
```

## Rationale

### Why Two Phases?

1. **Placement First**: Good initial placement reduces SWAP count
2. **Routing Second**: Handle remaining connectivity issues
3. **Separation of Concerns**: Each phase has clear goal

### Why SABRE-Inspired?

SABRE (SWAP-based BidirEctional heuristic search) is:
- **Public**: Published in academic paper
- **Effective**: Good SWAP overhead in practice
- **Adaptable**: Can be modified for our needs
- **Clean-Room Safe**: Algorithm is public, not implementation

**Source**: Li et al., "Tackling the Qubit Mapping Problem for NISQ-Era Quantum Devices", ASPLOS 2019

### Why Not Optimal?

Optimal routing is NP-hard. Heuristics provide:
- **Reasonable Results**: 2-5x overhead typical
- **Fast Compilation**: Polynomial time
- **Practical**: Works for real circuits

## Heavy-Hex Topology Support

IBM's heavy-hex topology has special properties:
- **Degree-3 Graph**: Each qubit connects to ≤3 neighbors
- **Regular Structure**: Repeating hexagonal pattern
- **Efficient Routing**: Better than linear chains

**Topology Representation**:
```rust
struct HeavyHexTopology {
    rows: usize,
    cols: usize,
    edges: Vec<(QubitId, QubitId)>,
}
```

## SWAP Insertion Strategy

### Basic SWAP
```
SWAP(q0, q1) = CX(q0, q1); CX(q1, q0); CX(q0, q1)
```

### Optimizations
1. **SWAP Cancellation**: Remove back-to-back SWAPs
2. **SWAP Commutation**: Move SWAPs past commuting gates
3. **Bridge Gates**: Use intermediate qubits when beneficial

## Consequences

### Positive

1. **Hardware Compatibility**: Circuits run on real hardware
2. **Reasonable Overhead**: 2-5x depth increase typical
3. **Clean-Room**: Independent algorithm design
4. **Extensible**: Easy to add new topologies

### Negative

1. **SWAP Overhead**: Increases circuit depth and errors
2. **Suboptimal**: Heuristic, not optimal
3. **Topology Dependent**: Different strategies for different topologies

### Mitigation

- **Good Placement**: Minimize initial SWAP need
- **Optimization**: Cancel and commute SWAPs
- **Topology Awareness**: Use topology-specific heuristics

## Implementation Plan

**Phase 1** (PENDING):
- ⏳ Connectivity graph representation
- ⏳ Heavy-hex topology generator
- ⏳ Shortest path algorithm (Dijkstra/BFS)

**Phase 2** (PENDING):
- ⏳ Initial placement heuristic
- ⏳ SABRE-inspired routing
- ⏳ SWAP insertion and tracking

**Phase 3** (PENDING):
- ⏳ SWAP optimization passes
- ⏳ Routing verification
- ⏳ Benchmarking

## Performance Targets

### SWAP Overhead
- **Small circuits** (<50 gates): <2x depth increase
- **Medium circuits** (50-200 gates): <3x depth increase
- **Large circuits** (>200 gates): <5x depth increase

### Compilation Time
- **100 gates**: <100ms
- **1000 gates**: <1s
- **10000 gates**: <10s

## Alternatives Considered

### Alternative 1: Optimal Routing (ILP/SAT)
**Rejected**: Too slow for practical circuits

### Alternative 2: Random Placement
**Rejected**: Poor SWAP overhead

### Alternative 3: Copy Qiskit Routing
**Rejected**: Violates clean-room methodology

### Alternative 4: No Routing (Assume All-to-All)
**Rejected**: Doesn't match real hardware

## Related Decisions

- **ADR-000**: Architecture Foundation
- **ADR-001**: IR Family Design
- **ADR-004**: Hardware Abstraction Layer

---

**Decision**: ACCEPTED  
**Architect**: Bob (ROLE-SYSTEM-ARCHITECT)  
**Date**: 2026-07-21

// Made with Bob