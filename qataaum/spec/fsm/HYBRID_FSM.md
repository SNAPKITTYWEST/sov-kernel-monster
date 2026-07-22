# QATAAUM Hybrid Finite-State Machine Specification

**Project:** QATAAUM AS400-PULSE-MONAD  
**Version:** 1.0  
**Date:** 2026-07-21  
**Status:** SPECIFICATION

---

## 1. Overview

The QATAAUM Hybrid FSM coordinates classical IBM i control with quantum circuit compilation, execution, and verification states. All state transitions are deterministic, journaled, and cryptographically sealed for audit and recovery.

---

## 2. State Definitions

### 2.1 Primary States

| State ID | Name | Description |
|----------|------|-------------|
| S0 | RECEIVED | Job received, initial validation pending |
| S1 | SOURCE_VALIDATED | Source code syntax validated |
| S2 | PARSED | AST constructed successfully |
| S3 | TYPED | Type checking complete |
| S4 | IR_GENERATED | Initial IR (Level 0-1) created |
| S5 | PROOF_OBLIGATIONS_CREATED | Verification conditions generated |
| S6 | OPTIMIZED | Circuit optimizations applied |
| S7 | TARGET_SELECTED | Backend and processor selected |
| S8 | ROUTED | Qubits mapped to physical topology |
| S9 | SCHEDULED | Operations scheduled with timing |
| S10 | PULSE_LOWERED | Lowered to pulse-level IR |
| S11 | VERIFIED | Formal verification complete |
| S12 | QUEUED | Submitted to execution queue |
| S13 | EXECUTING | Running on backend |
| S14 | MEASURED | Measurement results obtained |
| S15 | MITIGATED | Error mitigation applied |
| S16 | RECEIPT_SEALED | Execution receipt generated |
| S17 | COMPLETED | Job successfully completed |

### 2.2 Error States

| State ID | Name | Description |
|----------|------|-------------|
| SF | FAILED | Unrecoverable error occurred |
| SR | RECOVERING | Attempting recovery from failure |
| SX | REJECTED | Job rejected (invalid input, capability mismatch) |

---

## 3. State Transition Rules

### 3.1 Transition Structure

Every transition requires:
```rust
struct Transition {
    from_state: StateId,
    to_state: StateId,
    event: Event,
    guard: Option<Guard>,
    action: Action,
    timestamp: Timestamp,
    sequence: u64,
    digest: Hash,
}
```

### 3.2 Transition Table

| From | Event | Guard | To | Action |
|------|-------|-------|-----|--------|
| S0 | JobReceived | - | S1 | ValidateSource |
| S1 | SourceValid | - | S2 | ParseSource |
| S1 | SourceInvalid | - | SX | RejectJob |
| S2 | ParseSuccess | - | S3 | TypeCheck |
| S2 | ParseError | - | SX | RejectJob |
| S3 | TypeCheckSuccess | - | S4 | GenerateIR |
| S3 | TypeCheckError | - | SX | RejectJob |
| S4 | IRGenerated | - | S5 | GenerateProofObligations |
| S5 | ProofsGenerated | - | S6 | OptimizeCircuit |
| S6 | OptimizationComplete | - | S7 | SelectTarget |
| S7 | TargetSelected | CapabilityCheck | S8 | RouteQubits |
| S7 | CapabilityMismatch | - | SX | RejectJob |
| S8 | RoutingComplete | - | S9 | ScheduleOperations |
| S9 | SchedulingComplete | - | S10 | LowerToPulse |
| S10 | PulseLowered | - | S11 | VerifyCircuit |
| S11 | VerificationSuccess | - | S12 | QueueForExecution |
| S11 | VerificationFailure | - | SX | RejectJob |
| S12 | ExecutionStarted | - | S13 | ExecuteCircuit |
| S13 | ExecutionComplete | - | S14 | CollectResults |
| S13 | ExecutionError | Recoverable | SR | AttemptRecovery |
| S13 | ExecutionError | !Recoverable | SF | FailJob |
| S14 | ResultsCollected | - | S15 | ApplyMitigation |
| S15 | MitigationComplete | - | S16 | SealReceipt |
| S16 | ReceiptSealed | - | S17 | CompleteJob |
| SR | RecoverySuccess | - | S12 | QueueForExecution |
| SR | RecoveryFailure | - | SF | FailJob |

### 3.3 Invalid Transitions

Any transition not in the table above is **INVALID** and results in:
- Transition to REJECTED state
- Error logged
- Alert generated
- Job terminated

---

## 4. State Properties

### 4.1 State Invariants

**S0 (RECEIVED):**
- Job ID assigned
- Source code present
- Timestamp recorded

**S2 (PARSED):**
- Valid AST exists
- No parse errors
- Source location tracking complete

**S3 (TYPED):**
- All types resolved
- No type errors
- Effect annotations validated

