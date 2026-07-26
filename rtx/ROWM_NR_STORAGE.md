# ROWM-NR Storage with Embedded WORM Receipts

## Status

This document is the storage and scheduler contract for the Read-Once
Write-Many Non-Recursive (ROWM-NR) system. WORM is incorporated as ROWM-NR's
internal immutable receipt mechanism. It is not the parent architecture and it
does not own ROWM-NR state.

It is a specification, not a proof artifact. The repository does not yet
contain the hash implementation, durable WORM append implementation, ROWM
runtime, recovery checker, or Layer 21 scheduler bridge required to claim the
proof obligations below as discharged.

## Authority and Layering

```
ROWM-NR storage authority
        |
        +-- active root and transaction state
        +-- immutable record store
        +-- capability and record-access index
        +-- bounded traversal engine
        +-- evolution and access heads
        |
        `-- embedded WORM receipt component
                |
                +-- append-once receipt pages
                +-- receipt hash chain
                `-- immutable replay evidence
```

ROWM-NR is the only public storage authority. It owns record creation,
capability validation, monotonic consumption, bounded traversal, committed
roots, and disclosure ordering. Its internal WORM component supplies durable
append-only evidence for those ROWM-NR transitions. ROWM-NR never edits or
replaces an existing WORM receipt.

Call direction is fixed:

```
scheduler -> ROWM-NR -> internal WORM append
```

The scheduler and Event Bus do not invoke WORM directly.

## Representation

`Hash256` is exactly 32 bytes. All hashed objects use a canonical encoding:

- fixed-width unsigned integers are little-endian;
- enums are one unsigned byte;
- variable byte strings are prefixed by an unsigned 64-bit byte length;
- fields occur in the order specified below;
- each object begins with a distinct fixed domain tag.

The hash function `H` is an injected cryptographic primitive with a fixed
algorithm identifier in the boot manifest. Safety arguments involving hash
identity are conditional on that primitive and its implementation.

### Immutable Record Body

```
RecordBody = {
    id: Hash256,
    payload_length: u64,
    payload: bytes[payload_length],
    parent_root: Hash256,
    epoch: u64,
    write_proof: Hash256
}
```

`RecordBody` is immutable once staged. Its identifier is:

```
id = H("SOV-ROWM-RECORD-v1" || canonical_record_fields)
```

Read state is deliberately not stored inside the immutable body. It belongs to
the ROWM index:

```
RecordAccess = {
    record_id: Hash256,
    phase: UNREAD | CLAIMED | CONSUMED,
    claim_id: Hash256,
    consumption_receipt: Hash256
}
```

This separation resolves the conflict between immutable record storage and a
mutable `UNREAD -> CONSUMED` transition.

### Capability

```
Capability = {
    id: Hash256,
    record_id: Hash256,
    owner: Hash256,
    nonce: u64,
    phase: AVAILABLE | CLAIMED | CONSUMED
}
```

`CLAIMED` is an internal recovery state. Externally, both `CLAIMED` and
`CONSUMED` are unavailable. Legal transitions are:

```
AVAILABLE -> CLAIMED -> CONSUMED
```

There is no transition back to `AVAILABLE`.

### WORM Receipt

```
WormReceipt = {
    version: u32,
    event_type: ROWM_WRITE | ROWM_CONSUME,
    transaction_id: Hash256,
    payload_hash: Hash256,
    previous_worm_hash: Hash256,
    logical_timestamp: u64,
    receipt_hash: Hash256
}
```

For consumption, the payload hash commits to:

```
ReadReceipt = {
    record_id: Hash256,
    capability_id: Hash256,
    consumer: Hash256,
    logical_timestamp: u64,
    previous_access_hash: Hash256
}
```

The physical WORM log carries both write and consumption receipts in one
append-only timeline. Evolution and access retain independent logical heads.

## Deterministic Hash Chains

Evolution:

```
root_next =
    H("SOV-ROWM-EVOLUTION-v1"
      || root_previous
      || mutation_hash
      || proof_hash
      || logical_timestamp)
```

Access:

```
access_next =
    H("SOV-ROWM-ACCESS-v1"
      || access_previous
      || consumer
      || record_id
      || capability_id
      || logical_timestamp)
```

`logical_timestamp` is a monotonic counter allocated by the serialized storage
transition. Wall-clock time may be recorded as a signed observation, but it is
then an explicit input. Reading an ambient clock inside the transition would
violate deterministic-output claims.

## Append-Once Primitive

Exactly-once receipts require a serialization point. The WORM component inside
ROWM-NR must provide:

```
worm_append_once(transaction_id, canonical_receipt)
    -> existing_or_new_receipt_hash | error
```

Rules:

1. A new transaction ID appends exactly one durable entry.
2. Repeating the same transaction ID and bytes returns the existing entry.
3. Reusing the transaction ID with different bytes fails.
4. Success is returned only after the entry and receipt-chain head are durable.
5. ROWM-NR can reconstruct the transaction index from its embedded receipt
   pages during recovery.

