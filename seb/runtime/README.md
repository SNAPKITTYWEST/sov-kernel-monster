# SEB L2 Runtime - Erlang/OTP Fabric

**Version:** 1.0.0  
**Status:** Implementation Complete (G2 → G3 Gate)  
**Date:** 2026-07-25  

## Overview

The L2 Erlang/OTP runtime implements the event coordination fabric for the Sovereign Event Bus (SEB). It bridges the Ada kernel (L0) with execution adapters, providing:

- **Dynamic agent lifecycle management** (4-state FSM)
- **Deterministic event routing** (1024 partitions via phash2)
- **Policy-driven authorization** (Datalog + Souffle)
- **Cryptographic event sealing** (Blake3 + Ed25519)
- **Cluster coordination** (Erlang distribution)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  seb_sup (Root Supervisor)                              │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────────────────┐  ┌──────────────────┐            │
│  │ seb_kernel_nif   │  │seb_datalog_bridge│            │
│  │ (Ada Kernel L0)  │  │ (Policy Engine)  │            │
│  └──────────────────┘  └──────────────────┘            │
│                                                         │
│  ┌──────────────────┐  ┌──────────────────┐            │
│  │seb_partition_mgr │  │seb_agent_sup     │            │
│  │ (1024 parts)     │  │ (Dynamic agents) │            │
│  └──────────────────┘  └──────────────────┘            │
│                                                         │
│                  [Agent FSM Instances]                  │
│        active → draining → checkpointed → stopped       │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## Components

### 1. **seb_sup.erl** - Root Supervisor
- Starts all core workers: kernel_nif, policy_engine, partition_manager, agent_sup
- One-for-all restart strategy (if any critical component fails, entire SEB restarts)
- Enforces L0 invariants at startup

### 2. **seb_agent_sup.erl** - Agent Lifecycle Supervisor
- Supervises dynamic agents using one-for-one strategy
- Spawns agents via `spawn_agent/2`
- Terminates agents with drain sequence via `terminate_agent/1`
- Tracks active agents via `get_agent_pids/0`

### 3. **seb_agent_fsm.erl** - 4-State Agent FSM
Per XML L2 spec, implements corrected state machine:

```
active ──shutdown()─→ draining ──commit_offset()─→ checkpointed ──────→ stopped
  │                      │              │              │
  │ queue_event()        │ (drain)      │ (offset)     └─→ (final cleanup)
  └──────────────────────┘              │
                                         └─→ (30s timeout)
```

**State Transitions:**
- **active**: Process events normally, accept queue_event/2, accept commit_offset/2
- **draining**: Reject new events, process remaining queue items, await offset commit (30s timeout)
- **checkpointed**: Offset committed to L0 kernel, ready for cleanup
- **stopped**: Final state, no further operations

**Key Invariants:**
- Drain timeout: 30 seconds (per XML)
- Queue monotonicity: offset > prior_offset
- Offset commit via seb_kernel_nif (L0 bridge)

### 4. **seb_partition_mgr.erl** - Deterministic Partition Assignment
- **1024 partitions** (fixed)
- **Deterministic routing** via `erlang:phash2({agent_id, competency}) rem 1024`
- **Same input → Same partition** (reproducible across runs)
- **Competency-based** (from Datalog policy engine)
- **Load tracking** (monitors partition load, triggers rebalancing at threshold)

### 5. **seb_datalog_bridge.erl** - Policy Engine Bridge
- **Port driver** to compiled Souffle policy engine
- **Async authorization** via `authorize/2`
- **Competency queries** via `get_competencies/1`
- **Stratified Datalog evaluation**

Policy decisions:
- Event satisfies governance rules
- Authority constraints verified
- Risk thresholds enforced
- Competency routing determined

### 6. **seb_kernel_nif.erl** - Ada Kernel Interface
- **NIF bridge** to libseb_kernel.a (Ada kernel)
- Implements:
  - `append_event/4` - Append with Ed25519 verification + hash chain validation
  - `commit_offset/1` - Commit offset with monotonicity check
  - `verify_chain/0` - Verify entire chain from tip to genesis
  - `get_tip_hash/0` - Return current tip hash

## L0 Invariants Enforced (from Ada Kernel)

1. **Plasma Gate**: Ed25519 signature valid on event hash
2. **Hash Chain**: Prev_Hash == current state tip hash
3. **Offset Monotonic**: Event offset > prior offset
4. **Payload Hash**: blake3(header || payload) matches footer.event_hash
5. **Segment Chain**: Prev_Seg_Hash links to prior segment

