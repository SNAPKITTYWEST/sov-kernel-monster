# Developer Guide

This guide describes how to inspect, build, test, and change the current
Sovereign Event Bus repository. It documents the repository as it exists,
including known failures. It does not treat historical completion reports as a
substitute for a clean build.

## Start here

SEB is a collection of component projects, not a root workspace or a single
server. Choose the boundary you are changing before installing toolchains.

```text
contracts/codegen  -> candidate language contracts
kernel             -> Ada state and append interfaces, C Erlang NIF surface
runtime            -> Erlang/OTP coordination
reasoning          -> Rust A2A events and in-memory traces
universe           -> Rust artifact manifests and gate model
human_touch        -> Rust review workflow prototype
verification       -> Lean models and proof sources
adapters           -> IBM i and z/OS integration assets
```

There is no JavaScript application, Node build, root `package.json`, or root
`Cargo.toml` in this repository.

## Clean checkout

```bash
git clone https://github.com/SNAPKITTYWEST/Sovereign-Event-Bus.git
cd Sovereign-Event-Bus
git status --short
```

The last command should print nothing. Build in the repository only when local
artifacts are acceptable; Cargo creates nested `target/` directories and can
create a crate-level `Cargo.lock` when one is absent.

Before committing:

```bash
git status --short
git diff --check
git diff --stat
```

Inspect every untracked file. Do not commit `target/`, `.lake/`, native
binaries, reports containing local paths, credentials, or generated deployment
archives.

## Toolchains

### Rust components

Install Rust and Cargo through a controlled toolchain appropriate to your
environment. The repository does not currently pin a Rust version.

Crates:

- `seb/reasoning`
- `seb/universe`
- `seb/human_touch`

Each crate is independent. Run commands with `--manifest-path` from the root or
change into that crate.

### Erlang runtime

Install Erlang/OTP and `rebar3`. Dependency resolution needs registry/network
access unless dependencies are already cached. The current runtime has source
issues that must be fixed before a release build can pass.

### Lean verification

Install `elan`, which provides Lean and `lake`. The project pins Lean 4.7.0 in
`seb/verification/lean4/lean-toolchain` and mathlib 4.7.0 in its Lake
configuration. The first build may need to download dependencies.

### Kernel

The intended native boundary needs:

- GNAT/SPARK and GNATprove for Ada;
- a C compiler;
- Erlang NIF headers matching the deployment OTP version;
- selected BLAKE3 and Ed25519 libraries; and
- a supported persistence API for the target operating system.

No GNAT project, native dependency manifest, or portable kernel build target is
currently checked in. Establish those before publishing a build command.

### Contracts and adapters

Contract generation assumes Bash, GNU Make, and common GNU command-line
utilities. Python 3 is used by the kernel vector script. TypeScript and YAML
tools are optional checks in the current Makefile.

The RPG source requires an IBM i environment with the external objects
described in `seb/adapters/L4_ADAPTER_BUILD_GUIDE.md`. The PL/I asset is a set of
declarations, not a complete executable adapter.

## Verified baseline

The following results were observed on 2026-07-25. Re-run them after any source
or dependency change.

| Component | Command | Current result |
| --- | --- | --- |
| Reasoning library | `cargo test --manifest-path seb/reasoning/Cargo.toml --lib` | Passes 18 tests |
| Reasoning build | `cargo build --manifest-path seb/reasoning/Cargo.toml` | Passes |
| Reasoning all targets | `cargo test --manifest-path seb/reasoning/Cargo.toml --all-targets --all-features` | Fails to compile the example |
| Universe library | `cargo test --manifest-path seb/universe/Cargo.toml --lib` | Passes 15 tests |
| Universe build | `cargo build --manifest-path seb/universe/Cargo.toml` | Passes |
| Universe all targets | `cargo test --manifest-path seb/universe/Cargo.toml --all-targets` | Fails to compile the example |
| Human review | `cargo test --manifest-path seb/human_touch/Cargo.toml` | Fails to compile |
| Erlang runtime | `rebar3 compile` | Not established as a passing build |
| Lean | `lake build` in `seb/verification/lean4` | Fails; admitted terms also remain |
| Ada/C kernel | No portable command | Build is not established |
| IBM adapters | Platform-specific | Not validated on target systems |

