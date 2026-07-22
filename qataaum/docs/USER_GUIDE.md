# QATAAUM User Guide

**Project:** QATAAUM Quantum Assembly Runtime  
**Version:** 1.0  
**Date:** 2026-07-22

## Table of Contents

1. [Introduction](#introduction)
2. [Getting Started](#getting-started)
3. [Writing Quantum Circuits](#writing-quantum-circuits)
4. [Compiling Circuits](#compiling-circuits)
5. [Running Simulations](#running-simulations)
6. [Job Management](#job-management)
7. [Advanced Topics](#advanced-topics)
8. [Troubleshooting](#troubleshooting)

---

## Introduction

QATAAUM (Quantum Assembly Runtime) is a clean-room quantum compiler and runtime system that supports:

- **OpenQASM 2.0** - Industry-standard quantum assembly language
- **OpenQASM 3.x** - Extended quantum assembly with classical control
- **MetaQASM-4** - Experimental language with typed effects and formal verification
- **ShadowRPG-Q** - IBM i-style job control language

### Key Features

- **9-Level IR Pipeline** - Comprehensive compilation from source to executable
- **Optimization Passes** - Gate cancellation, rotation folding, and more
- **State Vector Simulator** - Exact simulation up to 12-14 qubits
- **Density Matrix Simulator** - Mixed-state simulation with noise modeling
- **Formal Verification** - Liquid Haskell refinements and Lean 4 proofs
- **IBM i Integration** - C FFI for RPG, COBOL, and CL interoperability

### What QATAAUM Is NOT

- **Not an IBM product** - Independent clean-room implementation
- **Not official OpenQASM 4** - MetaQASM-4 is an experimental language
- **Not affiliated with Qiskit** - Compatible but independently developed

---

## Getting Started

### Prerequisites

- **Rust** 1.70 or later
- **Cargo** (included with Rust)
- **Git** for cloning the repository

Optional:
- **Liquid Haskell** for refinement verification
- **Lean 4** for theorem proving
- **IBM i** for native RPG integration

### Installation

```bash
# Clone the repository
git clone https://github.com/your-org/qataaum.git
cd qataaum

# Build the project
cargo build --release

# Run tests
cargo test

# Run benchmarks
cargo bench
```

### Quick Start Example

Create a file `bell_state.qasm`:

```qasm
OPENQASM 2.0;
qreg q[2];
creg c[2];

h q[0];
cx q[0],q[1];
measure q -> c;
```

Compile and simulate:

```rust
use qataaum_parser::{Lexer, Parser};
use qataaum_simulator::StateVectorSimulator;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Read source
    let source = std::fs::read_to_string("bell_state.qasm")?;
    
    // Parse
    let mut lexer = Lexer::new(&source);
    let tokens = lexer.tokenize()?;
    let mut parser = Parser::new(tokens);
    let ast = parser.parse()?;
    
    // Simulate
    let mut sim = StateVectorSimulator::new(2);
    sim.h(0)?;
    sim.cx(0, 1)?;
    
    println!("Bell state created!");
    Ok(())
}
```

---

## Writing Quantum Circuits

### OpenQASM 2.0 Basics

#### Quantum Registers

```qasm
OPENQASM 2.0;

// Declare quantum registers
qreg q[5];      // 5 qubits named q[0] through q[4]
qreg ancilla[2]; // 2 ancilla qubits

// Declare classical registers
creg c[5];      // 5 classical bits
```

#### Single-Qubit Gates

```qasm
// Pauli gates
x q[0];         // Pauli-X (NOT gate)
y q[1];         // Pauli-Y
z q[2];         // Pauli-Z

// Hadamard gate
h q[0];         // Create superposition

// Rotation gates
rx(pi/4) q[0];  // Rotate around X-axis
ry(pi/4) q[1];  // Rotate around Y-axis
rz(pi/4) q[2];  // Rotate around Z-axis

// Phase gates
s q[0];         // S gate (√Z)
t q[1];         // T gate (√S)
sdg q[2];       // S† gate
tdg q[3];       // T† gate
```

#### Two-Qubit Gates

```qasm
// CNOT (controlled-NOT)
cx q[0],q[1];   // Control: q[0], Target: q[1]

// Controlled-Z
cz q[0],q[1];

// Controlled-phase
cp(pi/4) q[0],q[1];

// SWAP
swap q[0],q[1];
```

#### Measurement

```qasm
// Measure single qubit
measure q[0] -> c[0];

// Measure all qubits
measure q -> c;
```

### Common Circuit Patterns

#### Bell State (Entanglement)

```qasm
OPENQASM 2.0;
qreg q[2];
creg c[2];

h q[0];
cx q[0],q[1];
measure q -> c;
```

#### GHZ State (3-qubit entanglement)

```qasm
OPENQASM 2.0;
qreg q[3];
creg c[3];

h q[0];
cx q[0],q[1];
cx q[1],q[2];
measure q -> c;
```

#### Quantum Fourier Transform (3 qubits)

```qasm
OPENQASM 2.0;
qreg q[3];

h q[0];
cp(pi/2) q[0],q[1];
cp(pi/4) q[0],q[2];
h q[1];
cp(pi/2) q[1],q[2];
h q[2];
swap q[0],q[2];
```

#### Grover's Algorithm (2 qubits)

```qasm
OPENQASM 2.0;
qreg q[2];
creg c[2];

// Initialize superposition
h q[0];
h q[1];

// Oracle (mark |11⟩)
cz q[0],q[1];

// Diffusion operator
h q[0];
h q[1];
x q[0];
x q[1];
cz q[0],q[1];
x q[0];
x q[1];
h q[0];
h q[1];

measure q -> c;
```

---

## Compiling Circuits

### Compilation Pipeline

QATAAUM uses a 9-level IR pipeline:

1. **Source AST** - Lossless syntax representation
2. **Typed AST** - Resolved names, types, effects
3. **CFG** - Control-flow graph
4. **SSA** - Static single assignment
5. **GATE** - Hardware-independent gates
6. **TOPO** - Topology-aware placement
7. **SCHEDULE** - Time-aware scheduling
8. **PULSE** - Pulse-level representation
9. **EXEC** - Executable backend package

### Basic Compilation

```rust
use qataaum_parser::{Lexer, Parser};
use qataaum_semantic::SemanticAnalyzer;
use qataaum_ir::{IrBuilder, gate::GateIrBuilder};

fn compile(source: &str) -> Result<(), Box<dyn std::error::Error>> {
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
    let gate_ir = gate_builder.build(&ir)?;
    
    println!("Compilation successful!");
    println!("Gates: {}", gate_ir.num_gates());
    println!("Qubits: {}", gate_ir.num_qubits());
    
    Ok(())
}
```

### Optimization

```rust
use qataaum_passes::{GateCancellationPass, RotationFoldingPass, Pass};

fn optimize(mut gate_ir: GateIr) -> Result<GateIr, Box<dyn std::error::Error>> {
    let initial_gates = gate_ir.num_gates();
    
    // Gate cancellation
    let cancel_pass = GateCancellationPass::new();
    gate_ir = cancel_pass.run(gate_ir)?;
    
    // Rotation folding
    let fold_pass = RotationFoldingPass::new();
    gate_ir = fold_pass.run(gate_ir)?;
    
    let final_gates = gate_ir.num_gates();
    println!("Optimized: {} -> {} gates", initial_gates, final_gates);
    
    Ok(gate_ir)
}
```

### Routing

```rust
use qataaum_routing::SabreRouter;

fn route(gate_ir: &GateIr) -> Result<RoutedCircuit, Box<dyn std::error::Error>> {
    let num_qubits = gate_ir.num_qubits();
    
    // Create router with linear topology
    let mut router = SabreRouter::new_linear(num_qubits);
    
    // Route the circuit
    let routed = router.route(gate_ir)?;
    
    println!("Routing complete!");
    println!("SWAPs added: {}", routed.num_swaps());
    
    Ok(routed)
}
```

---

## Running Simulations

### State Vector Simulation

Best for pure-state circuits (up to 12-14 qubits).

```rust
use qataaum_simulator::StateVectorSimulator;

fn simulate_bell_state() -> Result<(), Box<dyn std::error::Error>> {
    let mut sim = StateVectorSimulator::new(2);
    
    // Create Bell state
    sim.h(0)?;
    sim.cx(0, 1)?;
    
    // Measure
    let result0 = sim.measure(0)?;
    let result1 = sim.measure(1)?;
    
    println!("Measured: {} {}", result0 as u8, result1 as u8);
    
    Ok(())
}
```

### Density Matrix Simulation

Required for mixed states and noise modeling (up to 6-8 qubits).

```rust
use qataaum_simulator::DensityMatrixSimulator;

fn simulate_with_noise() -> Result<(), Box<dyn std::error::Error>> {
    let mut sim = DensityMatrixSimulator::new(2);
    
    // Create Bell state with noise
    sim.h(0)?;
    sim.apply_depolarizing_noise(0, 0.01)?;
    sim.cx(0, 1)?;
    sim.apply_depolarizing_noise(1, 0.01)?;
    
    // Check purity
    let purity = sim.purity();
    println!("Purity: {:.4}", purity);
    
    // Measure
    let result0 = sim.measure(0)?;
    let result1 = sim.measure(1)?;
    
    println!("Measured: {} {}", result0 as u8, result1 as u8);
    
    Ok(())
}
```

### Noise Models

#### Depolarizing Noise

```rust
// Apply depolarizing noise with probability p
sim.apply_depolarizing_noise(qubit, 0.01)?;
```

#### Amplitude Damping

```rust
// Apply amplitude damping with rate gamma
sim.apply_amplitude_damping(qubit, 0.05)?;
```

#### Phase Damping

```rust
// Apply phase damping with rate gamma
sim.apply_phase_damping(qubit, 0.03)?;
```

### Multiple Shots

```rust
fn run_multiple_shots(num_shots: usize) -> Result<Vec<(bool, bool)>, Box<dyn std::error::Error>> {
    let mut results = Vec::new();
    
    for _ in 0..num_shots {
        let mut sim = StateVectorSimulator::new(2);
        sim.h(0)?;
        sim.cx(0, 1)?;
        
        let r0 = sim.measure(0)?;
        let r1 = sim.measure(1)?;
        results.push((r0, r1));
    }
    
    Ok(results)
}
```

---

## Job Management

### Creating Jobs

```rust
use shadow_rpg_q::Job;

let job = Job::new(
    "job-001",                              // Job ID
    "OPENQASM 2.0; qreg q[2]; h q[0];",    // Source code
    "simulator",                            // Target backend
    5                                       // Priority (0-9)
);
```

### Queue Management

```rust
use shadow_rpg_q::{Job, JobQueue};

let mut queue = JobQueue::new();

// Enqueue jobs
let job1 = Job::new("job-001", source1, "simulator", 5);
let job2 = Job::new("job-002", source2, "simulator", 8);
queue.enqueue(job1)?;
queue.enqueue(job2)?;

// Dequeue highest priority job
let next_job = queue.dequeue()?;
```

### Journal and Audit

```rust
use shadow_rpg_q::Journal;

let mut journal = Journal::new();

// Write entries
journal.write_entry("RECEIVED", &job, "Job received")?;
journal.write_entry("COMPILED", &job, "Compilation complete")?;
journal.write_entry("EXECUTING", &job, "Simulation started")?;
journal.write_entry("COMPLETED", &job, "Success")?;

// Read entries
let entries = journal.read_entries("job-001")?;
for entry in entries {
    println!("{:?}", entry);
}
```

### Execution Receipts

```rust
use shadow_rpg_q::Receipt;

// Create receipt
let mut receipt = Receipt::new(&job, "COMPLETED", "Success");

// Seal with cryptographic hash
receipt.seal()?;

// Verify integrity
let is_valid = receipt.verify()?;
println!("Receipt valid: {}", is_valid);
```

### Complete Workflow

```rust
use shadow_rpg_q::{Job, JobQueue, Journal, Receipt, Executor};

fn execute_workflow(source: &str) -> Result<(), Box<dyn std::error::Error>> {
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
    
    // Create receipt
    let mut receipt = Receipt::new(&job, "COMPLETED", "Success");
    receipt.seal()?;
    
    println!("Workflow complete!");
    println!("Receipt hash: {:?}", receipt.hash());
    
    Ok(())
}
```

---

## Advanced Topics

### MetaQASM-4 (Experimental)

MetaQASM-4 adds typed effects and formal verification:

```metaqasm
// Type-safe qubit ownership
qubit[2] q;

// Effect-typed operations
effect Measure {
    let result: bit = measure q[0];
}

// Refinement constraints
constraint linear_ownership(q);
constraint no_cloning(q);
```

### ShadowRPG-Q Job Control

IBM i-style job control language:

```shadowrpg
JOB ID(JOB001) PRIORITY(5)
SOURCE('bell_state.qasm')
TARGET(SIMULATOR)
SHOTS(1000)
OPTIMIZE(YES)
JOURNAL(YES)
RECEIPT(YES)
SUBMIT
```

### Formal Verification

#### Liquid Haskell Refinements

```haskell
{-@ type ValidQubit N = {v:Int | 0 <= v && v < N} @-}

{-@ applyGate :: n:Nat -> ValidQubit n -> Circuit -> Circuit @-}
applyGate :: Int -> Int -> Circuit -> Circuit
```

#### Lean 4 Theorems

```lean
theorem gate_cancellation_preserves_semantics :
  ∀ (c : Circuit), semantics c = semantics (cancel_gates c) := by
  intro c
  -- Proof
```

### Custom Optimization Passes

```rust
use qataaum_passes::Pass;

struct MyCustomPass;

impl Pass for MyCustomPass {
    type Input = GateIr;
    type Output = GateIr;
    
    fn run(&self, input: Self::Input) -> Result<Self::Output, PassError> {
        // Custom optimization logic
        Ok(input)
    }
}
```

### IBM i FFI Integration

```c
// C interface
#include "qataaum_ibmi_ffi.h"

QataaumCompiler* compiler = qataaum_compiler_new();
char* output;
size_t output_len;

int result = qataaum_compiler_compile(
    compiler,
    source,
    strlen(source),
    &output,
    &output_len
);

qataaum_compiler_free(compiler);
```

```rpg
// RPG interface
DCL-PR qataaum_compiler_new POINTER EXTPROC(*CWIDEN:'qataaum_compiler_new');
END-PR;

DCL-S compiler POINTER;
compiler = qataaum_compiler_new();
```

---

## Troubleshooting

### Common Errors

#### Parse Error: Unexpected Token

```
Error: unexpected token 'qreg' at line 2
```

**Solution:** Check OpenQASM version declaration:
```qasm
OPENQASM 2.0;  // Required first line
qreg q[2];
```

#### Semantic Error: Undeclared Variable

```
Error: undeclared variable 'q'
```

**Solution:** Declare registers before use:
```qasm
OPENQASM 2.0;
qreg q[2];     // Declare first
h q[0];        // Then use
```

#### Simulator Error: Invalid Qubit

```
Error: qubit index 5 out of bounds (max: 2)
```

**Solution:** Check qubit indices:
```rust
let mut sim = StateVectorSimulator::new(2);  // 2 qubits: 0, 1
sim.h(0)?;  // OK
sim.h(2)?;  // Error: only 0 and 1 are valid
```

#### Routing Error: No Valid Route

```
Error: cannot route gate cx(0,4) on linear topology
```

**Solution:** Use appropriate topology or add SWAP gates manually.

### Performance Issues

#### Slow Compilation

- Enable release mode: `cargo build --release`
- Reduce optimization passes
- Use incremental compilation

#### Slow Simulation

- Use state vector for pure states
- Reduce qubit count (exponential scaling)
- Consider approximate simulation methods

#### Memory Issues

- State vector: 2^n complex numbers (16 bytes each)
- Density matrix: 4^n complex numbers
- Limit: ~12-14 qubits (state vector), ~6-8 qubits (density matrix)

### Getting Help

- **Documentation:** See `docs/` directory
- **API Reference:** `docs/API_REFERENCE.md`
- **Architecture:** `PUBLIC_ARCHITECTURE_REPORT.md`
- **Issues:** GitHub issue tracker
- **Community:** Project discussion forum

---

## Best Practices

1. **Start Small:** Test with 2-3 qubits before scaling up
2. **Validate Early:** Use semantic analyzer to catch errors
3. **Optimize Wisely:** Profile before optimizing
4. **Test Thoroughly:** Use property-based testing
5. **Document Circuits:** Add comments to complex circuits
6. **Version Control:** Track circuit changes
7. **Benchmark:** Measure performance regularly
8. **Verify:** Use formal verification for critical circuits

---

**Generated:** 2026-07-22  
**Version:** 1.0  
**License:** Apache-2.0