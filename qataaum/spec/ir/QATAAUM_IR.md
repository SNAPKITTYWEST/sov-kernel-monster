# QATAAUM Intermediate Representation Family

**Project:** QATAAUM AS400-PULSE-MONAD  
**Version:** 1.0  
**Date:** 2026-07-21  
**Status:** SPECIFICATION

---

## 1. Overview

The QATAAUM IR family consists of 9 intermediate representation levels, each serving a specific purpose in the compilation pipeline. Each level has well-defined semantics, transformation rules, and verification conditions.

---

## 2. IR Level 0: Source AST

### 2.1 Purpose
Lossless representation of source code syntax.

### 2.2 Structure
```rust
pub struct SourceAST {
    pub version: Version,
    pub includes: Vec<Include>,
    pub statements: Vec<Statement>,
    pub source_map: SourceMap,
}
```

### 2.3 Properties
- **Lossless:** Can reconstruct original source
- **Untyped:** No type information
- **Unoptimized:** Preserves all source constructs
- **Location tracking:** Full span information

### 2.4 Transformations
- **Input:** Source code (OpenQASM 2/3, MetaQASM-4)
- **Output:** IR Level 1 (Typed AST)

---

## 3. IR Level 1: Typed Quantum AST

### 3.1 Purpose
Resolved names, types, effects, and dimensions.

### 3.2 Structure
```rust
pub struct TypedAST {
    pub version: Version,
    pub symbol_table: SymbolTable,
    pub type_env: TypeEnvironment,
    pub statements: Vec<TypedStatement>,
}

pub struct TypedStatement {
    pub stmt: Statement,
    pub ty: Type,
    pub effect: Effect,
    pub span: Span,
}
```

### 3.3 Properties
- **Type-checked:** All types resolved
- **Name-resolved:** All identifiers bound
- **Effect-tracked:** Side effects explicit
- **Dimension-checked:** Array bounds verified

### 3.4 Transformations
- **Input:** IR Level 0 (Source AST)
- **Output:** IR Level 2 (CFG)
- **Passes:** Name resolution, type checking, effect inference

---

## 4. IR Level 2: QATAAUM-CFG

### 4.1 Purpose
Hybrid classical-quantum control-flow graph.

### 4.2 Structure
```rust
pub struct CFG {
    pub entry: BlockId,
    pub blocks: HashMap<BlockId, BasicBlock>,
    pub edges: Vec<Edge>,
    pub exit: BlockId,
}

pub struct BasicBlock {
    pub id: BlockId,
    pub instructions: Vec<Instruction>,
    pub terminator: Terminator,
}

pub enum Terminator {
    Return(Value),
    Branch { condition: Value, true_block: BlockId, false_block: BlockId },
    Jump(BlockId),
    Unreachable,
}
```

### 4.3 Properties
- **Structured:** Well-formed CFG
- **Typed:** All values typed
- **Effect-ordered:** Side effects sequenced
- **Dominance:** Dominance tree computed

### 4.4 Transformations
- **Input:** IR Level 1 (Typed AST)
- **Output:** IR Level 3 (SSA)
- **Passes:** CFG construction, dominance analysis

---

## 5. IR Level 3: QATAAUM-SSA

### 5.1 Purpose
Static single assignment form with explicit measurement, branching, timing, and qubit effects.

### 5.2 Structure
```rust
pub struct SSA {
    pub functions: Vec<Function>,
    pub globals: Vec<Global>,
}

pub struct Function {
    pub name: String,
    pub params: Vec<Parameter>,
    pub return_type: Type,
    pub blocks: Vec<SSABlock>,
}

pub struct SSABlock {
    pub id: BlockId,
    pub phi_nodes: Vec<PhiNode>,
    pub instructions: Vec<SSAInstruction>,
    pub terminator: SSATerminator,
}

pub struct PhiNode {
    pub result: SSAValue,
    pub ty: Type,
    pub incoming: Vec<(SSAValue, BlockId)>,
}
```

### 5.3 Properties
- **SSA form:** Each variable assigned once
- **Phi nodes:** Merge points explicit
- **Use-def chains:** Explicit data flow
- **Memory SSA:** Memory effects tracked

### 5.4 Transformations
- **Input:** IR Level 2 (CFG)
- **Output:** IR Level 4 (GATE)
- **Passes:** SSA construction, optimization passes

---

## 6. IR Level 4: QATAAUM-GATE

### 6.1 Purpose
Hardware-independent gate and measurement representation.