## Building

```bash
cd seb/runtime

# Build
make build

# Run tests
make test

# Run static analysis
make dialyzer

# Build release
make release

# Start dev console
make console
```

## Success Criteria (Ahmad Integrity Gate)

All must pass for production readiness:

- [ ] `rebar3 release` builds: `seb_release.tar.gz`
- [ ] `dialyzer` reports: zero type errors
- [ ] Cluster forms 3 nodes, survives partition heal
- [ ] Agent shutdown drains in < 30s
- [ ] NIF calls to kernel work (test vectors)
- [ ] Partition assignment deterministic (same seed → same result)
- [ ] No TODOs, FIXMEs, or undefined stubs
- [ ] Signed handoff manifest

## Testing

### Unit Tests
```bash
make test
```

Tests cover:
- Agent FSM state transitions
- Drain timeout (30s)
- Offset commitment via NIF
- Queue operations
- Partition determinism
- Policy engine queries

### Integration Tests
```bash
make test
```

Tests cover:
- Cluster formation (3 nodes)
- Multi-agent spawn + drain
- Partition assignment across agents
- Policy engine authorization
- Failure recovery

### Performance Benchmarks (from XML spec)
- Event latency: < 10ms (p99)
- Throughput: > 10,000 events/sec
- Seal latency: < 5ms (p99)
- Memory per event: < 1KB

## Configuration

### sys.config
Kernel, datalog, partition, agent, WORM, SENTINEL, network settings.

**Key Parameters:**
- `partition_count`: 1024 (fixed)
- `drain_timeout_ms`: 30000 (per XML)
- `max_queue_size`: 10000
- `hash_algorithm`: blake3
- `signature_algorithm`: ed25519

### vm.args
Erlang VM tuning:
- SMP: enabled
- Kernel polling: enabled
- Memory: 256MB heap
- Processes: 262K max

## Dependencies

```toml
libsodium = "1.0.18"   # Crypto primitives
blake3 = "1.0.0"       # Hash function
souffle = "2.3.0"      # Datalog engine
telemetry = "~> 1.0"   # Observability
```

## G2 Gate (Kernel) → G3 Gate (Runtime)

### G2 Completion Evidence
- Ada kernel (seb_kernel.adb/.ads) complete with SPARK Level 4 verification
- L0 invariants encoded as preconditions/postconditions
- libseb_kernel.a compiled and tested
- Test vectors pass (append, commit, verify operations)

### G3 Deliverables (THIS PHASE)
- [x] seb_sup.erl - Root supervision tree
- [x] seb_agent_sup.erl - Agent lifecycle supervisor
- [x] seb_agent_fsm.erl - 4-state corrected FSM
- [x] seb_partition_mgr.erl - Deterministic routing (1024 partitions)
- [x] seb_datalog_bridge.erl - Datalog policy engine bridge
- [x] seb_kernel_nif.erl - Ada kernel NIF bridge
- [x] seb_app.erl - Application module
- [x] rebar.config - Build configuration
- [x] sys.config - Runtime configuration
- [x] vm.args - Erlang VM tuning
- [x] Comprehensive unit + integration tests
- [x] Makefile with all targets
- [x] This README

### Next: G4 Gate (Adapters)
- Implement seb/adapters/ (HolyC, Shell, Browser, Chain adapters)
- WORM sealing flow
- E2E tests across kernel → runtime → adapters

## Diagnostics

### Check cluster status
```erlang
nodes().
```

### Check agent status
```erlang
seb_agent_sup:get_agent_pids().
```

### Query partition assignment
```erlang
seb_partition_mgr:assign_partition(<<"agent_1">>, compute).
```

### Verify chain integrity
```erlang
seb_kernel_nif:verify_chain().
```

## References

- **Master Spec**: SEB_SOVEREIGN_EVENT_BUS_MASTER_SPECIFICATION.xml (source of truth)
- **L0 Kernel**: seb/kernel/src/seb_kernel.ads (Ada SPARK)
- **Datalog Policy**: seb/contracts/lean4.template (formal properties)
- **MIRROR KITTY Governance**: Phase Mirror governance model (Four Agreements)

## License

Apache 2.0

---

**Status:** ✅ **READY FOR G3 GATE REVIEW**

All L2 components implemented per XML specification. Awaiting Ahmad Integrity Gate approval.
