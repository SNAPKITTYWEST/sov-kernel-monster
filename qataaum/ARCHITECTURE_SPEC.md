# BOB IDE — Quantum Cognitive Civilization Engine
## RBG-FS Architecture Specification v3.0

**Engine Name:** RBG-FS Engine  
**Expansion:** R orchestration, Bash governance, GNU Fortran numerical computation, Smalltalk civilization semantics  
**Mission:** Production-scale multi-language quantum-cognitive civilization engine for BOB IDE

---

## Scientific Integrity Declaration

### Classification
The local implementation is a **classical simulation of quantum-state-inspired dynamics** using NumPy-equivalent operations. This is NOT quantum computation executed on IBM Quantum hardware.

### Real Quantum Requirement
The phrase "executed on IBM Quantum hardware" may only be used when:
- Valid quantum circuits are created
- Submitted to authenticated IBM Quantum backend
- Backend job identifiers received
- Measured results received with backend metadata
- Verifiable execution receipt produced

### Dual Execution Modes
1. **Simulation Mode**: Classical local simulation via Fortran kernels
2. **Hardware Mode**: Optional authenticated IBM Quantum provider adapter with actual job submission

---

## Language Constitution

### Smalltalk (Domain Sovereign)
**Runtime:** Pharo Smalltalk  
**Role:** Live civilization object graph, agents, knowledge nodes, social relations, messages, governance, event dispatch, reflection, inspection, image-based development

**Responsibilities:**
- QuantumCognitiveAgent objects
- KnowledgeNode objects
- Civilization objects
- LatticeProxy objects
- AgentAction objects
- Perception, Decision, Reflection objects
- SocialLink objects
- MetricSnapshot objects
- SimulationSession objects
- Provider objects, Tool objects, Receipts

**Principle:** Every domain entity must be inspectable while the system runs. Behavior belongs to objects. State transitions occur through messages.

### Fortran (Numerical Sovereign)
**Standard:** Fortran 2018 or newer  
**Compiler:** GNU Fortran baseline  
**Role:** High-performance numerical engine for state evolution, lattice operations, Hamiltonians, linear algebra, measurements, entropy metrics, batch simulation

**Responsibilities:**
- Complex-valued state vectors
- Density matrices (where configured)
- Sparse lattice coupling
- Gate application
- Tensor products
- Hamiltonian construction
- Time evolution
- Measurement distributions
- Entanglement metrics
- Deterministic seeded simulation
- Snapshot serialization

**Interfaces:** ISO_C_BINDING ABI, stable C-compatible function surface, explicit-width numeric types, caller-owned buffer contracts, error codes with structured diagnostics

### R (Experimental Sovereign)
**Role:** Scientific analysis, experiment configuration, metrics, statistical validation, visualization, reproducibility reports, model comparisons, benchmark analysis

**Responsibilities:**
- Parameter sweeps
- Statistical summaries
- Convergence analysis
- Coherence/entropy/energy plots
- Agent-behavior distributions
- Regression detection
- Reproducibility reports
- Quarto technical reports

**Rules:** R must not become the latency-critical simulation loop. R consumes typed engine outputs. All experiments accept explicit seeds and configuration files.

### Bash (Execution Sovereign)
**Role:** Reproducible local tool execution, builds, tests, packaging, process supervision, environment validation, CI entry points, developer commands

**Rules:** Strict mode, quote variables, validate paths, resolve repository roots, never silently ignore failed commands, produce machine-readable receipts

**Prohibited:** Bash must not contain core simulation mathematics or parse complex structured data using fragile text pipelines.

### Rust (Security Sovereign)
**Role:** Tauri host, WebSocket bridge, process security, capability enforcement, protocol validation, filesystem boundaries, tool receipts, native packaging

### TypeScript (Interface Sovereign)
**Role:** Browser IDE, Monaco integration, autonomous chat, route state, WebLLM, diff review, terminal display, GitHub integration, WebSocket client

---

## Architecture Layers

### Layer 1: Interface
- **Runtime:** GitHub Pages browser application or Tauri webview
- **Language:** TypeScript + semantic CSS
- **Components:** Monaco editor, BOB autonomous chat, xterm.js terminal, civilization inspector, quantum-state inspector, metrics viewer, GitHub source control, diff review, execution receipts

