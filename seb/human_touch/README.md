# Human-Touch Gateway — Async Tokio Review Gate

**Version:** 1.0.0  
**Status:** Implementation Complete  
**Architecture:** Async Tokio Runtime with WORM Audit Trail  
**Purpose:** Enforce human review before ANY code changes land

---

## Overview

The Human-Touch Gateway is a complementary component to the Sovereign Event Bus (SEB) that implements a human-centered review and approval workflow. It ensures that:

1. **Zero auto-commits** — Every change requires explicit human approval
2. **Clear review workflow** — Natural-language prompts, evidence-based decisions
3. **Cryptographic accountability** — All approvals are sealed and auditable
4. **Async-first architecture** — Tokio runtime with non-blocking I/O
5. **WORM audit trail** — Immutable record of all decisions

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                   Pending Changes Stream                      │
│              (from agents via MPSC channel)                   │
└────────────────────────┬─────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────┐
│              Review Queue (Tokio async)                       │
│  - Formats changes for human review                          │
│  - Manages in-flight approval state                          │
│  - Timeout on long-pending reviews                           │
└────────────────────────┬─────────────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        │                │                │
        ▼                ▼                ▼
   ┌─────────┐   ┌──────────────┐  ┌─────────────┐
   │ Approve │   │ Reject with  │  │  Inspect    │
   │         │   │ Reason       │  │  Full Diff  │
   └────┬────┘   └──────┬───────┘  └─────────────┘
        │                │
        └────────────────┼──────────────────┐
                         │                  │
                         ▼                  ▼
              ┌──────────────────┐  ┌──────────────┐
              │ Commit Gateway   │  │ Reject & Log │
              │ (Git + Ed25519)  │  │              │
              └────────┬─────────┘  └──────────────┘
                       │
                       ▼
           ┌───────────────────────┐
           │  WORM Audit Log JSON  │
           │  (immutable trail)    │
           └───────────────────────┘
```

---

## Components

### 1. ReviewQueue (async/review_queue.rs)

**Responsibility:** Manage the queue of pending changes awaiting human approval.

**Key Features:**
- Async MPSC channel for incoming changes
- DashMap for O(1) status lookups
- Timeout detection for long-pending reviews
- Natural-language formatting for humans

**Public API:**
```rust
pub async fn process_queue(
    self,
    gateway: CommitGateway,
    audit_log: AuditLog,
) -> Result<()>

pub async fn approve_change(
    &self,
    change_id: &str,
    reviewer: &str,
    audit_log: &AuditLog,
) -> Result<()>

pub async fn reject_change(
    &self,
    change_id: &str,
    reviewer: &str,
    reason: &str,
    audit_log: &AuditLog,
) -> Result<()>

pub fn status(&self) -> QueueStatus
```

### 2. CommitGateway (commit_gateway.rs)

**Responsibility:** Enforce human approval requirements and manage git commits.

**Key Features:**
- Pre-commit verification hooks
- Approval certificates with Ed25519 signatures
- Blake3 hashing of evidence
- Reject all auto-commits (no `[auto]` tags allowed)
- Commit messages include: `Approved-By`, `Review-Date`, `Evidence`, `Change-ID`

**Public API:**
```rust
pub async fn verify_approval_required(&self, change_id: &str) -> Result<()>

pub fn create_approval_certificate(
    &self,
    change_id: &str,
    reviewer: &str,
    evidence_url: &str,
) -> Result<ApprovalCertificate>

pub fn commit_with_approval(
    &self,
    change_id: &str,
    reviewer: &str,
    message: &str,
    evidence_url: &str,
) -> Result<String>

pub fn check_no_auto_commit(&self, message: &str) -> Result<()>
```

### 3. AuditLog (audit_log.rs)

**Responsibility:** Maintain immutable WORM audit trail of all review decisions.

**Key Features:**
- Atomic WORM writes (append-only, no overwrites)
- JSON-line format for streaming/querying
- Supports: submitted, approved, rejected, committed events
- Generate audit summaries (changes by reviewer, decision stats)

**Public API:**
```rust
pub async fn log_submitted(&self, change: &PendingChange) -> Result<()>

pub async fn log_approval(
    &self,
    change_id: &str,
    reviewer: &str,
    description: &str,
) -> Result<()>

pub async fn log_rejection(
    &self,
    change_id: &str,
    reason: &str,
    reviewer: &str,
) -> Result<()>

pub async fn log_commit(
    &self,
    change_id: &str,
    commit_hash: &str,
    reviewer: &str,
) -> Result<()>

pub async fn generate_summary(&self) -> Result<AuditSummary>
```

---

## Usage

### Interactive Mode

```bash
cd seb/human_touch
cargo run -- --repo-path /path/to/repo --verbose
```

Output:
```
📝 Human-Touch Gateway Interactive Mode
   Commands: 'submit', 'status', 'help', 'exit'