All three Rust crates currently report formatting drift under `cargo fmt
--all -- --check`, and the all-target Clippy commands are not clean. Formatting
and linting are therefore repair gates, not passing evidence.

### Reproduce the passing Rust suites

```bash
cargo test --manifest-path seb/reasoning/Cargo.toml --lib
cargo test --manifest-path seb/universe/Cargo.toml --lib
```

Library-only testing is intentionally explicit. Plain `cargo test` also builds
examples in these crates and currently fails.

## Known build failures

These are starting points for repair, not an exhaustive defect list.

### Reasoning example

`seb/reasoning/examples/demo.rs` accesses the private `protocol_handler` field
and passes `Option<String>` where the current `set_query` API accepts a
different value. Reconcile the example with the public library API, then make
the all-targets command a required test.

### Universe example

`seb/universe/examples/universe_demo.rs` imports `Invariant`, `ProofMetadata`,
and `TestMetadata` from the crate root, but `seb/universe/src/lib.rs` does not
re-export those names. Decide whether they belong in the public API or update
the example to import their defining module.

### Human review crate

`seb/human_touch/src/main.rs` passes `Arc<Mutex<ReviewQueue>>` into a function
that expects `Arc<ReviewQueue>`. Fix the ownership contract rather than adding
an unsafe or duplicate synchronization layer. After it compiles, connect a real
submission source and prove that an approval reaches the commit gateway exactly
once.

### Erlang runtime

Current issues include:

- `void()` is used as an undefined type in `seb_agent_fsm.erl`;
- a deprecated `catch` form conflicts with warnings-as-errors;
- test function names are not discoverable by EUnit;
- integration fixtures return `{ok, Pid}` but later treat the tuple as a PID;
- the release configuration lists modules where relx expects applications;
- `runtime/config/sys.config` contains a checked-in distributed Erlang cookie
  that must be removed from source, externally provisioned, and rotated;
- the Datalog bridge can have no live port; and
- the Erlang kernel facade neither loads nor matches the C NIF interface.

A successful runtime repair must show nonzero discovered-test counts, not only a
zero exit code.

### Lean project

The default Lake library does not type-check, multiple sources contain `sorry`,
and the checked-in `Tests.lean` is not wired as a Lake test target. Some
cryptographic functions are deliberately trivial models. Repair the build
before deciding which theorem closure is eligible for release evidence.

### Kernel

The Ada kernel and C NIF do not currently form one implementation:

- the C NIF duplicates state instead of calling Ada;
- the NIF has a duplicate local declaration;
- signature/hash validation and key registry paths include placeholders;
- WAL source exists but is not connected to append;
- the Ada source has unresolved type/build issues; and
- the runtime facade uses a different handle and arity contract.

Start by writing a versioned ABI document and a minimal native build that treats
warnings as errors. Do not repair each side independently without conformance
tests.

## Component workflows

### Reasoning

Primary files:

- `seb/reasoning/src/a2a_protocol.rs`
- `seb/reasoning/src/trace.rs`
- `seb/reasoning/src/streaming.rs`
- `seb/reasoning/src/integration.rs`
- `seb/reasoning/src/lib.rs`

Suggested local loop:

```bash
cargo fmt --manifest-path seb/reasoning/Cargo.toml -- --check
cargo test --manifest-path seb/reasoning/Cargo.toml --lib
cargo test --manifest-path seb/reasoning/Cargo.toml --all-targets --all-features
```

The first two commands should remain fast. The final command is the integration
gate to restore. Add boundary tests for empty, short, long, and multibyte IDs:
some current diagnostics slice strings by fixed byte offsets.

The current trace signature is a placeholder digest/length check. Name any
replacement type after its actual security property and add negative tests
before describing it as a signature.

### Universe

Primary files:

