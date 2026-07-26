# Production Hardening

This document defines the work and evidence required before Sovereign Event Bus
(SEB) can be operated as a production event system. It is a release-gate
specification, not a statement that the current repository meets these
requirements.

## Status contract

Use the following terms consistently:

| Term | Meaning |
| --- | --- |
| Source present | An interface or implementation exists in the repository |
| Builds | The declared target compiles from a clean checkout in CI |
| Tested | Repeatable automated tests execute and assert behavior |
| Integrated | Two or more components pass a versioned contract test |
| Hardened | Threat controls, recovery, observability, and operational limits are demonstrated |
| Production ready | Every required gate in this document is closed with reviewable evidence |

Documentation, generated reports, proof certificates, hashes, and signatures
must use these terms according to evidence. A command returning exit code zero
is not sufficient when the command skipped a tool, discovered no tests, or ran
a simulated backend.

## Definition of production ready

SEB is production ready only when all of the following are true:

1. One canonical envelope encoding and signature domain is implemented and
   validated across every supported language.
2. Authentication, authorization, replay defense, key lifecycle, and policy
   failure behavior are fail closed.
3. Accepted events, offsets, decisions, and receipts survive the documented
   crash and disaster scenarios.
4. The runtime and native boundary compile, load, negotiate compatible
   versions, and fail without corrupting the host VM.
5. Human approval is authenticated, authorized, durable, idempotent, and linked
   to exactly one eligible event transition.
6. Formal claims build in CI without placeholders and are connected to the
   implementation through explicit refinement or conformance artifacts.
7. A clean source checkout passes the full test matrix, security analysis,
   cross-language vectors, and release build without silently skipped work.
8. Operators can observe saturation, lag, failures, and evidence health; they
   have tested backup, restore, rollback, and incident procedures.
9. Capacity and latency limits are measured on declared hardware and workloads.
10. Release artifacts are reproducible enough to audit, have an SBOM and
    provenance, and are signed by a controlled release identity.

Any unmet item keeps the release in reference, experimental, or preview status.

## Assurance principles

### One event, one canonical representation

Every implementation must consume and produce the same byte-level envelope.
Language-native structs are views over that representation, not independent
definitions. The specification must define:

- field order, field widths, endianness, and alignment;
- string encoding and Unicode normalization;
- timestamp precision, epoch, and allowed clock skew;
- integer overflow behavior;
- absent, empty, and null semantics;
- map ordering and duplicate-key handling;
- maximum envelope, field, and evidence sizes;
- canonical serialization and signature domain separation;
- version negotiation and unknown-field behavior; and
- hash-chain input, receipt input, and stable test vectors.

The present Ada, test-vector, Rust, TypeScript, Python, RPG, and PL/I shapes are
not yet one interoperable wire format.

### Claims follow evidence

The following words require named evidence:

| Claim | Minimum evidence |
| --- | --- |
| Deterministic | Repeat tests across clean processes, hosts, time zones, and supported architectures produce identical decision artifacts |
| Fail closed | Fault injection shows every unavailable dependency denies or queues work according to policy |
| Cryptographically sealed | A reviewed algorithm implementation, controlled keys, canonical input, test vectors, negative tests, and verification at every trust boundary |
| Durable | Crash, power-loss, partial-write, corruption, restore, and retention tests against the selected storage system |
| WORM | Storage-level retention and deletion controls, administrative separation, and provider or device evidence |
| Formally verified | CI-checked theorem set without admitted terms, plus a documented connection between model and deployed implementation |
| Production ready | Every required gate in this document closed |

### No silent success

Build, test, audit, proof, policy, and release commands must fail when a required
tool is absent, a test suite discovers zero tests, a component is skipped, an
artifact is stale, or a required report cannot be produced. Optional work must
be explicitly labeled optional in both console and machine-readable output.

## System and trust boundaries