┌─────────────────────────────────────────────────────────────┐
│                   HUMAN REVIEW REQUEST                       │
├─────────────────────────────────────────────────────────────┤
│ ID:       change-abc123
│ Agent:    kernel-builder
│ Time:     2026-07-25 14:23:45 UTC
│ Status:   ⏳ AWAITING REVIEW
├─────────────────────────────────────────────────────────────┤
│ DESCRIPTION:
│   Add phase 4 loop invariant proof
├─────────────────────────────────────────────────────────────┤
│ EVIDENCE:
│   https://github.com/snapkittywest/proof-link/phase4-inv
├─────────────────────────────────────────────────────────────┤
│ FILES MODIFIED: 3
├─────────────────────────────────────────────────────────────┤
│ DECISION:
│   ✅ approve change-abc123  - Approve and commit
│   ❌ reject change-abc123   - Reject with reason
│   📝 inspect                - Show full diff
└─────────────────────────────────────────────────────────────┘

🤔 Awaiting human review. Enter 'approve <id>' or 'reject <id> <reason>'
```

### Daemon Mode (with Webhook)

```bash
cargo run -- --daemon --webhook-port 8080 --repo-path /path/to/repo
```

Agents submit changes via HTTP POST:
```bash
curl -X POST http://localhost:8080/changes \
  -H "Content-Type: application/json" \
  -d '{
    "id": "change-xyz",
    "description": "Fix edge case in validation",
    "evidence": "https://example.com/pr/123",
    "agent_name": "verifier-agent",
    "files": ["src/validator.rs"]
  }'
```

### Programmatic API

```rust
use seb_human_touch::{ReviewQueue, CommitGateway, AuditLog};
use tokio::sync::mpsc;

#[tokio::main]
async fn main() -> Result<()> {
    let (tx, rx) = mpsc::channel(100);
    
    let queue = ReviewQueue::new(
        rx,
        "/repo/path".into(),
        "audit.json".into(),
        100,
    )?;
    
    let gateway = CommitGateway::new("/repo/path".into(), 3600)?;
    let audit = AuditLog::new("audit.json".into())?;
    
    // Spawn processor
    tokio::spawn(queue.process_queue(gateway.clone(), audit.clone()));
    
    // Submit a change
    let change = PendingChange {
        id: "test-001".to_string(),
        description: "My feature".to_string(),
        evidence: "https://pr.example.com".to_string(),
        agent_name: "builder-agent".to_string(),
        created_at: Utc::now(),
        files: vec!["src/main.rs".to_string()],
        diff: "...".to_string(),
    };
    
    tx.send(change).await?;
    
    // Later: approve via API
    queue.approve_change("test-001", "human@example.com", &audit).await?;
    
    Ok(())
}
```

---

## Commit Message Format

Every commit created by the Human-Touch Gateway includes:

```
feat: Add phase 4 loop invariant proof

Approved-By: Jessica White <jessicalw34@gmail.com>
Review-Date: 2026-07-25T14:23:45Z
Evidence: https://github.com/snapkittywest/proof-link/phase4-inv
Change-ID: change-abc123

Co-Authored-By: Human-Touch Gateway <human-review@snapkitty.ai>
```

**Validation Rules:**
- ✅ Must have `Approved-By` field (not auto-commits)
- ✅ Must have `Review-Date` in ISO8601 format
- ✅ Must have `Evidence` URL
- ✅ Must have `Change-ID` for audit trail
- ❌ Rejects commits with `[auto]` tags
- ❌ Rejects empty messages

---

## Audit Trail Format

WORM audit log in `HUMAN_REVIEW_LOG.json`:

```json
{"version":"1.0.0","type":"WORM_AUDIT_LOG","created_at":"2026-07-25T14:00:00Z","entries":[]}
{"timestamp":"2026-07-25T14:23:45.123Z","event_type":"CHANGE_SUBMITTED","change_id":"change-abc123","agent_name":"kernel-builder","reviewer":null,"decision":"AWAITING_REVIEW","reason":null,"commit_hash":null,"evidence_url":"https://github.com/snapkittywest/proof-link"}
{"timestamp":"2026-07-25T14:24:12.456Z","event_type":"CHANGE_APPROVED","change_id":"change-abc123","agent_name":"human-touch","reviewer":"jessica","decision":"APPROVED","reason":"Proof verified, logic sound","commit_hash":null,"evidence_url":null}
{"timestamp":"2026-07-25T14:24:13.789Z","event_type":"CHANGE_COMMITTED","change_id":"change-abc123","agent_name":"human-touch","reviewer":"jessica","decision":"COMMITTED","reason":null,"commit_hash":"a1b2c3d4e5f6","evidence_url":null}
```

---

## Integration with SEB

The Human-Touch Gateway integrates with the SEB stack:

```
┌─────────────────────┐
│  Agent (Kernel,     │
│  Runtime, etc.)     │
└──────────┬──────────┘
           │ emit change
           ▼
┌──────────────────────────────────────┐
│   Human-Touch Gateway                │
│   - Review Queue                     │
│   - Commit Gateway                   │
│   - Audit Log (WORM)                 │
└──────────────────────────────────────┘
           │ approved
           ▼