- `seb/universe/src/manifest.rs`
- `seb/universe/src/search_substrate.rs`
- `seb/universe/src/compile_verify_merge.rs`
- `seb/universe/src/lib.rs`

Suggested local loop:

```bash
cargo fmt --manifest-path seb/universe/Cargo.toml -- --check
cargo test --manifest-path seb/universe/Cargo.toml --lib
cargo test --manifest-path seb/universe/Cargo.toml --all-targets
```

Current gate stages model metadata transitions; they do not invoke a compiler,
test runner, proof checker, reviewer, merge service, or deployment target. Keep
simulation types separate from production execution types. A caller can also
mutate or mark gate state directly, so no authorization decision should depend
on this object yet.

`seb/universe/repository.json` is development data, not a trusted manifest. It
contains structural and value issues; validate it against a schema before using
it in tests or tooling.

### Runtime

Intended commands:

```bash
cd seb/runtime
rebar3 format --verify
rebar3 compile
rebar3 eunit
rebar3 dialyzer
rebar3 release
```

Some plugins or targets may need to be added or pinned before every command is
available. The eventual CI job must report the number of EUnit tests executed.

Runtime changes should cover:

- supervisor restart and shutdown behavior;
- correct `gen_statem` call/reply actions;
- policy timeout and deny-on-error behavior;
- idempotent partition assignment and real reassignment;
- drain behavior with queued and in-flight events;
- NIF load/version errors; and
- crash containment for native work.

### Verification

```bash
cd seb/verification/lean4
lake build
```

Before a proof artifact is release eligible:

1. Define the exact imported theorem closure.
2. Reject `sorry`, `admit`, and unreviewed axioms in that closure.
3. Record Lean, Lake, mathlib, and source digests.
4. Connect the model to a canonical protocol or implementation conformance
   artifact.
5. Preserve full command output and exit status.

`lake test` is not currently declared. Add an explicit executable/test target
or use buildable example/theorem modules with a documented command.

### Contracts and code generation

The five templates in `seb/contracts` are independent hand-maintained shapes.
The scripts under `seb/scripts/codegen` mainly copy them to expected locations.
Some output directories referenced by the scripts are absent in this repository.

Before running a generator:

```bash
git status --short
sed -n '1,220p' seb/scripts/codegen/generate_all.sh
```

After running one:

```bash
git status --short
git diff --check
git diff
```

Do not accept generated parity based on filenames. Add golden byte vectors and
round-trip tests for every language. The protocol source of truth must define
canonical bytes, not only language-level field names.

The root `seb/Makefile` still validates scaffold paths that are not present and
can downgrade tool failures to warnings. Treat its targets as development
helpers until they fail reliably on missing required work.

The manifest-hash target also depends on GNU traversal tools. Its current output
does not match the value recorded in `seb/GenesisConfig.toml`, and the existing
verification target checks for the configuration key rather than proving the
value is current. Rebuild this as a canonical, cross-platform manifest format
before treating the hash as integrity evidence.

### Legacy adapters

Use the platform guide in `seb/adapters` to inventory external programs, files,
queues, DB2 tables, authorities, and transaction boundaries. Before enabling a
real effect:

- escape and validate every value embedded in JSON or command text;
- reconcile RPG, copybook, PL/I, and canonical protocol layouts;
- define idempotency and outcome reconciliation;
- test commit, rollback, timeout, and connection loss on the actual platform;
- restrict program/library authority to the required operation; and
- capture platform compiler, linker, object, and deployment versions.

PL/I declarations should remain labeled declarations until a callable
implementation and platform test evidence exist.

## BOB shell workflow

The six scripts in `bob-shell` are development wrappers. Read a script before
using it in a protected checkout:

```bash
sed -n '1,260p' bob-shell/bob-build.sh
sed -n '1,300p' bob-shell/bob-test.sh
sed -n '1,320p' bob-shell/bob-audit.sh
sed -n '1,320p' bob-shell/bob-policy.sh
sed -n '1,320p' bob-shell/bob-proof.sh
sed -n '1,360p' bob-shell/bob-deploy.sh
```

Current behavior to account for:

- missing tools can be skipped by build logic;
- deterministic test mode sets environment variables but does not control all
  sources of nondeterminism;
- audit output depends on traversal order, timestamps, GNU utilities, and
  working-tree contents;
- policy and proof commands can create root-level scaffold files;
- a caller-supplied Prolog query is executable input;
- proof certificates can describe placeholder output;
- deploy validation and sealing can be disabled; and
- packaging success does not prove runtime, policy, evidence, or adapter health.

For evaluation, use a disposable branch or worktree and compare status before
and after:

```bash
git status --short
bash bob-shell/bob-audit.sh
git status --short
```

For CI, replace silent skips with an explicit required/optional component
manifest. Emit structured results containing command, tool version, exit code,
duration, test count, skipped reason, and artifact digest.

## Contract change procedure

Any envelope, receipt, offset, signature, policy-decision, or evidence change is
a cross-component change.

1. Write the byte-level compatibility rule and migration behavior.
2. Add positive and negative vectors before updating implementations.
3. Update every supported decoder and encoder.
4. Run cross-language round-trip and byte-equality tests.
5. Update proof models and state whether the theorem set changed.
6. Exercise mixed-version producer, runtime, adapter, and verifier pairs.
7. Record the oldest readable and writable protocol versions.
8. Update operational rollback constraints.

A source-compatible struct change can still be wire-incompatible.

## Testing expectations

Choose tests according to the boundary:

| Change | Required evidence |
| --- | --- |
| Pure Rust logic | Unit tests plus all-target compilation |
| Parser or serializer | Golden vectors, negative cases, property tests, and fuzz seed |
| Signature or hash input | Known-answer and mutation tests across languages |
| Runtime state machine | EUnit/property tests for every transition and timeout |
| Native boundary | ABI tests, sanitizers, leak checks, malformed input, and crash isolation |
| Persistence | Kill-point, partial-write, corruption, restore, and concurrent-writer tests |
| Human approval | RBAC, expiry, replay, race, restart, and idempotent commit tests |
| Adapter | Target-platform integration plus unknown-outcome reconciliation |
| Lean model | Clean build, admitted-term gate, assumptions review, and implementation traceability |
| Release tooling | Clean-checkout run with required-tool and zero-test failure cases |

Tests that depend on time, random input, filesystem order, locale, or network
must either control those inputs or record them in reproducible evidence.

## Security-sensitive review

Require at least one reviewer who understands the affected trust boundary for:

- canonical parsing and serialization;
- authentication, authorization, keys, signatures, or hashes;
- policy evaluation;
- offsets, ordering, idempotency, or replay;
- WAL, evidence, backup, restore, or retention;
- NIF/native memory and scheduler behavior;
- human approval and separation of duties;
- release signing, provenance, or dependency changes; and
- theorem assumptions or model-to-code claims.

Reviewers should ask what happens on timeout, retry, restart, duplicate input,
partial completion, stale authorization, malformed data, and rollback.

## Pull request evidence

A focused change should state:

```text
Boundary changed:
Behavior before:
Behavior after:
Failure behavior:
Compatibility impact:
Commands executed:
Tests discovered/passed/failed/skipped:
Generated artifacts:
Security assumptions:
Operational or rollback impact:
Known residual risk:
```

Attach logs or machine-readable reports for release gates, but keep transient
build output out of Git. Claims in README files, reports, certificates, and
release notes must match the commands executed in the same revision.

## Documentation rules

- Describe implemented behavior in the present tense.
- Describe intended design with words such as "intended," "planned," or
  "modeled."
- Name the command and test count behind a passing claim.
- Call a cryptographic primitive by name only when that primitive is actually
  used and verified.
- Do not call ordinary files WORM storage.
- Do not call metadata checks compilation, proof, review, merge, or deployment.
- Do not label a proof zero-placeholder until CI scans the release theorem
  closure.
- Keep performance values labeled as targets until a reproducible benchmark
  produces them.

The release-readiness criteria live in
[`PRODUCTION_HARDENING.md`](PRODUCTION_HARDENING.md).