### Layer 2: Native Control (BOB Bridge)
- **Runtime:** Rust WebSocket server
- **Transport:** Authenticated localhost WebSocket
- **Components:** Capability negotiation, process manager, filesystem gateway, Git gateway, shell gateway, Smalltalk runtime adapter, Fortran engine adapter, R analysis adapter, IBM Quantum provider adapter

### Layer 3: Civilization
- **Runtime:** Pharo Smalltalk image
- **Language:** Smalltalk
- **Components:** Agent society, knowledge graph, six-stage cognitive lifecycle, actions, social relations, governance, persistence orchestration, live inspection

### Layer 4: Numerical
- **Runtime:** Native shared library or supervised worker process
- **Language:** Fortran
- **Components:** Quantum-inspired state engine, lattice engine, Hamiltonian engine, integrator, measurement engine, metrics engine

### Layer 5: Analysis
- **Runtime:** Supervised R process
- **Language:** R
- **Components:** Experiment runner, metrics analyzer, visualization generator, benchmark report, validation report

---

## Control Flow

### Interactive Cycle
1. User sends instruction through BOB chat interface
2. BOB agent converts request into visible execution plan
3. Browser sends typed request to Rust BOB Bridge
4. Bridge validates origin, session, workspace, capability, permission
5. Bridge sends domain message to Smalltalk civilization runtime
6. Smalltalk resolves objects, cognitive phase, agent state, requested behavior
7. Smalltalk creates typed numerical request for Fortran engine
8. Fortran validates dimensions, normalization, timestep, seed, memory bounds
9. Fortran computes requested evolution and returns structured results
10. Smalltalk applies domain semantics and emits civilization events
11. Rust streams events, metrics, state deltas, logs, receipts over WebSocket
12. Browser updates inspectors without blocking Monaco or chat composer

### Analysis Cycle
1. User or agent selects experiment
2. Smalltalk creates immutable experiment specification
3. Bash launches supervised Fortran batch worker
4. Fortran writes typed result artifacts
5. R validates, summarizes, visualizes outputs
6. BOB displays report and links to execution receipts

---

## Smalltalk Domain Model

### BOBCivilization
**State:** agents, knowledgeGraph, socialGraph, globalLattice, simulationClock, governancePolicy, eventJournal, activeExperiment

**Messages:** initializeFromConfiguration:, advanceBy:, executeCycle, addAgent:, removeAgent:, inspectAgent:, publishEvent:, createCheckpoint, restoreCheckpoint:, collectMetrics, exportSnapshot

### BOBQuantumCognitiveAgent
**State:** identifier, localLattice, knowledgeNodes, relationships, cognitivePhase, energyBudget, coherenceEstimate, actionHistory, randomStream

**Messages:** perceive:, reason, learnFrom:, decide, actIn:, reflect, executeCognitiveCycleIn:, receiveMessage:, formRelationshipWith:, inspectState

### BOBKnowledgeNode
**State:** identifier, proposition, confidence, provenance, numericalStateReference, creationEvent, revisionHistory

**Messages:** reinforceBy:, penalizeBy:, mergeWith:, measureConfidence, addProvenance:, reviseWith:

### BOBFortranEngine
**Responsibility:** Smalltalk proxy for native numerical ABI

**Messages:** createState:, destroyState:, applyGate:to:, evolve:withHamiltonian:forDuration:, measure:usingSeed:, computeMetrics:, createLattice:, updateLattice:

### BOBExperiment
**State:** identifier, configuration, seed, startTime, endTime, engineVersion, results, receipts

### BOBExecutionReceipt
**State:** identifier, timestamp, operation, inputsHash, outputsHash, engineVersion, seed, exitStatus, diagnostics, executionLocation

---

## Six-Stage Cognitive Cycle

