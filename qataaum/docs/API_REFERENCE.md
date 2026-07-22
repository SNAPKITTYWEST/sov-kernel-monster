# QATAAUM API Reference

**Version:** 1.0  
**Date:** 2026-07-22  
**Project:** QATAAUM Quantum Assembly Runtime

## Table of Contents

1. [Overview](#overview)
2. [Compiler API](#compiler-api)
3. [Simulator API](#simulator-api)
4. [Runtime API](#runtime-api)
5. [FFI API](#ffi-api)
6. [Error Handling](#error-handling)
7. [Examples](#examples)

---

## Overview

QATAAUM provides a comprehensive API for quantum circuit compilation, simulation, and execution. The API is organized into four main modules:

- **Compiler:** Parse, analyze, optimize, and compile quantum circuits
- **Simulator:** Execute circuits on classical simulators
- **Runtime:** Job management, queueing, and execution orchestration
- **FFI:** C-compatible interface for IBM i integration

### Design Principles

- **Type Safety:** Strong typing with Rust's type system
- **Error Handling:** Result types for all fallible operations
- **Zero-Copy:** Minimize allocations and copies
- **Thread Safety:** Safe concurrent access where appropriate
- **Clean Room:** Independent implementation from public specifications

---

## Compiler API

### Parser Module

#### `qataaum_parser::Lexer`

Tokenizes OpenQASM source code.

```rust
pub struct Lexer<'a> {
    source: &'a str,
    position: usize,
}

impl<'a> Lexer<'a> {
    /// Create a new lexer from source code
    pub fn new(source: &'a str) -> Self;
    
    /// Tokenize the entire source
    pub fn tokenize(&mut self) -> Result<Vec<Token>, LexerError>;
}
```

**Example:**
```rust
use qataaum_parser::Lexer;

let source = "OPENQASM 2.0; qreg q[2]; h q[0];";
let mut lexer = Lexer::new(source);
let tokens = lexer.tokenize()?;
```

#### `qataaum_parser::Parser`

Parses tokens into an Abstract Syntax Tree (AST).

```rust
pub struct Parser {
    tokens: Vec<Token>,
    position: usize,
}

impl Parser {
    /// Create a new parser from tokens
    pub fn new(tokens: Vec<Token>) -> Self;
    
    /// Parse tokens into an AST
    pub fn parse(&mut self) -> Result<Program, ParseError>;
}
```

**Example:**
```rust
use qataaum_parser::{Lexer, Parser};

let source = "OPENQASM 2.0; qreg q[2]; h q[0];";
let mut lexer = Lexer::new(source);
let tokens = lexer.tokenize()?;
let mut parser = Parser::new(tokens);
let ast = parser.parse()?;
```

### Semantic Analysis Module

#### `qataaum_semantic::SemanticAnalyzer`

Performs type checking and semantic validation.

```rust
pub struct SemanticAnalyzer {
    symbol_table: SymbolTable,
    errors: Vec<SemanticError>,
}

impl SemanticAnalyzer {
    /// Create a new semantic analyzer
    pub fn new() -> Self;
    
    /// Analyze an AST
    pub fn analyze(&mut self, program: &Program) -> Result<(), SemanticError>;
    
    /// Get the symbol table
    pub fn symbol_table(&self) -> &SymbolTable;
}
```

**Example:**
```rust
use qataaum_semantic::SemanticAnalyzer;

let mut analyzer = SemanticAnalyzer::new();
analyzer.analyze(&ast)?;
```

### IR Module

#### `qataaum_ir::IrBuilder`

Constructs typed intermediate representation.

```rust
pub struct IrBuilder {
    next_id: usize,
}

impl IrBuilder {
    /// Create a new IR builder
    pub fn new() -> Self;
    
    /// Build IR from AST
    pub fn build(&mut self, program: &Program) -> Result<TypedProgram, IrError>;
}
```

#### IR Levels

The QATAAUM compiler uses a 9-level IR pipeline:

1. **Level 0:** Source AST (lossless syntax representation)
2. **Level 1:** Typed AST (resolved names, types, effects)
3. **Level 2:** CFG (control-flow graph)
4. **Level 3:** SSA (static single assignment)
5. **Level 4:** GATE (hardware-independent gates)
6. **Level 5:** TOPO (topology-aware placement)
7. **Level 6:** SCHEDULE (time-aware scheduling)
8. **Level 7:** PULSE (pulse-level representation)
9. **Level 8:** EXEC (executable backend package)

**Example:**
```rust
use qataaum_ir::{IrBuilder, cfg::CfgBuilder, ssa::SsaBuilder};

// Build typed IR
let mut ir_builder = IrBuilder::new();
let typed_ir = ir_builder.build(&ast)?;

// Build CFG
let mut cfg_builder = CfgBuilder::new();
let cfg = cfg_builder.build(&typed_ir)?;

// Build SSA
let mut ssa_builder = SsaBuilder::new();
let ssa = ssa_builder.build(&cfg)?;
```

### Optimization Passes

#### `qataaum_passes::Pass`

Base trait for optimization passes.

```rust
pub trait Pass {
    type Input;
    type Output;
    
    /// Run the optimization pass
    fn run(&self, input: Self::Input) -> Result<Self::Output, PassError>;
}
```

#### `qataaum_passes::GateCancellationPass`

Eliminates inverse gate pairs.

```rust
pub struct GateCancellationPass;

impl GateCancellationPass {
    pub fn new() -> Self;
}

impl Pass for GateCancellationPass {
    type Input = GateIr;
    type Output = GateIr;
    
    fn run(&self, input: Self::Input) -> Result<Self::Output, PassError>;
}
```

**Example:**
```rust
use qataaum_passes::{GateCancellationPass, Pass};

let pass = GateCancellationPass::new();
let optimized = pass.run(gate_ir)?;
```

#### `qataaum_passes::RotationFoldingPass`

Combines consecutive rotation gates.

```rust
pub struct RotationFoldingPass;

impl RotationFoldingPass {
    pub fn new() -> Self;
}
```

**Example:**
```rust
use qataaum_passes::{RotationFoldingPass, Pass};

let pass = RotationFoldingPass::new();
let optimized = pass.run(gate_ir)?;
```

### Routing Module

#### `qataaum_routing::SabreRouter`

SABRE-inspired routing algorithm for qubit placement.

```rust
pub struct SabreRouter {
    topology: Topology,
    heuristic_weight: f64,
}

impl SabreRouter {
    /// Create router with linear topology
    pub fn new_linear(num_qubits: usize) -> Self;
    
    /// Create router with custom topology
    pub fn new(topology: Topology) -> Self;
    
    /// Route a circuit to the topology
    pub fn route(&mut self, circuit: &GateIr) -> Result<RoutedCircuit, RoutingError>;
}
```

**Example:**
```rust
use qataaum_routing::SabreRouter;

let mut router = SabreRouter::new_linear(5);
let routed = router.route(&gate_ir)?;
```

---

## Simulator API

### State Vector Simulator

#### `qataaum_simulator::StateVectorSimulator`

Exact state vector simulation.

```rust
pub struct StateVectorSimulator {
    num_qubits: usize,
    state: Vec<Complex64>,
}

impl StateVectorSimulator {
    /// Create a new simulator with n qubits (initialized to |0⟩)
    pub fn new(num_qubits: usize) -> Self;
    
    /// Apply Hadamard gate
    pub fn h(&mut self, qubit: usize) -> Result<(), SimulatorError>;
    
    /// Apply Pauli-X gate
    pub fn x(&mut self, qubit: usize) -> Result<(), SimulatorError>;
    
    /// Apply Pauli-Y gate
    pub fn y(&mut self, qubit: usize) -> Result<(), SimulatorError>;
    
    /// Apply Pauli-Z gate
    pub fn z(&mut self, qubit: usize) -> Result<(), SimulatorError>;
    
    /// Apply CNOT gate
    pub fn cx(&mut self, control: usize, target: usize) -> Result<(), SimulatorError>;
    
    /// Apply rotation-X gate
    pub fn rx(&mut self, qubit: usize, theta: f64) -> Result<(), SimulatorError>;
    
    /// Apply rotation-Y gate
    pub fn ry(&mut self, qubit: usize, theta: f64) -> Result<(), SimulatorError>;
    
    /// Apply rotation-Z gate
    pub fn rz(&mut self, qubit: usize, theta: f64) -> Result<(), SimulatorError>;
    
    /// Apply controlled-phase gate
    pub fn cp(&mut self, control: usize, target: usize, theta: f64) -> Result<(), SimulatorError>;
    
    /// Measure a qubit (collapses state)
    pub fn measure(&mut self, qubit: usize) -> Result<bool, SimulatorError>;
    
    /// Get probability of measuring |1⟩ on a qubit
    pub fn probability(&self, qubit: usize) -> Result<f64, SimulatorError>;
    
    /// Get the full state vector
    pub fn state(&self) -> &[Complex64];
    
    /// Reset to |0⟩ state
    pub fn reset(&mut self);
}
```

**Example:**
```rust
use qataaum_simulator::StateVectorSimulator;

let mut sim = StateVectorSimulator::new(2);
sim.h(0)?;
sim.cx(0, 1)?;
let result = sim.measure(0)?;
```

### Density Matrix Simulator

#### `qataaum_simulator::DensityMatrixSimulator`

Mixed-state simulation with noise support.

```rust
pub struct DensityMatrixSimulator {
    num_qubits: usize,
    density_matrix: Array2<Complex64>,
}

impl DensityMatrixSimulator {
    /// Create a new simulator with n qubits
    pub fn new(num_qubits: usize) -> Self;
    
    /// Apply single-qubit gates (same as StateVectorSimulator)
    pub fn h(&mut self, qubit: usize) -> Result<(), SimulatorError>;
    pub fn x(&mut self, qubit: usize) -> Result<(), SimulatorError>;
    pub fn y(&mut self, qubit: usize) -> Result<(), SimulatorError>;
    pub fn z(&mut self, qubit: usize) -> Result<(), SimulatorError>;
    
    /// Apply two-qubit gates
    pub fn cx(&mut self, control: usize, target: usize) -> Result<(), SimulatorError>;
    pub fn cp(&mut self, control: usize, target: usize, theta: f64) -> Result<(), SimulatorError>;
    
    /// Apply noise channels
    pub fn apply_depolarizing_noise(&mut self, qubit: usize, p: f64) -> Result<(), SimulatorError>;
    pub fn apply_amplitude_damping(&mut self, qubit: usize, gamma: f64) -> Result<(), SimulatorError>;
    pub fn apply_phase_damping(&mut self, qubit: usize, gamma: f64) -> Result<(), SimulatorError>;
    
    /// Measure a qubit
    pub fn measure(&mut self, qubit: usize) -> Result<bool, SimulatorError>;
    
    /// Get the density matrix
    pub fn density_matrix(&self) -> &Array2<Complex64>;
    
    /// Calculate purity
    pub fn purity(&self) -> f64;
    
    /// Reset to |0⟩ state
    pub fn reset(&mut self);
}
```

**Example:**
```rust
use qataaum_simulator::DensityMatrixSimulator;

let mut sim = DensityMatrixSimulator::new(2);
sim.h(0)?;
sim.apply_depolarizing_noise(0, 0.01)?;
sim.cx(0, 1)?;
let purity = sim.purity();
```

---

## Runtime API

### Job Management

#### `shadow_rpg_q::Job`

Represents a quantum job.

```rust
pub struct Job {
    id: String,
    source: String,
    target: String,
    priority: u8,
    created_at: SystemTime,
}

impl Job {
    /// Create a new job
    pub fn new(id: &str, source: &str, target: &str, priority: u8) -> Self;
    
    /// Get job ID
    pub fn id(&self) -> &str;
    
    /// Get source code
    pub fn source(&self) -> &str;
    
    /// Get target backend
    pub fn target(&self) -> &str;
    
    /// Get priority (0-9, higher is more urgent)
    pub fn priority(&self) -> u8;
    
    /// Get creation timestamp
    pub fn created_at(&self) -> SystemTime;
}
```

**Example:**
```rust
use shadow_rpg_q::Job;

let job = Job::new(
    "job-001",
    "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];",
    "simulator",
    5
);
```

### Queue Management

#### `shadow_rpg_q::JobQueue`

Priority queue for job scheduling.

```rust
pub struct JobQueue {
    jobs: BinaryHeap<PriorityJob>,
}

impl JobQueue {
    /// Create a new empty queue
    pub fn new() -> Self;
    
    /// Enqueue a job
    pub fn enqueue(&mut self, job: Job) -> Result<(), QueueError>;
    
    /// Dequeue the highest priority job
    pub fn dequeue(&mut self) -> Result<Job, QueueError>;
    
    /// Get queue length
    pub fn len(&self) -> usize;
    
    /// Check if queue is empty
    pub fn is_empty(&self) -> bool;
}
```

**Example:**
```rust
use shadow_rpg_q::{Job, JobQueue};

let mut queue = JobQueue::new();
let job = Job::new("job-001", source, "simulator", 5);
queue.enqueue(job)?;
let next_job = queue.dequeue()?;
```

### Journal

#### `shadow_rpg_q::Journal`

Append-only audit log for job state transitions.

```rust
pub struct Journal {
    entries: Vec<JournalEntry>,
}

impl Journal {
    /// Create a new journal
    pub fn new() -> Self;
    
    /// Write a journal entry
    pub fn write_entry(&mut self, state: &str, job: &Job, message: &str) -> Result<(), JournalError>;
    
    /// Read all entries for a job
    pub fn read_entries(&self, job_id: &str) -> Result<Vec<&JournalEntry>, JournalError>;
    
    /// Get total entry count
    pub fn len(&self) -> usize;
}
```

**Example:**
```rust
use shadow_rpg_q::Journal;

let mut journal = Journal::new();
journal.write_entry("RECEIVED", &job, "Job received")?;
journal.write_entry("COMPILED", &job, "Compilation complete")?;
let entries = journal.read_entries("job-001")?;
```

### Receipt

#### `shadow_rpg_q::Receipt`

Cryptographically sealed execution receipt.

```rust
pub struct Receipt {
    job_id: String,
    state: String,
    message: String,
    timestamp: SystemTime,
    hash: Option<String>,
}

impl Receipt {
    /// Create a new receipt
    pub fn new(job: &Job, state: &str, message: &str) -> Self;
    
    /// Seal the receipt with a cryptographic hash
    pub fn seal(&mut self) -> Result<(), ReceiptError>;
    
    /// Verify receipt integrity
    pub fn verify(&self) -> Result<bool, ReceiptError>;
    
    /// Get receipt hash
    pub fn hash(&self) -> Option<&str>;
}
```

**Example:**
```rust
use shadow_rpg_q::Receipt;

let mut receipt = Receipt::new(&job, "COMPLETED", "Success");
receipt.seal()?;
let is_valid = receipt.verify()?;
```

### Executor

#### `shadow_rpg_q::Executor`

Job execution orchestrator.

```rust
pub struct Executor {
    compiler: Compiler,
    simulator: Box<dyn Simulator>,
}

impl Executor {
    /// Create a new executor
    pub fn new() -> Self;
    
    /// Execute a job
    pub fn execute(&mut self, job: Job) -> Result<ExecutionResult, ExecutorError>;
}
```

**Example:**
```rust
use shadow_rpg_q::{Job, Executor};

let mut executor = Executor::new();
let job = Job::new("job-001", source, "simulator", 5);
let result = executor.execute(job)?;
```

---

## FFI API

### C-Compatible Interface

#### `qataaum_ibmi_ffi`

C-compatible FFI for IBM i integration.

```c
// Opaque handle types
typedef struct QataaumCompiler QataaumCompiler;
typedef struct QataaumSimulator QataaumSimulator;
typedef struct QataaumJob QataaumJob;

// Compiler functions
QataaumCompiler* qataaum_compiler_new(void);
void qataaum_compiler_free(QataaumCompiler* compiler);
int qataaum_compiler_compile(
    QataaumCompiler* compiler,
    const char* source,
    size_t source_len,
    char** output,
    size_t* output_len
);

// Simulator functions
QataaumSimulator* qataaum_simulator_new(size_t num_qubits);
void qataaum_simulator_free(QataaumSimulator* sim);
int qataaum_simulator_apply_h(QataaumSimulator* sim, size_t qubit);
int qataaum_simulator_apply_cx(QataaumSimulator* sim, size_t control, size_t target);
int qataaum_simulator_measure(QataaumSimulator* sim, size_t qubit, int* result);

// Job functions
QataaumJob* qataaum_job_new(
    const char* id,
    const char* source,
    const char* target,
    uint8_t priority
);
void qataaum_job_free(QataaumJob* job);
int qataaum_job_execute(QataaumJob* job, char** result, size_t* result_len);
```

**RPG Example:**
```rpg
DCL-PR qataaum_compiler_new POINTER EXTPROC(*CWIDEN:'qataaum_compiler_new');
END-PR;

DCL-PR qataaum_compiler_compile INT(10) EXTPROC(*CWIDEN:'qataaum_compiler_compile');
  compiler POINTER VALUE;
  source POINTER VALUE;
  source_len UNS(10) VALUE;
  output POINTER;
  output_len POINTER;
END-PR;

DCL-S compiler POINTER;
DCL-S source CHAR(1000);
DCL-S output POINTER;
DCL-S output_len UNS(10);

compiler = qataaum_compiler_new();
source = 'OPENQASM 2.0; qreg q[2]; h q[0];';
qataaum_compiler_compile(compiler: %ADDR(source): %LEN(source): %ADDR(output): %ADDR(output_len));
```

---

## Error Handling

All fallible operations return `Result<T, E>` types:

### Error Types

```rust
// Parser errors
pub enum LexerError {
    UnexpectedCharacter(char, usize),
    UnterminatedString(usize),
}

pub enum ParseError {
    UnexpectedToken(Token),
    UnexpectedEof,
    InvalidSyntax(String),
}

// Semantic errors
pub enum SemanticError {
    UndeclaredVariable(String),
    TypeMismatch { expected: Type, found: Type },
    InvalidOperation(String),
}

// IR errors
pub enum IrError {
    InvalidTransformation(String),
    UnsupportedFeature(String),
}

// Simulator errors
pub enum SimulatorError {
    InvalidQubit(usize),
    InvalidParameter(String),
    MeasurementError(String),
}

// Runtime errors
pub enum ExecutorError {
    CompilationFailed(String),
    SimulationFailed(String),
    InvalidJob(String),
}
```

### Error Handling Pattern

```rust
use qataaum_parser::{Lexer, Parser};

fn compile_circuit(source: &str) -> Result<Program, Box<dyn std::error::Error>> {
    let mut lexer = Lexer::new(source);
    let tokens = lexer.tokenize()?;
    let mut parser = Parser::new(tokens);
    let ast = parser.parse()?;
    Ok(ast)
}

match compile_circuit(source) {
    Ok(program) => println!("Success!"),
    Err(e) => eprintln!("Error: {}", e),
}
```

---

## Examples

### Complete Compilation Pipeline

```rust
use qataaum_parser::{Lexer, Parser};
use qataaum_semantic::SemanticAnalyzer;
use qataaum_ir::{IrBuilder, gate::GateIrBuilder};
use qataaum_passes::{GateCancellationPass, Pass};
use qataaum_routing::SabreRouter;

fn compile_and_route(source: &str) -> Result<RoutedCircuit, Box<dyn std::error::Error>> {
    // Parse
    let mut lexer = Lexer::new(source);
    let tokens = lexer.tokenize()?;
    let mut parser = Parser::new(tokens);
    let ast = parser.parse()?;
    
    // Semantic analysis
    let mut analyzer = SemanticAnalyzer::new();
    analyzer.analyze(&ast)?;
    
    // Build IR
    let mut ir_builder = IrBuilder::new();
    let ir = ir_builder.build(&ast)?;
    
    // Build Gate IR
    let mut gate_builder = GateIrBuilder::new();
    let mut gate_ir = gate_builder.build(&ir)?;
    
    // Optimize
    let pass = GateCancellationPass::new();
    gate_ir = pass.run(gate_ir)?;
    
    // Route
    let num_qubits = gate_ir.num_qubits();
    let mut router = SabreRouter::new_linear(num_qubits);
    let routed = router.route(&gate_ir)?;
    
    Ok(routed)
}
```

### Simulation with Noise

```rust
use qataaum_simulator::DensityMatrixSimulator;

fn simulate_with_noise() -> Result<f64, SimulatorError> {
    let mut sim = DensityMatrixSimulator::new(2);
    
    // Create Bell state with noise
    sim.h(0)?;
    sim.apply_depolarizing_noise(0, 0.01)?;
    sim.cx(0, 1)?;
    sim.apply_depolarizing_noise(1, 0.01)?;
    
    // Calculate purity
    let purity = sim.purity();
    Ok(purity)
}
```

### Job Execution Workflow

```rust
use shadow_rpg_q::{Job, JobQueue, Journal, Receipt, Executor};

fn execute_workflow(source: &str) -> Result<Receipt, Box<dyn std::error::Error>> {
    // Create job
    let job = Job::new("job-001", source, "simulator", 5);
    
    // Enqueue
    let mut queue = JobQueue::new();
    queue.enqueue(job.clone())?;
    
    // Journal
    let mut journal = Journal::new();
    journal.write_entry("RECEIVED", &job, "Job received")?;
    
    // Execute
    let mut executor = Executor::new();
    let result = executor.execute(job.clone())?;
    
    journal.write_entry("COMPLETED", &job, "Execution complete")?;
    
    // Create and seal receipt
    let mut receipt = Receipt::new(&job, "COMPLETED", "Success");
    receipt.seal()?;
    
    Ok(receipt)
}
```

---

## API Stability

- **Stable:** Parser, Semantic, IR, Simulator, Runtime core APIs
- **Experimental:** Pulse compiler, advanced optimization passes
- **Internal:** IR transformation details, routing heuristics

Breaking changes will be documented in release notes.

---

**Generated:** 2026-07-22  
**Version:** 1.0  
**License:** Apache-2.0