Without this primitive, a crash after append but before active-state commit can
produce duplicate receipts on retry, so PO1 cannot be established.

## Write State Machine

```
READY
  -> VALIDATE
  -> STAGE_RECORD
  -> COMPUTE_ROOT
  -> APPEND_WORM
  -> WORM_DURABLE
  -> PUBLISH_ROOT
  -> DONE
```

The candidate record and root are not visible before `WORM_DURABLE`.

The transaction ID is derived from the prior evolution root, mutation hash,
proof hash, and logical timestamp. Recovery behavior is deterministic:

- no WORM receipt: resume `APPEND_WORM`;
- matching durable receipt: resume `PUBLISH_ROOT`;
- conflicting receipt: enter `FAILED_INTEGRITY`;
- WORM capacity exhaustion: remain pending and disclose no new root.

## Read-Once State Machine

```
READY
  -> LOOKUP
  -> CHECK_CAPABILITY
  -> CLAIM
  -> APPEND_WORM
  -> WORM_DURABLE
  -> COMMIT_CONSUMED
  -> DISCLOSE
  -> DONE
```

`CLAIM` is the concurrency serialization point. It atomically changes both the
record access entry and the selected capability from `AVAILABLE/UNREAD` to
`CLAIMED`. Competing reads fail before payload access.

The implementation may read internal record bytes while calculating hashes,
but it must not copy them into caller-controlled memory before:

1. the consumption receipt is durable;
2. the record and capability are committed `CONSUMED`;
3. the durable receipt hash is linked from that committed state.

Recovery behavior:

- claimed with no receipt: resume the same append-once transaction;
- receipt durable but not committed: commit `CONSUMED`;
- committed: never disclose again, including after restart.

No recovery transition changes `CLAIMED` or `CONSUMED` to `AVAILABLE`.

## Bounded Traversal

Traversal uses fixed storage:

```
Traversal = {
    entries[Bq]: (record_id, depth),
    visited[Bv]: record_id,
    head: u32,
    tail: u32,
    visited_count: u32,
    steps: u64,
    max_depth: u32
}
```

Permanent invariants:

```
head <= tail
tail <= Bq
visited_count <= Bv
steps <= Bq * (max_depth + 1)
```

The state machine is:

```
INIT -> LOAD -> CHECK -> VISIT -> ENQUEUE -> PROCESS -> DONE
```

An already-visited record is not enqueued again. Queue or visited-set
exhaustion returns an explicit bound error; it never falls back to recursion or
an unbounded walk.

## LLI Extension

The previously stated LLI grammar cannot express the supplied ROWM fragment:
`:=`, `if`, hashing, durable append, queue operations, and disclosure are not
members of that grammar. The minimum finite extension is:

```
Phase    ::= available | claimed | consumed
Result   ::= ok Value | error Code
StateOp  ::= claim | append_once | commit | disclose
QueueOp  ::= enqueue | dequeue | visited
HashOp   ::= hash Domain Bytes
Step     ::= State "=" StateOp "(" Args ")"
           | State "=" QueueOp "(" Args ")"
           | Value "=" HashOp
Transition ::= Precondition "=>" Step+
```

Each operator has a fixed arity, fixed-width encoding, bounded input size, and
a deterministic transition table. `append_once` is successful only on durable
WORM acknowledgement. `disclose` requires a committed receipt hash.

The core transitions are:

```
write(payload, proof, state)
  => staged    = stage_immutable(payload, proof)
  => next_root = hash(evolution, state.root, staged.id, proof, state.clock)
  => receipt   = append_once(txid, write_receipt(staged, next_root))
  => state     = publish_root(state, next_root, receipt)

read_once(capability, record, state)
  => claimed      = claim(state, capability, record)
  => next_access  = hash(access, state.access, capability, record, state.clock)
  => receipt      = append_once(txid, consume_receipt(claimed, next_access))
  => state        = commit_consumed(state, claimed, receipt)
  => payload      = disclose(state, record, receipt)
```

Until this grammar extension, parser, lowering rules, and verifier exist as
code, ROWM-NR is not self-hosted merely because pseudocode uses LLI notation.

## ASP Forbidden States

The constraints must be time-indexed. A timeless rule forbidding both
`AVAILABLE` and `CONSUMED` would incorrectly reject the valid history that
contains the transition.