1. **Perceive:** Receive environment deltas, messages, measurements, available actions. Preserve provenance.
2. **Reason:** Evaluate knowledge relationships, request numerical operations. No stochastic selection as substitute for reasoning.
3. **Learn:** Update knowledge confidence under explicit rules. Preserve prior state, create revision event.
4. **Decide:** Rank valid actions using policy, state, evidence, configured stochastic behavior. Log candidates and rationale.
5. **Act:** Apply valid action through civilization object model. Validate preconditions and postconditions.
6. **Reflect:** Compare outcome with intent, update metrics, record lessons, create receipt.

---

## Fortran Engine Modules

### bob_kinds
Define explicit integer and real kinds, complex precision, ABI-compatible type aliases

### bob_errors
Stable error codes, diagnostic buffers, no uncontrolled process termination

### bob_rng
Deterministic seeded pseudo-random streams, independent streams per agent, reproducible measurement sampling

### bob_state
State-vector representation, optional density-matrix representation, normalization validation, allocation and release

### bob_gates
Pauli X, Y, Z, Hadamard, T gate, controlled gates, arbitrary validated unitary operators

### bob_tensor
Tensor products, subsystem indexing, joint-state construction, partial trace where supported

### bob_lattice
Lattice dimensions, neighbor topology, boundary conditions, coupling matrix, local state references

### bob_hamiltonian
Kinetic terms, interaction terms, external-field terms, Hermiticity checks, sparse and dense execution paths

### bob_integrator
Exact matrix exponential for small systems, stable numerical approximation for larger systems, configurable timestep, error estimates, norm-preservation checks

### bob_measurement
Basis measurement, probability distribution, sampling, collapse behavior, batch shots

### bob_metrics
Norm, energy expectation, purity, von Neumann entropy, reduced-state metrics, fidelity, coherence indicators with precise definitions

### bob_surface_code
Only exists when stabilizers, syndrome extraction, logical states, error injection, decoding, validation are implemented. Otherwise explicitly marked unavailable.

### bob_abi
Export stable ISO_C_BINDING interface consumed by Rust and Smalltalk adapters

---

## Fortran ABI Functions

```fortran
bob_engine_version()
bob_state_create()
bob_state_destroy()
bob_state_normalize()
bob_state_validate()
bob_gate_apply()
bob_hamiltonian_create()
bob_hamiltonian_destroy()
bob_state_evolve()
bob_state_measure()
bob_lattice_create()
bob_lattice_step()
bob_metrics_compute()
bob_snapshot_write()
bob_snapshot_read()
bob_last_error()
```

**Contract:** Every function returns stable status code. Every buffer has explicit length. No function reads beyond caller-provided bounds. No ABI function throws, aborts, or writes to uncontrolled standard output.

---

## R Analysis Engine

**Package:** bobCivilizationR

**Commands:** bob-experiment, bob-analyze, bob-benchmark, bob-report, bob-compare

**Analyses:** Repeated-run variance, seed sensitivity, conservation diagnostics, norm drift, energy drift, scaling by lattice size, scaling by agent count, action-frequency distributions, knowledge-confidence calibration, social-network evolution, correlation vs causation warnings, simulation vs hardware result comparison

**Reporting:** Quarto for reproducible HTML and PDF reports including configuration, seed, software versions, commit hash, engine mode, machine metadata, runtime, warnings, receipt identifiers

---

## Bash Scripts

- `scripts/bootstrap.sh` - Validate compilers, runtimes, package managers, system requirements
- `scripts/build-fortran.sh` - Build debug and release numerical libraries
- `scripts/build-smalltalk.sh` - Prepare Pharo image and load project packages
- `scripts/build-bridge.sh` - Build Rust bridge
- `scripts/test-all.sh` - Run all tests (Fortran, Smalltalk, Rust, TypeScript, R, protocol, integration)
- `scripts/run-civilization.sh` - Launch bridge, Smalltalk runtime, numerical engine, development UI
- `scripts/run-experiment.sh` - Execute configured deterministic batch experiment
- `scripts/generate-report.sh` - Run R analysis and generate reproducibility reports
- `scripts/package.sh` - Produce versioned runtime artifacts

**Receipt Output:** Every script writes structured JSON receipt containing command, repository commit, working directory, start/end time, tool versions, exit status, generated artifacts, hashes

---

## WebSocket Services

### civilization namespace
- civilization.create, .start, .pause, .step, .stop, .snapshot, .restore, .inspect, .metrics.subscribe, .event