| Boundary | Trusted input | Untrusted or fallible input | Required control |
| --- | --- | --- | --- |
| Producer to ingress | Registered identity and negotiated schema version | Envelope bytes, timestamps, evidence references | Authentication, size limits, canonical parse, replay check, rate limit |
| Ingress to policy | Parsed immutable event and identity context | Policy bundle, external facts, policy service availability | Signed policy bundle, version pin, timeout, deny-on-error |
| Policy to router | Authorized decision tied to event digest | Route name, adapter metadata | Decision signature, exact event binding, route allowlist |
| Runtime to native kernel | Versioned NIF ABI and bounded buffers | Native code, allocation, file and crypto errors | ABI handshake, input bounds, dirty schedulers or isolation, crash containment |
| Router to adapter | Typed request and capability grant | Remote platform behavior and partial completion | Deadlines, idempotency key, least privilege, reconciliation |
| Review service | Eligible event and policy-required review state | Reviewer browser/session, duplicate actions, stale approval | Strong authentication, RBAC, expiry, single-use decision token |
| Evidence writer | Final transition and prior committed tip | Storage failures, partial writes, administrative action | Atomic append, integrity tree, retention controls, restore verification |
| Build to release | Reviewed source and locked dependencies | Compromised runner, registry, toolchain, secret | Hermetic build, provenance, SBOM, signing, separated approval |

Native code, external policy engines, IBM platform calls, human interfaces,
artifact registries, and evidence storage are separate trust boundaries even
when deployed on the same host.

## Threat model

### Assets

- event intent, authority, and payload confidentiality;
- ordering, offsets, partition ownership, and continuation state;
- policy bundles and authorization decisions;
- signing, verification, and release keys;
- human-review identity and decision records;
- evidence-chain integrity and retention;
- deployment packages, manifests, and provenance; and
- operator credentials, audit access, and recovery material.

### Adversary capabilities

Plan for an adversary who can:

- submit malformed, oversized, duplicated, delayed, or replayed envelopes;
- control payload bytes, identifiers, timestamps, and selected metadata;
- observe or interrupt network traffic;
- crash a process between any two storage operations;
- compromise one service account or adapter credential;
- race approval, cancellation, retry, and timeout operations;
- introduce a malicious dependency or build artifact;
- modify mutable logs or repository metadata; and
- exploit parser differences across language and legacy-platform boundaries.

### Explicit assumptions

Production design must name and test its assumptions about:

- host and hypervisor integrity;
- trusted time and maximum skew;
- entropy availability;
- hardware security modules or managed key services;
- storage consistency and retention guarantees;
- network identity and service discovery;
- administrator separation of duties; and
- supported operating systems, CPU architectures, and legacy platforms.

An assumption is not a control. Each assumption needs an owner, validation
method, and documented behavior when it is violated.

## Required readiness gates

### Gate 1: Canonical protocol

Required controls:

- Publish a versioned binary or canonical text specification.
- Generate language bindings from one machine-readable schema where practical.
- Define strict parsing and rejection behavior.
- Use a dedicated signature context string and versioned hash preimage.
- Define forward/backward compatibility and deprecation windows.
- Reject ambiguous, duplicate, non-canonical, and out-of-range input.

Exit evidence:

- A checked-in conformance corpus with positive and negative vectors.
- Round-trip and byte-equality tests for every supported implementation.
- Property tests for parser/serializer invariants.
- Differential fuzzing across at least two independent implementations.
- A compatibility table for every released schema and runtime version.

### Gate 2: Identity, keys, and cryptography

Required controls:

- Replace placeholder hashes and signatures with reviewed library
  implementations.
- Establish producer, service, reviewer, evidence, and release identities.
- Keep private keys outside source and ordinary configuration files.
- Define issuance, activation, rotation, revocation, expiry, and compromise
  response.
- Bind every signature to protocol version, environment, tenant, event digest,
  transition, and intended verifier.
- Use constant-time verification paths where secret-dependent behavior exists.
- Reject zero, malformed, expired, revoked, unknown, or wrong-purpose keys.

Exit evidence:

- Published key hierarchy and data-flow review.
- Known-answer, negative, mutation, and cross-language cryptographic tests.
- HSM/KMS access policy with administrative separation.
- Rotation and emergency-revocation exercise.
- Independent security review of algorithms, input construction, and key use.

### Gate 3: Replay, idempotency, and ordering

Required controls:

- Assign an immutable event identifier and producer-scoped idempotency key.
- Persist replay decisions for at least the maximum accepted replay window.
- Define ordering per partition and behavior across partitions.
- Make adapter dispatch and commit retry-safe.
- Distinguish duplicate submission, duplicate delivery, and duplicate effect.
- Detect conflicting reuse of the same idempotency key.