**S8 (ROUTED):**
- All qubits mapped to physical qubits
- Topology constraints satisfied
- SWAP gates inserted if needed

**S11 (VERIFIED):**
- All proof obligations discharged
- Witnesses attached
- Verification receipt generated

**S17 (COMPLETED):**
- Results available
- Receipt sealed
- Audit trail complete

### 4.2 State Timeouts

| State | Timeout | Action on Timeout |
|-------|---------|-------------------|
| S0-S11 | 5 minutes | → SF (compilation timeout) |
| S12 | 1 hour | → SF (queue timeout) |
| S13 | Backend-dependent | → SR (attempt recovery) |
| S14-S16 | 10 minutes | → SF (post-processing timeout) |
| SR | 5 minutes | → SF (recovery timeout) |

---

## 5. Events

### 5.1 Event Types

```rust
enum Event {
    // Input events
    JobReceived { job_id: String, source: String },
    
    // Compilation events
    SourceValid,
    SourceInvalid { errors: Vec<Error> },
    ParseSuccess { ast: AST },
    ParseError { errors: Vec<Error> },
    TypeCheckSuccess { typed_ast: TypedAST },
    TypeCheckError { errors: Vec<Error> },
    IRGenerated { ir: IR },
    ProofsGenerated { obligations: Vec<ProofObligation> },
    OptimizationComplete { optimized_ir: IR },
    TargetSelected { backend: Backend, processor: Processor },
    CapabilityMismatch { required: Vec<Capability>, available: Vec<Capability> },
    RoutingComplete { routed_ir: IR },
    SchedulingComplete { scheduled_ir: IR },
    PulseLowered { pulse_ir: IR },
    VerificationSuccess { witnesses: Vec<Witness> },
    VerificationFailure { failures: Vec<ProofFailure> },
    
    // Execution events
    ExecutionStarted { job_handle: JobHandle },
    ExecutionComplete { raw_results: RawResults },
    ExecutionError { error: ExecutionError, recoverable: bool },
    ResultsCollected { results: Results },
    MitigationComplete { mitigated_results: Results },
    ReceiptSealed { receipt: Receipt },
    
    // Recovery events
    RecoverySuccess,
    RecoveryFailure { reason: String },
    
    // Completion events
    CompleteJob,
}
```

---

## 6. Guards

### 6.1 Guard Conditions

```rust
enum Guard {
    CapabilityCheck {
        required: Vec<Capability>,
        available: Vec<Capability>,
    },
    
    ResourceAvailable {
        qubits: usize,
        memory: usize,
    },
    
    TimeoutNotExceeded {
        elapsed: Duration,
        limit: Duration,
    },
    
    ProofObligationsSatisfied {
        obligations: Vec<ProofObligation>,
        witnesses: Vec<Witness>,
    },
}

impl Guard {
    fn evaluate(&self) -> bool {
        match self {
            Guard::CapabilityCheck { required, available } => {
                required.iter().all(|cap| available.contains(cap))
            }
            Guard::ResourceAvailable { qubits, memory } => {
                check_resources(*qubits, *memory)
            }
            Guard::TimeoutNotExceeded { elapsed, limit } => {
                elapsed < limit
            }
            Guard::ProofObligationsSatisfied { obligations, witnesses } => {
                verify_proofs(obligations, witnesses)
            }
        }
    }
}
```

---

## 7. Actions

### 7.1 Action Types

```rust
enum Action {
    ValidateSource { source: String },
    ParseSource { source: String },
    TypeCheck { ast: AST },
    GenerateIR { typed_ast: TypedAST },
    GenerateProofObligations { ir: IR },
    OptimizeCircuit { ir: IR },
    SelectTarget { requirements: Requirements },
    RouteQubits { ir: IR, topology: Topology },
    ScheduleOperations { ir: IR, timing: TimingConstraints },
    LowerToPulse { ir: IR, calibration: Calibration },
    VerifyCircuit { ir: IR, obligations: Vec<ProofObligation> },
    QueueForExecution { executable: Executable },
    ExecuteCircuit { executable: Executable },
    CollectResults { job_handle: JobHandle },
    ApplyMitigation { results: RawResults },
    SealReceipt { results: Results, metadata: Metadata },
    CompleteJob { receipt: Receipt },
    RejectJob { reason: String },
    FailJob { error: Error },
    AttemptRecovery { error: ExecutionError },
}
```

---

## 8. Journaling

### 8.1 Journal Entry Structure

```rust
struct JournalEntry {
    sequence: u64,
    timestamp: Timestamp,
    job_id: String,
    from_state: StateId,
    to_state: StateId,
    event: Event,
    action: Action,
    result: ActionResult,
    digest: Hash,
    signature: Signature,
}
```

### 8.2 Journal Properties