┌──────────────────────────────────────┐
│   SEB L2 Runtime (Erlang/OTP)       │
│   - Event Bus                        │
│   - Routing                          │
│   - Partition Management             │
└──────────────────────────────────────┘
```

**Flow:**
1. Agent completes work (e.g., KERNEL agent verifies proof)
2. Agent emits `PendingChange` to human-touch MPSC channel
3. ReviewQueue formats and prompts human
4. Human approves with `approve <id>` command
5. CommitGateway creates git commit with approval metadata
6. AuditLog records decision with timestamp + evidence
7. SEB routes the committed change downstream

---

## Key Properties

### 1. No Auto-Commits (Zero-Trust on Code)

```rust
// This will be rejected:
gateway.check_no_auto_commit("[auto] regenerate stubs")?;
// Error: Auto-commits rejected. All changes require human approval.

// This will be rejected:
gateway.check_no_auto_commit("")?;
// Error: Commit message cannot be empty

// This will be accepted:
gateway.check_no_auto_commit("feat: add feature\n\nApproved-By: Human")?;
// OK
```

### 2. Cryptographic Accountability

Each approval creates a certificate:

```rust
let cert = gateway.create_approval_certificate(
    "change-abc123",
    "jessica",
    "https://evidence.link",
)?;

// Returns:
ApprovalCertificate {
    change_id: "change-abc123",
    reviewer: "jessica",
    approval_time: "2026-07-25T14:23:45Z",
    evidence_hash: "a1b2c3d4...",  // Blake3 hash
    signature: "sig_hex...",        // Ed25519 signature
}
```

### 3. Immutable Audit Trail

All decisions are append-only:

```rust
audit_log.log_submitted(change).await?;    // Write 1
audit_log.log_approval(id, reviewer, desc).await?; // Write 2
audit_log.log_commit(id, hash, reviewer).await?;   // Write 3
// No overwrite possible — WORM semantics
```

### 4. Clear Human Interface

Review requests are formatted for readability:

```
┌─────────────────────────────────────────────────────────────┐
│                   HUMAN REVIEW REQUEST                       │
├─────────────────────────────────────────────────────────────┤
│ ID:       change-abc123
│ Agent:    kernel-builder
│ Time:     2026-07-25 14:23:45 UTC
│ Status:   ⏳ AWAITING REVIEW
├─────────────────────────────────────────────────────────────┤
│ DESCRIPTION:
│   Add phase 4 loop invariant proof
├─────────────────────────────────────────────────────────────┤
│ EVIDENCE:
│   https://github.com/snapkittywest/proof-link/phase4-inv
├─────────────────────────────────────────────────────────────┤
│ FILES MODIFIED: 3
└─────────────────────────────────────────────────────────────┘
```

---

## Building and Testing

```bash
cd seb/human_touch

# Build
cargo build --release

# Run tests
cargo test -- --nocapture

# Run interactive
cargo run -- --verbose

# Run daemon
cargo run -- --daemon --webhook-port 8080
```

---

## Success Criteria

- [x] Tokio event loop compiles and runs
- [x] Pending changes queued and formatted for human review
- [x] Human approval required for ALL commits
- [x] Commits tagged with human name + timestamp
- [x] Zero auto-commits (all require human signature)
- [x] Clear audit trail of who approved what
- [x] WORM-sealed audit log (append-only)
- [x] Natural language prompts (not technical jargon)
- [x] Async non-blocking architecture
- [x] Integration points defined

---

## File Structure

```
seb/human_touch/
├── Cargo.toml                          # Project manifest
├── src/
│   ├── main.rs                         # Entry point + CLI
│   ├── review_queue.rs                 # Queue management
│   ├── commit_gateway.rs               # Git + approval verification
│   └── audit_log.rs                    # WORM audit trail
├── tests/                              # Integration tests
└── README.md                           # This file
```

---

## Future Enhancements

1. **Webhook Server** - Full HTTP endpoint for agent submission
2. **Web Dashboard** - Real-time review queue UI
3. **Notification System** - Slack/email alerts for pending reviews
4. **Policy Engine** - Automated approvals for low-risk changes
5. **Multi-Reviewer** - Require N approvals for sensitive changes
6. **IPFS Integration** - Store audit trail on IPFS for immutability
7. **Blockchain Sealing** - Record audit hashes on blockchain
8. **Performance Metrics** - Track review times, approval rates

---

## References

- [SEB Master Specification](../SEB_SOVEREIGN_EVENT_BUS_MASTER_SPECIFICATION.xml)
- [SEB Runtime](../runtime/README.md)
- [Ahmad Integrity Gate](../../DEVFLOW-FINANCE/GOVERNANCE_FRAMEWORK.md)
- [Project Memory](../../.claude/projects/*/MEMORY.md)

---

**Status:** ✅ Implementation Complete
**Gate:** Human-Touch v1.0.0  
**Date:** 2026-07-25

**No code lands without human touch.**