Exit evidence:

- Concurrent duplicate and retry tests.
- Restart tests around every transition.
- Delayed-message and clock-skew tests.
- Reconciliation evidence proving one externally visible effect per committed
  idempotency key where the adapter supports it.

### Gate 4: Durable append and recovery

Required controls:

- Select a storage engine with documented atomicity and durability semantics.
- Connect the kernel append path to the WAL or replace it with a defined durable
  store.
- Record event, decision, dispatch intent, effect receipt, and committed offset
  with an explicit transaction model.
- Protect segment metadata and chain tips against torn or reordered writes.
- Define corruption detection, quarantine, repair, and read-only recovery.
- Separate immutable evidence retention from ordinary application logs.

Exit evidence:

- Kill-at-every-write-point tests.
- Power-loss and partial-sector simulation where supported.
- Backup and point-in-time restore exercise.
- Chain verification against corrupted, truncated, reordered, and duplicated
  records.
- Measured recovery point and recovery time under the declared deployment.
- WORM retention evidence from the actual storage control plane if WORM is
  claimed.

### Gate 5: Runtime and native isolation

Required controls:

- Reconcile the Erlang facade and C NIF names, arities, handles, and return
  contracts.
- Load the NIF through a versioned initialization path.
- Bound all native allocations and copied buffers.
- Move blocking file, crypto, and platform operations off normal schedulers.
- Convert native failures to stable Erlang error values without leaking
  resources.
- Decide whether the kernel belongs in a NIF, port, or separate supervised
  service based on crash impact.
- Make shutdown, drain, partition transfer, and restart state machines explicit.

Exit evidence:

- Clean C/Ada build with warnings treated as errors.
- ABI conformance tests and version-mismatch tests.
- Erlang property tests and EUnit tests that are confirmed to execute.
- Native fuzzing under sanitizers and leak detection.
- Host-VM crash-containment and scheduler-latency tests.
- Rolling upgrade and mixed-version compatibility tests.

### Gate 6: Policy enforcement

Required controls:

- Package policy as an immutable, signed, versioned artifact.
- Record the exact policy and fact-set digest used for each decision.
- Apply strict deadlines and deny or durably quarantine on timeout.
- Separate policy administration from event submission.
- Validate external facts for freshness and provenance.
- Make authorization decisions deterministic or record every nondeterministic
  input needed to replay them.

Exit evidence:

- Policy decision vectors, mutation tests, and deny-on-error tests.
- Policy service loss, slow response, malformed output, and stale-fact tests.
- Rollback exercise for a faulty policy bundle.
- Audit showing who approved and deployed each policy version.

### Gate 7: Human review

Required controls:

- Persist review requests and state transitions transactionally.
- Authenticate reviewers with phishing-resistant controls appropriate to risk.
- Authorize by tenant, action, amount, environment, and separation-of-duty rule.
- Bind each decision to one event digest, one policy, one action, and an expiry.
- Make approval, rejection, cancellation, timeout, and reassignment atomic.
- Prevent self-approval where policy forbids it.
- Connect an approved decision to an idempotent commit gateway.
- Store evidence in append-only storage with an independently verifiable digest.

Exit evidence:

- Race tests for two reviewers, timeout versus approval, and cancel versus
  commit.
- Session theft, stale page, replayed decision, and revoked-role tests.
- Accessibility and operator-error review of the decision interface.
- Recovery test proving pending reviews survive restart without duplicate
  commits.

### Gate 8: Formal assurance

Required controls:

- Name the exact theorem set included in a release.
- Remove `sorry`, admitted axioms, trivial crypto definitions, and unused test
  files from the release proof target.
- Model failure, overflow, ordering, replay, and bounded-resource behavior.
- Document which implementation artifacts refine or are generated from the
  model.
- Pin the Lean toolchain and dependency graph.

Exit evidence:

- `lake build` from a clean, network-controlled environment.
- Automated scan rejecting admitted terms in the release theorem closure.
- Proof manifest containing source digests, toolchain digests, theorem names,
  and command output.
- Independent review of model assumptions and implementation correspondence.

Formal verification applies only to the model and theorem closure named in the
evidence. It must not be generalized to adapters, storage, crypto libraries, or
runtime code that the model does not cover.

