# ADR-004: Hardware Abstraction Layer

**Status**: ACCEPTED  
**Date**: 2026-07-21  
**Deciders**: Bob (ROLE-SYSTEM-ARCHITECT)  
**Related**: ADR-000, ADR-001, ADR-002

---

## Context

QATAAUM must support multiple quantum hardware backends:
- IBM Quantum processors (Heron, Nighthawk, etc.)
- Simulators (state-vector, density-matrix)
- Future providers (hypothetical)

The system must:
1. Abstract hardware differences
2. Support provider-neutral code
3. Enable capability checking
4. Maintain clean-room boundaries
5. Never invent undocumented hardware specs

## Decision

We adopt a **Processor Profile System** with capability-based abstraction:

### 1. Processor Profile Schema
```rust
struct ProcessorProfile {
    provider: String,
    family: String,
    revision: String,
    status: ProfileStatus,
    qubit_count: usize,
    connectivity: ConnectivityGraph,
    native_gates: Vec<GateFamily>,
    measurement_caps: MeasurementCapabilities,
    dynamic_circuits: bool,
    timing_resolution: Duration,
    pulse_access: PulseAccessLevel,
    public_evidence: Vec<SourceReference>,
    unknown_properties: Vec<String>,
}

enum ProfileStatus {
    PublicRevision,   // Documented by provider
    Hypothetical,     // Not publicly documented
    Simulated,        // Synthetic for testing
}
```

### 2. Connectivity Graph
```rust
struct ConnectivityGraph {
    topology: TopologyKind,
    edges: Vec<(QubitId, QubitId)>,
    degree: HashMap<QubitId, usize>,
}

enum TopologyKind {
    HeavyHex,         // IBM heavy-hexagonal
    Linear,           // Linear chain
    AllToAll,         // Fully connected
    Custom(String),   // Custom topology
}
```

### 3. Capability Checking
```rust
trait CapabilityChecker {
    fn supports_gate(&self, gate: &GateKind) -> bool;
    fn supports_connectivity(&self, q1: QubitId, q2: QubitId) -> bool;
    fn supports_dynamic_circuits(&self) -> bool;
    fn supports_mid_circuit_measurement(&self) -> bool;
    fn get_gate_duration(&self, gate: &GateKind) -> Option<Duration>;
}
```

## Rationale

### Why Processor Profiles?

1. **Data-Driven**: Hardware specs are data, not code
2. **Verifiable**: Each profile references public documentation
3. **Extensible**: Easy to add new processors
4. **Clean-Room Safe**: Explicit about what's known vs unknown

### Why Capability Checking?

Prevents compilation of unsupported operations:
```rust
if !profile.supports_gate(&GateKind::Toffoli) {
    return Err("Toffoli gate not supported on this backend");
}
```

### Why Explicit Unknown Properties?

**Critical for clean-room compliance**:
- Never invent specifications
- Mark unknowns explicitly
- Require public documentation

## Consequences

### Positive

1. **Provider Neutral**: Code works across backends
2. **Safe Compilation**: Catch unsupported operations early
3. **Clean-Room Compliant**: Explicit about sources
4. **Extensible**: Easy to add new backends

### Negative

1. **Profile Maintenance**: Must update as hardware evolves
2. **Capability Complexity**: Many capabilities to track
3. **Unknown Handling**: Must handle missing information

## Implementation Plan

**Phase 1** (PENDING):
- ⏳ Processor profile data structure
- ⏳ Heavy-hex topology generator
- ⏳ Capability checker interface

**Phase 2** (PENDING):
- ⏳ Heron r1/r2/r3 profiles (from public docs)
- ⏳ Nighthawk r1 profile (verify public docs)
- ⏳ Simulator profiles

**Phase 3** (PENDING):
- ⏳ Routing engine (SWAP insertion)
- ⏳ Placement engine (qubit mapping)
- ⏳ Scheduling engine (timing)

## Documented Processors

**PUBLIC** (from IBM Quantum documentation):
- Heron r1: 133 qubits, heavy-hex, dynamic circuits
- Heron r2: 133 qubits, improved fidelity
- Heron r3: 133 qubits, production-ready

**REQUIRES VERIFICATION**:
- Nighthawk r1: 120 qubits (per spec, verify public docs)

**HYPOTHETICAL** (not publicly documented):
- Heron r4: Must be marked HYPOTHETICAL
- Nighthawk r2+: Must be marked HYPOTHETICAL

## Alternatives Considered

### Alternative 1: Hard-Coded Hardware
**Rejected**: Not extensible, not data-driven

### Alternative 2: Copy Qiskit Backend System
**Rejected**: Violates clean-room methodology

### Alternative 3: Assume All Hardware Same
**Rejected**: Ignores real hardware constraints

## Related Decisions

- **ADR-000**: Architecture Foundation
- **ADR-001**: IR Family Design
- **ADR-007**: Routing and Placement (pending)

---

**Decision**: ACCEPTED  
**Architect**: Bob (ROLE-SYSTEM-ARCHITECT)  
**Date**: 2026-07-21

// Made with Bob