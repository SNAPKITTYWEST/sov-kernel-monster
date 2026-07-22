# QATAAUM Quick Start Guide

**Get up and running with QATAAUM in 5 minutes**

## Installation

```bash
# Clone repository
git clone https://github.com/your-org/qataaum.git
cd qataaum

# Build
cargo build --release

# Test
cargo test
```

## Your First Quantum Circuit

### 1. Create a Bell State

Create `bell.qasm`:

```qasm
OPENQASM 2.0;
qreg q[2];
creg c[2];

h q[0];
cx q[0],q[1];
measure q -> c;
```

### 2. Compile and Simulate

Create `main.rs`:

```rust
use qataaum_parser::{Lexer, Parser};
use qataaum_simulator::StateVectorSimulator;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Read circuit
    let source = std::fs::read_to_string("bell.qasm")?;
    
    // Parse
    let mut lexer = Lexer::new(&source);
    let tokens = lexer.tokenize()?;
    let mut parser = Parser::new(tokens);
    let _ast = parser.parse()?;
    
    // Simulate
    let mut sim = StateVectorSimulator::new(2);
    sim.h(0)?;
    sim.cx(0, 1)?;
    
    // Measure
    let r0 = sim.measure(0)?;
    let r1 = sim.measure(1)?;
    
    println!("Measured: {} {}", r0 as u8, r1 as u8);
    Ok(())
}
```

### 3. Run

```bash
cargo run --release
```

Output:
```
Measured: 0 0  (or 1 1 - entangled!)
```

## Common Circuits

### GHZ State (3-qubit entanglement)

```qasm
OPENQASM 2.0;
qreg q[3];

h q[0];
cx q[0],q[1];
cx q[1],q[2];
```

```rust
let mut sim = StateVectorSimulator::new(3);
sim.h(0)?;
sim.cx(0, 1)?;
sim.cx(1, 2)?;
```

### Quantum Teleportation

```qasm
OPENQASM 2.0;
qreg q[3];
creg c[2];

// Prepare Bell pair
h q[1];
cx q[1],q[2];

// Alice's operations
cx q[0],q[1];
h q[0];
measure q[0] -> c[0];
measure q[1] -> c[1];

// Bob's corrections (conditional)
if(c[1]==1) x q[2];
if(c[0]==1) z q[2];
```

### Grover's Algorithm

```qasm
OPENQASM 2.0;
qreg q[2];

// Superposition
h q[0];
h q[1];

// Oracle
cz q[0],q[1];

// Diffusion
h q[0];
h q[1];
x q[0];
x q[1];
cz q[0],q[1];
x q[0];
x q[1];
h q[0];
h q[1];
```

## Job Management

```rust
use shadow_rpg_q::{Job, Executor};

// Create job
let job = Job::new(
    "my-job",
    "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];",
    "simulator",
    5
);

// Execute
let mut executor = Executor::new();
let result = executor.execute(job)?;
```

## Optimization

```rust
use qataaum_passes::{GateCancellationPass, Pass};

// Optimize circuit
let pass = GateCancellationPass::new();
let optimized = pass.run(gate_ir)?;
```

## Noise Simulation

```rust
use qataaum_simulator::DensityMatrixSimulator;

let mut sim = DensityMatrixSimulator::new(2);
sim.h(0)?;
sim.apply_depolarizing_noise(0, 0.01)?;
sim.cx(0, 1)?;
```

## Next Steps

- **Full Guide:** See `docs/USER_GUIDE.md`
- **API Reference:** See `docs/API_REFERENCE.md`
- **Examples:** See `examples/` directory
- **Architecture:** See `PUBLIC_ARCHITECTURE_REPORT.md`

## Need Help?

- Check `docs/USER_GUIDE.md` for detailed documentation
- See `docs/API_REFERENCE.md` for API details
- Review examples in `examples/` directory
- Open an issue on GitHub

---

**Happy Quantum Computing!** 🚀