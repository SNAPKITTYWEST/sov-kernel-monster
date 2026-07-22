# ADR-008: IBM i Integration Strategy

**Status**: ACCEPTED  
**Date**: 2026-07-21  
**Deciders**: Bob (ROLE-RPG-ENGINEER), ROLE-SYSTEM-ARCHITECT  
**Related**: ADR-000

---

## Context

QATAAUM is inspired by IBM i operational principles:
- Record-oriented processing
- Job queues and journaling
- Deterministic restart
- Audit trails
- Command-driven interfaces

The system must:
1. Provide IBM i-style operational control
2. Support portable development (non-IBM i systems)
3. Maintain clean-room boundaries
4. Never copy proprietary IBM i code

## Decision

We adopt a **Dual-Mode Architecture**:

### Mode 1: Native IBM i (When Available)
**Environment**: IBM i with RPG compiler

**Components**:
- **ShadowRPG-Q**: RPG-inspired control language
- **Service Programs**: ILE-compatible modules
- **Data Queues**: Job submission and results
- **Journaling**: Transaction log and recovery
- **Command Interface**: CL-style commands

### Mode 2: Portable Compatibility Layer
**Environment**: Linux, Windows, macOS

**Components**:
- **ShadowRPG-Q Interpreter**: Rust-based executor
- **Queue Emulation**: File-based or database queues
- **Journal Emulation**: Append-only log files
- **Command Emulation**: CLI interface

## ShadowRPG-Q Language

**Purpose**: Job control and quantum workflow orchestration

**Design Principles**:
1. **Record-Oriented**: Fixed-format or free-form records
2. **Declarative**: Describe what, not how
3. **Typed**: Strong typing for quantum resources
4. **Auditable**: Every operation logged

**Example**:
```rpg
DCL-JOB QUANTUM_BELL_STATE;
DCL-QREG Q 2;
DCL-CREG C 2;

QASM-SOURCE 'bell_state.qasm';
COMPILE TARGET(HERON_R3) OPTIMIZE(LEVEL2);
EXECUTE SHOTS(1024);
RETRIEVE RESULTS(C);
END-JOB;
```

## Job Lifecycle

### 1. Submission
```
User → Command Interface → Job Queue → Journal Entry
```

### 2. Processing
```
Job Queue → Compiler → Optimizer → Scheduler → Executor
```

### 3. Completion
```
Executor → Results → Journal Entry → User Notification
```

### 4. Recovery
```
Journal → Replay → Restore State → Resume
```

## Record Formats

### Job Record
```rust
struct JobRecord {
    job_id: JobId,
    user: String,
    timestamp: Timestamp,
    source_hash: Hash,
    target: ProcessorProfile,
    optimization_level: u8,
    shots: usize,
    status: JobStatus,
}
```

### Result Record
```rust
struct ResultRecord {
    job_id: JobId,
    execution_time: Duration,
    result_hash: Hash,
    measurements: HashMap<BitId, Vec<u8>>,
    metadata: Metadata,
}
```

### Journal Entry
```rust
struct JournalEntry {
    sequence: u64,
    timestamp: Timestamp,
    operation: Operation,
    data: Vec<u8>,
    checksum: Hash,
}
```

## Rationale

### Why IBM i Inspiration?

1. **Reliability**: IBM i principles proven over decades
2. **Auditability**: Every operation traceable
3. **Recoverability**: Deterministic restart from journal
4. **Operational Excellence**: Clear job lifecycle

### Why Dual-Mode?

1. **Accessibility**: Most developers don't have IBM i access
2. **Development**: Faster iteration on portable systems
3. **Deployment**: Can deploy on IBM i when available
4. **Testing**: Test on any platform

### Why ShadowRPG-Q?

1. **Domain-Specific**: Tailored for quantum workflows
2. **Familiar**: RPG-like syntax for IBM i users
3. **Clean-Room**: Original language, not copied
4. **Typed**: Quantum-specific type system

## Consequences

### Positive

1. **Operational Excellence**: IBM i-style reliability
2. **Portable**: Works on any platform
3. **Auditable**: Complete operation history
4. **Recoverable**: Restart from any point

### Negative

1. **Complexity**: Two modes to maintain
2. **Learning Curve**: New language (ShadowRPG-Q)
3. **Emulation Overhead**: Portable mode has overhead

### Mitigation

- **Shared Core**: Most code shared between modes
- **Documentation**: Comprehensive ShadowRPG-Q guide
- **Performance**: Optimize portable mode

## Implementation Plan

**Phase 1** (PENDING):
- ⏳ Define ShadowRPG-Q grammar
- ⏳ Implement parser and interpreter
- ⏳ Create job record formats

**Phase 2** (PENDING):
- ⏳ Implement portable queue system
- ⏳ Implement portable journaling
- ⏳ Create command interface

**Phase 3** (PENDING):
- ⏳ Native IBM i integration (if environment available)
- ⏳ RPG service programs
- ⏳ ILE activation groups

## Alternatives Considered

### Alternative 1: Python Scripts
**Rejected**: Not operational-grade, no IBM i integration

### Alternative 2: Copy IBM i CL
**Rejected**: Proprietary, violates clean-room

### Alternative 3: No IBM i Integration
**Rejected**: Misses opportunity for operational excellence

## Related Decisions

- **ADR-000**: Architecture Foundation
- **ADR-009**: Execution Receipt System (pending)

---

**Decision**: ACCEPTED  
**Architect**: Bob (ROLE-SYSTEM-ARCHITECT)  
**Date**: 2026-07-21

// Made with Bob