### 6.2 Structure
```rust
pub struct GateIR {
    pub qubits: Vec<LogicalQubit>,
    pub gates: Vec<GateOp>,
    pub measurements: Vec<Measurement>,
    pub classical: Vec<ClassicalOp>,
}

pub enum GateOp {
    SingleQubit { gate: SingleQubitGate, qubit: LogicalQubit },
    TwoQubit { gate: TwoQubitGate, control: LogicalQubit, target: LogicalQubit },
    MultiQubit { gate: MultiQubitGate, qubits: Vec<LogicalQubit> },
}

pub enum SingleQubitGate {
    H, X, Y, Z, S, T, Sdg, Tdg,
    Rx(Angle), Ry(Angle), Rz(Angle),
    U(Angle, Angle, Angle),
}

pub enum TwoQubitGate {
    CX, CY, CZ, SWAP, CRx(Angle), CRy(Angle), CRz(Angle),
}
```

### 6.3 Properties
- **Logical qubits:** Not yet mapped to physical
- **Standard gates:** Canonical gate set
- **Decomposed:** Complex gates decomposed
- **Optimized:** Gate cancellation, rotation folding

### 6.4 Transformations
- **Input:** IR Level 3 (SSA)
- **Output:** IR Level 5 (TOPO)
- **Passes:** Gate decomposition, optimization

---

## 7. IR Level 5: QATAAUM-TOPO

### 7.1 Purpose
Target-coupled placement and routing representation.

### 7.2 Structure
```rust
pub struct TopoIR {
    pub physical_qubits: Vec<PhysicalQubit>,
    pub mapping: QubitMapping,
    pub gates: Vec<PhysicalGateOp>,
    pub swaps: Vec<SwapOp>,
    pub topology: Topology,
}

pub struct QubitMapping {
    pub logical_to_physical: HashMap<LogicalQubit, PhysicalQubit>,
    pub physical_to_logical: HashMap<PhysicalQubit, LogicalQubit>,
}

pub struct PhysicalGateOp {
    pub gate: GateOp,
    pub physical_qubits: Vec<PhysicalQubit>,
    pub cost: f64,
}
```

### 7.3 Properties
- **Physical qubits:** Mapped to hardware
- **Topology-aware:** Respects connectivity
- **SWAP-inserted:** Routing complete
- **Placement-optimized:** Minimizes SWAP overhead

### 7.4 Transformations
- **Input:** IR Level 4 (GATE)
- **Output:** IR Level 6 (SCHEDULE)
- **Passes:** Qubit placement, routing, SWAP insertion

---

## 8. IR Level 6: QATAAUM-SCHEDULE

### 8.1 Purpose
Time-aware operations, resource reservations, barriers, and dependencies.

### 8.2 Structure
```rust
pub struct ScheduleIR {
    pub timeline: Timeline,
    pub operations: Vec<ScheduledOp>,
    pub resources: ResourceMap,
    pub dependencies: DependencyGraph,
}

pub struct ScheduledOp {
    pub op: PhysicalGateOp,
    pub start_time: Time,
    pub duration: Duration,
    pub resources: Vec<Resource>,
    pub dependencies: Vec<OpId>,
}

pub struct Timeline {
    pub total_duration: Duration,
    pub critical_path: Vec<OpId>,
    pub parallelism: f64,
}
```

### 8.3 Properties
- **Time-ordered:** Operations scheduled
- **Resource-aware:** No conflicts
- **Dependency-respecting:** Correct ordering
- **Optimized:** Minimizes makespan

### 8.4 Transformations
- **Input:** IR Level 5 (TOPO)
- **Output:** IR Level 7 (PULSE)
- **Passes:** Scheduling, resource allocation

---

## 9. IR Level 7: QATAAUM-PULSE

### 9.1 Purpose
Provider-neutral pulse frames, ports, waveforms, captures, delays, phase shifts, and calibration references.

### 9.2 Structure
```rust
pub struct PulseIR {
    pub frames: Vec<Frame>,
    pub waveforms: Vec<Waveform>,
    pub pulse_sequence: Vec<PulseOp>,
    pub calibration: CalibrationData,
}

pub struct Frame {
    pub id: FrameId,
    pub qubit: PhysicalQubit,
    pub frequency: Frequency,
    pub phase: Phase,
}

pub enum PulseOp {
    Play { frame: FrameId, waveform: WaveformId, duration: Duration },
    Capture { frame: FrameId, duration: Duration },
    Delay { frame: FrameId, duration: Duration },
    SetFrequency { frame: FrameId, frequency: Frequency },
    ShiftPhase { frame: FrameId, phase: Phase },
    Barrier { frames: Vec<FrameId> },
}

pub struct Waveform {
    pub id: WaveformId,
    pub samples: Vec<Complex<f64>>,
    pub duration: Duration,
}
```

### 9.3 Properties
- **Pulse-level:** Low-level control
- **Frame-based:** Frequency and phase tracking
- **Waveform-explicit:** Pulse shapes defined
- **Calibrated:** Uses calibration data

### 9.4 Transformations
- **Input:** IR Level 6 (SCHEDULE)
- **Output:** IR Level 8 (EXEC)
- **Passes:** Pulse synthesis, calibration application

---

## 10. IR Level 8: QATAAUM-EXEC