```prolog
phase(available; claimed; consumed).

% Monotonic capability and record state.
:- next(T,T1), cap_phase(C,T,consumed), cap_phase(C,T1,P), P != consumed.
:- next(T,T1), cap_phase(C,T,claimed), cap_phase(C,T1,available).
:- next(T,T1), record_phase(R,T,consumed), record_phase(R,T1,P), P != consumed.
:- next(T,T1), record_phase(R,T,claimed), record_phase(R,T1,unread).

% A record and capability have at most one committed consumption.
:- read_committed(R,Tx1), read_committed(R,Tx2), Tx1 != Tx2.
:- cap_committed(C,Tx1), cap_committed(C,Tx2), Tx1 != Tx2.

% A completed transaction has exactly one WORM receipt.
receipt_count(Tx,N) :-
    transaction(Tx),
    N = #count { Pos : worm_receipt(Tx,Pos) }.
:- completed(Tx), receipt_count(Tx,N), N != 1.

% Disclosure is strictly after durable receipt and consumption commit.
durable_before(Tx,T)   :- receipt_durable(Tx,Tr), step(T), Tr < T.
committed_before(Tx,T) :- consumed_at(Tx,Tc), step(T), Tc < T.
:- disclosed(Tx,T), not durable_before(Tx,T).
:- disclosed(Tx,T), not committed_before(Tx,T).

% WORM positions never change.
:- next(T,T1), worm_at(Pos,T,H1), worm_at(Pos,T1,H2), H1 != H2.

% Root publication is strictly after its write receipt is durable.
:- root_published(Tx,T), not durable_before(Tx,T).

% Bounded queue and traversal.
:- queue_state(_,Head,Tail,_,_), Head > Tail.
:- queue_state(_,_,Tail,_,Capacity), Tail > Capacity.
:- traversal_steps(_,Steps,Bound), Steps > Bound.

% Functional output for identical state and explicit inputs.
:- transition_output(S,I,O1), transition_output(S,I,O2), O1 != O2.
```

## C ABI

```c
int sov_rowm_write(
    sov_rowm_context_t* context,
    const void* payload,
    size_t payload_bytes,
    const sov_hash256_t* proof,
    sov_hash256_t* root_out);

int sov_rowm_read_once(
    sov_rowm_context_t* context,
    const sov_rowm_capability_t* capability,
    const sov_hash256_t* record_id,
    void* payload_out,
    size_t payload_capacity,
    size_t* payload_bytes_out);

int sov_rowm_verify(
    const sov_rowm_context_t* context,
    const sov_hash256_t* root);

int sov_rowm_get_receipts(
    const sov_rowm_context_t* context,
    uint64_t cursor,
    sov_worm_receipt_view_t* receipts_out,
    size_t receipt_capacity,
    size_t* receipt_count_out,
    uint64_t* next_cursor_out);

int sov_rowm_traverse(
    const sov_rowm_context_t* context,
    const sov_hash256_t* root,
    uint32_t max_depth,
    sov_hash256_t* record_ids_out,
    size_t record_capacity,
    size_t* record_count_out);
```

`read_once` copies into caller memory only in `DISCLOSE`. A size query that
would expose payload bytes is not permitted; public length metadata may be
queried separately.

## Verification Obligations

1. Every committed ROWM write maps to exactly one durable WORM receipt.
2. Every successful read has one durable consumption receipt ordered before
   disclosure.
3. A record and capability cannot commit consumption twice.
4. No existing WORM position changes across a state transition.
5. Traversal terminates within its declared queue, visited-set, depth, and step
   bounds.
6. Identical state and explicit inputs produce identical roots and receipts.
7. Crash recovery converges to the same committed state as uninterrupted
   execution.
8. No new root or payload is visible from a pending or failed transaction.

Required evidence includes executable state-machine tests with crash injection
at every transition, concurrent-read tests, WORM-full tests, replay tests, hash
known-answer tests, and a machine-checkable refinement proof.

## Scheduler CHECKPOINT Integration

Layer 21 invokes ROWM-NR only after a generated token is fully committed. It
does not invoke the WORM component directly. At each positive multiple of 64
committed generated tokens:

```
freeze sequence transition
copy and synchronize the referenced KV bytes
canonicalize scheduler, RNG, token, block-table, and KV snapshot
ROWM-NR write(snapshot, checkpoint_proof)
ROWM-NR appends its internal WORM receipt
ROWM-NR publishes the new evolution root
commit checkpoint state
publish checkpoint event to the Event Bus
resume generation
```

The ROWM-NR immutable record store contains the complete checkpoint bytes. Its
embedded WORM component stores the hash-chained transition receipt. A GPU
address is never a checkpoint payload.

If ROWM-NR write, internal receipt durability, or root publication fails, the
scheduler remains in `CHECKPOINT`, publishes no success event, and does not
generate the next token. ROWM-NR recovery uses its transaction table and
embedded receipt pages to complete any matching pending transition, then
resumes from the same logical checkpoint.

The Event Bus is downstream of the committed ROWM-NR root. Its event contains
the sequence ID, token count, checkpoint record ID, new root, internal receipt
hash, and transition digest. Subscribers cannot mutate scheduler, ROWM-NR, or
its embedded WORM component.
