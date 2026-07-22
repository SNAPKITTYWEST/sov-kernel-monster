# ShadowRPG-Q: IBM i-Style Quantum Job Control Runtime

**Status:** Original experimental implementation  
**NOT an IBM product** - Independent clean-room implementation

## Overview

ShadowRPG-Q is an original quantum job control runtime inspired by IBM i operational workflows, record-oriented processing, and job queue management. It provides:

- **Job Queue Management**: Priority-based job scheduling
- **Append-Only Journaling**: Deterministic replay and recovery
- **Execution Receipts**: Cryptographically sealed provenance records
- **Hybrid FSM Coordination**: Classical control with quantum execution states

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    ShadowRPG-Q Runtime                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐            │
│  │   Job    │───▶│  Queue   │───▶│ Executor │            │
│  │ Builder  │    │ Priority │    │  Engine  │            │
│  └──────────┘    └──────────┘    └──────────┘            │
│                         │              │                   │
│                         ▼              ▼                   │
│                  ┌──────────┐    ┌──────────┐            │
│                  │ Journal  │    │ Receipt  │            │
│                  │ Append   │    │  Seal    │            │
│                  └──────────┘    └──────────┘            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Core Components

### Job (`job.rs`)
- Job lifecycle management (Received → Validated → Compiling → Compiled → Queued → Executing → Completed/Failed/Cancelled)
- Priority levels (Low, Normal, High)
- Builder pattern for job configuration
- Status tracking with timestamps

### Queue (`queue.rs`)
- Priority-based binary heap queue
- Configurable maximum size
- Thread-safe job submission and retrieval

### Journal (`journal.rs`)
- Append-only journal for audit trail
- Cryptographic hash verification
- Deterministic replay for recovery
- Journal entry types for all state transitions

### Receipt (`receipt.rs`)
- Cryptographically sealed execution receipts
- Source code hash, compilation hash, result hash
- Immutable provenance records
- Receipt chain verification

### Executor (`executor.rs`)
- Main execution engine
- Job submission and queue management
- Journal coordination
- Active job tracking
- Recovery from journal replay

## Usage Example

```rust
use shadow_rpg_q::{Executor, ExecutorConfig, Job, JobPriority};
use std::path::PathBuf;

// Create executor with configuration
let config = ExecutorConfig {
    max_queue_size: 1000,
    journal_path: PathBuf::from("quantum.journal"),
    max_concurrent_jobs: 4,
};

let executor = Executor::new(config)?;

// Create and submit a job
let job = Job::new(
    "bell_state".to_string(),
    "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];".to_string(),
    "qasm2".to_string(),
    "simulator".to_string(),
)
.with_priority(JobPriority::High)
.with_shots(1024);

let job_id = executor.submit_job(job)?;

// Get next job from queue
let job = executor.get_next_job()?.unwrap();

// Execute job
let receipt = executor.execute_job(job)?;

// Verify receipt seal
assert!(receipt.verify_seal());
```

## Job Lifecycle

```
RECEIVED ──▶ VALIDATED ──▶ COMPILING ──▶ COMPILED ──▶ QUEUED
                                                         │
                                                         ▼
COMPLETED ◀── EXECUTING ◀─────────────────────────────────
    │
    ├──▶ FAILED
    └──▶ CANCELLED
```

## Journal Format

Each journal entry contains:
- Sequence number (monotonically increasing)
- Timestamp (UTC)
- Job ID
- Entry type (JobSubmitted, StatusChanged, etc.)
- Old and new status
- Metadata
- Cryptographic hash

## Receipt Format

Each execution receipt contains:
- Receipt ID (UUID)
- Job ID
- Source code hash (SHA-256)
- Compilation hash (SHA-256)
- Result hash (SHA-256)
- Timestamps (submitted, started, completed)
- Status
- Metadata (priority, language, shots)
- Cryptographic seal

## Testing

```bash
cargo test -p shadow-rpg-q
```

**Test Results:** 15/15 tests passing

## Design Principles

1. **Record-Oriented**: All state is represented as immutable records
2. **Append-Only**: Journal entries are never modified or deleted
3. **Deterministic**: Replay from journal produces identical state
4. **Verifiable**: All receipts are cryptographically sealed
5. **Recoverable**: System can restart from any journal state

## IBM i Inspiration

ShadowRPG-Q draws inspiration from IBM i concepts:
- Job queues and job descriptions
- Journaling and commitment control
- Record-level processing
- Operational control language
- Service programs and activation groups

**Important:** This is an independent implementation. It does not use IBM proprietary code, internal APIs, or confidential specifications.

## Integration

ShadowRPG-Q is designed to integrate with:
- QATAAUM compiler pipeline
- Quantum simulators and backends
- Formal verification layers (Liquid Haskell, Lean 4)
- Provider-neutral execution interfaces

## License

MIT License (see LICENSE file in repository root)

## Line Count

- `job.rs`: 260 lines
- `queue.rs`: 110 lines
- `journal.rs`: 210 lines
- `receipt.rs`: 170 lines
- `executor.rs`: 180 lines
- `lib.rs`: 100 lines
- **Total:** 1,030 substantive lines

## Status

✅ Job lifecycle management  
✅ Priority queue  
✅ Append-only journal  
✅ Cryptographic receipts  
✅ Execution engine  
✅ 15/15 tests passing  
⏳ IBM i FFI boundary (future)  
⏳ Native RPG integration (future)

---

**QATAAUM Project** | Clean-Room Quantum Runtime | 2026