### 10.1 Purpose
Backend package with executable instructions, metadata, proof receipts, and result schema.

### 10.2 Structure
```rust
pub struct ExecutableIR {
    pub metadata: ExecutableMetadata,
    pub instructions: Vec<ExecutableInstruction>,
    pub proof_receipts: Vec<ProofReceipt>,
    pub result_schema: ResultSchema,
    pub verification: VerificationData,
}

pub struct ExecutableMetadata {
    pub job_id: String,
    pub circuit_hash: Hash,
    pub compilation_hash: Hash,
    pub backend: Backend,
    pub processor: Processor,
    pub timestamp: Timestamp,
    pub compiler_version: Version,
}

pub struct ExecutableInstruction {
    pub instruction: Instruction,
    pub timing: TimingInfo,
    pub resources: Vec<Resource>,
    pub verification: Option<Witness>,
}

pub struct ProofReceipt {
    pub obligation: ProofObligation,
    pub witness: Witness,
    pub verified: bool,
    pub verifier: String,
}
```

### 10.3 Properties
- **Executable:** Ready for backend
- **Verified:** Proofs attached
- **Sealed:** Cryptographically signed
- **Traceable:** Complete provenance

### 10.4 Transformations
- **Input:** IR Level 7 (PULSE)
- **Output:** Backend execution
- **Passes:** Packaging, verification, sealing

---

## 11. IR Transformation Pipeline

```
Source Code (OpenQASM 2/3, MetaQASM-4)
    ↓
[Parser]
    ↓
IR-0: Source AST (lossless syntax)
    ↓
[Name Resolution, Type Checking]
    ↓
IR-1: Typed AST (resolved, typed)
    ↓
[CFG Construction]
    ↓
IR-2: QATAAUM-CFG (control flow)
    ↓
[SSA Transformation]
    ↓
IR-3: QATAAUM-SSA (single assignment)
    ↓
[Gate Decomposition, Optimization]
    ↓
IR-4: QATAAUM-GATE (logical gates)
    ↓
[Placement, Routing]
    ↓
IR-5: QATAAUM-TOPO (physical qubits)
    ↓
[Scheduling]
    ↓
IR-6: QATAAUM-SCHEDULE (time-aware)
    ↓
[Pulse Synthesis]
    ↓
IR-7: QATAAUM-PULSE (pulse-level)
    ↓
[Packaging, Verification]
    ↓
IR-8: QATAAUM-EXEC (executable)
    ↓
Backend Execution
```

---

## 12. Verification Conditions

Each IR level has verification conditions:

### IR-0 (Source AST)
- Syntax valid
- Source locations complete

### IR-1 (Typed AST)
- All names resolved
- All types valid
- Effects consistent

### IR-2 (CFG)
- Well-formed CFG
- Dominance properties
- No unreachable blocks

### IR-3 (SSA)
- SSA form valid
- Phi nodes correct
- Use-def chains valid

### IR-4 (GATE)
- Gates decomposed
- Qubits linear
- No cloning

### IR-5 (TOPO)
- Topology respected
- All qubits mapped
- SWAPs valid

### IR-6 (SCHEDULE)
- No resource conflicts
- Dependencies satisfied
- Timing valid

### IR-7 (PULSE)
- Frames consistent
- Waveforms valid
- Calibration applied

### IR-8 (EXEC)
- Proofs verified
- Metadata complete
- Signature valid

---

## 13. Optimization Passes

### Gate-Level Optimizations (IR-4)
- Gate cancellation (inverse pairs)
- Rotation folding (angle combination)
- Commutation analysis
- Dead gate elimination

### Topology-Level Optimizations (IR-5)
- Placement optimization
- SWAP reduction
- Lookahead routing

### Schedule-Level Optimizations (IR-6)
- Parallelization
- Resource packing
- Critical path reduction

---

## 14. Implementation Status

- [ ] IR-0: Source AST (partial - AST defined)
- [ ] IR-1: Typed AST
- [ ] IR-2: QATAAUM-CFG
- [ ] IR-3: QATAAUM-SSA
- [ ] IR-4: QATAAUM-GATE
- [ ] IR-5: QATAAUM-TOPO
- [ ] IR-6: QATAAUM-SCHEDULE
- [ ] IR-7: QATAAUM-PULSE
- [ ] IR-8: QATAAUM-EXEC

---

## 15. References

- SSA Form: Cytron et al., "Efficiently Computing Static Single Assignment Form"
- CFG: Aho, Sethi, Ullman, "Compilers: Principles, Techniques, and Tools"
- Quantum Circuit Optimization: Nam et al., "Automated optimization of large quantum circuits"
- Pulse Programming: McKay et al., "Qiskit Pulse: Programming Quantum Computers Through the Cloud"

---

**Document Status:** SPECIFICATION  
**Last Updated:** 2026-07-21  
**Maintained By:** ROLE-SYSTEM-ARCHITECT

**End of QATAAUM IR Specification**