### agent namespace
- agent.list, .create, .inspect, .cycle, .message, .action.approve, .event

### quantum namespace
- quantum.state.create, .inspect, .gate.apply, .evolve, .measure, .metrics, .result

### experiment namespace
- experiment.create, .run, .cancel, .progress, .complete, .report

### runtime namespace
- runtime.capabilities, .health, .logs, .receipt, .error

**Streaming Rules:** Assign every operation a request identifier. Stream progress without blocking command responses. Preserve event order per simulation session. Attach simulation tick and event sequence to civilization events. Never silently retry state mutations after uncertain connection failure.

---

## BOB IDE Integration

### Routes
- `/workspace/:workspaceId/civilization` - Live civilization map, agent list, state timeline, knowledge graph, social network, metrics, controls, event stream
- `/workspace/:workspaceId/civilization/agents/:agentId` - Object inspector for one Smalltalk agent
- `/workspace/:workspaceId/quantum` - Simulation-state inspector, lattice viewer, operator history, measurement distributions, normalization diagnostics, energy, entropy, coherence metrics
- `/workspace/:workspaceId/experiments` - Experiment configurations, active runs, completed runs, comparisons, reports
- `/workspace/:workspaceId/runtime` - Smalltalk image state, Fortran engine state, R worker state, bridge state, process logs, versions, capabilities, receipts

### Agent Chat Tools
- inspect_civilization, inspect_agent, advance_civilization, pause_civilization, create_checkpoint, restore_checkpoint, run_experiment, compare_experiments, apply_quantum_gate, measure_state, analyze_metrics, generate_report

**Visual Principle:** Civilization controls belong beside autonomous BOB chat and active editor. Do not convert IDE into detached analytics dashboard.

---

## Persistence

- **Event Journal:** Append-only ordered domain events generated by Smalltalk
- **Checkpoint:** Versioned full or incremental state snapshots
- **Numerical Snapshot:** Fortran-owned binary format with version, dimensions, precision, endianness, normalization status, checksum
- **Portable Export:** JSON metadata plus referenced binary numerical artifacts
- **Migration:** Explicit schema versions and deterministic migrations. Never load incompatible snapshots silently.

---

## Repository Structure

```
bob-quantum-civilization/
├── apps/
│   ├── bob-web/              # Browser IDE (GitHub Pages)
│   ├── bob-desktop/          # Tauri desktop application
│   └── bob-bridge/           # Rust WebSocket bridge
├── smalltalk/
│   └── src/
│       ├── BOB-Civilization/
│       ├── BOB-Agents/
│       ├── BOB-Knowledge/
│       ├── BOB-Numerics/
│       ├── BOB-Experiments/
│       ├── BOB-Receipts/
│       └── BOB-Protocol/
├── fortran/
│   └── src/
│       ├── bob_kinds.f90
│       ├── bob_errors.f90
│       ├── bob_rng.f90
│       ├── bob_state.f90
│       ├── bob_gates.f90
│       ├── bob_tensor.f90
│       ├── bob_lattice.f90
│       ├── bob_hamiltonian.f90
│       ├── bob_integrator.f90
│       ├── bob_measurement.f90
│       ├── bob_metrics.f90
│       └── bob_abi.f90
├── r/
│   ├── bobCivilizationR/
│   └── experiments/
├── scripts/
│   ├── bootstrap.sh
│   ├── build-fortran.sh
│   ├── build-smalltalk.sh
│   ├── build-bridge.sh
│   ├── test-all.sh
│   ├── run-civilization.sh
│   ├── run-experiment.sh
│   ├── generate-report.sh
│   └── package.sh
├── docs/
│   ├── ARCHITECTURE_SPEC.md
│   ├── FORTRAN_ABI.md
│   ├── SMALLTALK_API.md
│   ├── WEBSOCKET_PROTOCOL.md
│   └── SCIENTIFIC_INTEGRITY.md
├── reference/
│   └── IBM_QUANTUM_WATSON_CIVILIZATION.py  # Behavioral reference
└── README.md
```

---

**Status:** Architecture specification complete. Ready for implementation scaffold.