### Gate 9: Supply chain and release integrity

Required controls:

- Define one root build entry point and fail on missing required toolchains.
- Lock dependencies and verify registry or vendor integrity.
- Pin CI actions, containers, compilers, and proof toolchains by immutable
  identifiers.
- Generate an SBOM for each distributed artifact.
- Produce build provenance and sign releases with a protected identity.
- Scan source, dependencies, containers, and release archives.
- Keep build output and credentials out of source history.

Exit evidence:

- Clean-checkout CI run for the exact release commit.
- Machine-readable test manifest with executed, skipped, and failed counts.
- SBOM, provenance, checksums, vulnerability disposition, and signatures.
- Rebuild comparison from an independent runner.
- Release approval by a principal other than the artifact builder.

### Gate 10: Observability and operations

Required controls:

- Use structured logs with stable event, trace, partition, policy, and release
  identifiers.
- Export queue depth, oldest-event age, decision latency, dispatch latency,
  commit latency, replay rejects, policy failures, native failures, evidence
  verification failures, and recovery progress.
- Trace one event across ingress, policy, routing, review, adapter, and evidence.
- Redact payloads, credentials, signatures, and sensitive evidence metadata.
- Define health, readiness, and dependency status separately.
- Provide runbooks for saturation, corrupted evidence, key compromise, policy
  failure, adapter outage, stuck review, and failed rollout.

Exit evidence:

- Alert tests and dashboard review.
- On-call exercise using only published runbooks.
- Log-redaction tests with representative sensitive payloads.
- Demonstrated event-level diagnosis without direct database mutation.

### Gate 11: Capacity, resilience, and performance

Do not set release targets from placeholder configuration values. Establish
targets from a declared workload and business requirement.

Required test dimensions:

- payload and evidence size distributions;
- number of producers, tenants, partitions, reviewers, and adapters;
- steady-state, burst, backlog catch-up, and hot-partition traffic;
- policy cache hit and miss behavior;
- review-required and automatic paths;
- storage latency, network loss, and dependency degradation;
- key rotation and evidence verification load; and
- supported CPU, memory, filesystem, and platform combinations.

Exit evidence:

- Reproducible benchmark harness and raw results.
- p50/p95/p99 latency with confidence intervals where appropriate.
- Throughput at the declared durability level.
- Saturation point, queue growth behavior, and recovery time.
- Soak test with memory, descriptor, scheduler, and storage trends.
- Fault-injection results and accepted residual risks.

### Gate 12: Release, rollback, and incident response

Required controls:

- Version schema, runtime, policy, proof manifest, and deployment package
  independently.
- Define compatible upgrade and downgrade paths.
- Use staged rollout with automated health and evidence-integrity gates.
- Keep database and evidence migrations backward compatible through rollback.
- Reconcile external adapter effects before retry or rollback.
- Maintain a signed release inventory and supported-version policy.
- Define severity, containment, evidence preservation, notification, and
  post-incident review procedures.

Exit evidence:

- Staging promotion using the exact production artifact.
- Failed-canary rollback exercise.
- Mixed-version and downgrade tests.
- Key-compromise and corrupted-evidence incident exercises.
- Signed release record linking source, tests, proof manifest, SBOM,
  provenance, configuration schema, and operator approval.

## Edge-case test matrix

Every row requires an automated test or a documented platform exercise.