- **Append-only:** Entries never modified or deleted
- **Ordered:** Sequence numbers strictly increasing
- **Cryptographically sealed:** Each entry signed
- **Chained:** Each entry references previous digest
- **Recoverable:** Can replay from any point

### 8.3 Recovery Protocol

```rust
fn recover_from_journal(job_id: &str, target_state: StateId) -> Result<State> {
    let entries = load_journal_entries(job_id)?;
    let mut state = State::new(StateId::S0);
    
    for entry in entries {
        if entry.to_state == target_state {
            break;
        }
        state = apply_transition(state, entry)?;
    }
    
    Ok(state)
}
```

---

## 9. State Machine Implementation

### 9.1 State Machine Structure

```rust
pub struct HybridFSM {
    current_state: StateId,
    job_id: String,
    context: Context,
    journal: Journal,
    transitions: TransitionTable,
}

impl HybridFSM {
    pub fn new(job_id: String) -> Self {
        Self {
            current_state: StateId::S0,
            job_id,
            context: Context::new(),
            journal: Journal::new(),
            transitions: TransitionTable::default(),
        }
    }
    
    pub fn transition(&mut self, event: Event) -> Result<StateId> {
        let transition = self.transitions.find(self.current_state, &event)?;
        
        // Check guard
        if let Some(guard) = &transition.guard {
            if !guard.evaluate() {
                return Err(Error::GuardFailed);
            }
        }
        
        // Execute action
        let result = transition.action.execute(&mut self.context)?;
        
        // Journal transition
        self.journal.append(JournalEntry {
            sequence: self.journal.next_sequence(),
            timestamp: Timestamp::now(),
            job_id: self.job_id.clone(),
            from_state: self.current_state,
            to_state: transition.to_state,
            event,
            action: transition.action,
            result,
            digest: self.journal.compute_digest(),
            signature: self.journal.sign(),
        })?;
        
        // Update state
        self.current_state = transition.to_state;
        
        Ok(self.current_state)
    }
}
```

---

## 10. Integration with IBM i

### 10.1 Job Queue Integration

```
IBM i Job Queue (QJOB)
    ↓
Job Received (S0)
    ↓
Compilation States (S1-S11)
    ↓
IBM i Data Queue (QDTA)
    ↓
Execution States (S12-S14)
    ↓
IBM i Journal (QJRN)
    ↓
Completion States (S15-S17)
    ↓
IBM i Spool File (QSPL)
```

### 10.2 ShadowRPG-Q Integration

```shadowrpg
     C                   EVAL      JobID = 'BELL-001'
     C                   EVAL      State = *RECEIVED
     
     C                   CALL      'QFSM_TRANSITION'
     C                   PARM                    JobID
     C                   PARM                    Event
     C                   PARM                    NewState
     
     C                   IF        NewState = *COMPLETED
     C                   CALL      'QRETRIEVE_RESULT'
     C                   ENDIF
```

---

## 11. Monitoring and Observability

### 11.1 State Metrics

```rust
struct StateMetrics {
    state_id: StateId,
    entry_count: u64,
    total_time: Duration,
    average_time: Duration,
    error_count: u64,
    timeout_count: u64,
}
```

### 11.2 Transition Metrics

```rust
struct TransitionMetrics {
    from_state: StateId,
    to_state: StateId,
    count: u64,
    success_rate: f64,
    average_duration: Duration,
}
```

---

## 12. Testing Strategy

### 12.1 State Tests

- Test each state's invariants
- Test state entry/exit actions
- Test state timeouts

### 12.2 Transition Tests

- Test all valid transitions
- Test invalid transitions (should reject)
- Test guard conditions
- Test action execution

### 12.3 Recovery Tests

- Test journal replay
- Test recovery from each state
- Test recovery failure handling

---

## 13. Formal Specification

### 13.1 State Machine Properties

**Safety:** No invalid transitions occur  
**Liveness:** Every job eventually reaches COMPLETED, FAILED, or REJECTED  
**Determinism:** Same inputs produce same state sequence  
**Recoverability:** Can resume from any journaled state  

### 13.2 Lean 4 Formalization

```lean
-- State machine formalization (stub)
inductive State where
  | received
  | parsed
  | typed
  -- ... other states

inductive Event where
  | jobReceived
  | sourceValid
  -- ... other events

def transition : State → Event → Option State
  | State.received, Event.jobReceived => some State.parsed
  -- ... other transitions

theorem deterministic_transitions :
  ∀ (s : State) (e : Event),
    transition s e = transition s e := by
  intro s e
  rfl
```

---

## 14. References

- IBM i Job Management: https://www.ibm.com/docs/en/i
- Finite State Machines: Hopcroft & Ullman
- Journaling Systems: Gray & Reuter, "Transaction Processing"

---

**Document Status:** SPECIFICATION  
**Last Updated:** 2026-07-21  
**Maintained By:** ROLE-SYSTEM-ARCHITECT

**End of Hybrid FSM Specification**