| Condition | Expected system property |
| --- | --- |
| Empty, maximum, and over-limit payload | Accept only documented sizes; reject before expensive work |
| Invalid UTF-8, normalization variants, and embedded nulls | Canonical parser behavior is identical across languages |
| Duplicate map key or reordered fields | Reject ambiguity or serialize to exactly one byte sequence |
| Unknown schema version | Reject or negotiate without guessing |
| Integer boundary and offset wrap | No truncation, sign conversion, panic, or reused offset |
| Timestamp before epoch, far future, or excessive skew | Stable policy result with recorded clock evidence |
| Missing, zero, wrong-purpose, expired, or revoked key | Authentication fails closed |
| Valid signature over the wrong tenant or environment | Domain binding rejects it |
| Replayed event before and after restart | Durable replay policy produces the same rejection |
| Two writers append concurrently | Ordering and chain tip remain valid |
| Crash before WAL flush | Recovery follows the documented acceptance contract |
| Crash after effect but before receipt | Reconciliation avoids a duplicate external effect |
| Truncated or reordered evidence segment | Verification detects and quarantines corruption |
| Policy process absent, slow, or malformed | No unauthorized execution; queue/dead-letter behavior is bounded |
| Review approved twice | One durable transition and one external effect |
| Approval races timeout or cancellation | Exactly one terminal state wins |
| Reviewer loses role after loading request | Commit-time authorization prevents stale approval |
| Adapter returns success after caller timeout | Reconciliation resolves unknown outcome before retry |
| One partition becomes hot | Backpressure is bounded and unrelated partitions remain available |
| Native call blocks or crashes | Scheduler and host-VM failure stay within the declared boundary |
| Disk full, read-only, or high latency | Acceptance and health signals match durability guarantees |
| Log or metrics backend unavailable | Processing follows a documented policy without leaking data |
| Key rotation during in-flight event | Verification uses the correct historical and active key versions |
| Rolling upgrade changes schema | Mixed versions interoperate or rollout stops automatically |
| Identifier is short, long, or multibyte | Diagnostics never panic or split invalid bytes |

## CI release pipeline

A production branch should require these stages in order:

1. Repository policy: formatting, generated-file drift, license consistency,
   secret scan, and forbidden-artifact scan.
2. Component builds: Rust all targets, Erlang release, native kernel/NIF, Lean
   theorem set, code generators, and supported adapters on their real
   platforms.
3. Component tests: unit, property, negative, and mutation-sensitive tests with
   explicit discovered-test counts.
4. Contract tests: canonical vectors and cross-language round trips.
5. Security tests: fuzzing, sanitizers, dependency review, static analysis, and
   authorization/replay suites.
6. Integration tests: policy, routing, review, adapter, evidence, restart, and
   reconciliation.
7. Resilience tests: dependency loss, crash points, corrupted state, resource
   exhaustion, and mixed-version rollout.
8. Assurance: Lean build, admitted-term gate, proof manifest, and traceability
   to implementation or conformance tests.
9. Artifact build: locked inputs, SBOM, provenance, checksums, and signature.
10. Promotion: independent approval, canary, automatic stop conditions, and
    evidence-integrity verification.

Each stage must emit a machine-readable result. A skipped required stage blocks
promotion.

## Operational acceptance

Before the first production deployment, operators must be able to answer:

- What exactly has been accepted if the process dies at this instruction?
- Where is the durable idempotency decision?
- Which policy and key version authorized this event?
- Has an external effect occurred when the adapter response is unknown?
- Can this evidence be deleted or altered by the service administrator?
- How is a corrupt chain isolated without hiding subsequent valid records?
- What happens when every reviewer is unavailable?
- Which metric proves the system is keeping up?
- Which artifact, schema, configuration, and proof manifest are running?
- Can the previous version be restored without reapplying an irreversible
  effect?

If any answer depends on reading source during an incident, the runbook and
telemetry are incomplete.

## Current readiness ledger

| Gate | State | Primary reason |
| --- | --- | --- |
| Canonical protocol | Open | Cross-language layouts and hash inputs differ |
| Identity and cryptography | Open | Placeholder verification, signing, and key material remain |
| Replay and idempotency | Open | No durable cross-component replay store |
| Durable append and recovery | Open | WAL is not connected to the kernel append path |
| Runtime and native isolation | Open | Runtime/NIF interfaces do not compile and integrate as one boundary |
| Policy enforcement | Open | Policy execution and failure behavior are stubbed |
| Human review | Open | Crate compile and durable authorization workflow are incomplete |
| Formal assurance | Open | Lean build fails and proof placeholders remain |
| Supply chain | Open | No required CI/release provenance pipeline |
| Observability and operations | Open | No integrated telemetry, SLOs, or exercised runbooks |
| Capacity and resilience | Open | No reproducible benchmark or soak evidence |
| Release and incident response | Open | No staged release, rollback, or incident evidence |

Closing a gate requires a pull request that links the implementation, tests,
generated evidence, owner review, and any accepted residual risk. Documentation
language may be upgraded only in the same change or a later change that cites
that evidence.
