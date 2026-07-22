//! Simulator Performance Benchmarks

use criterion::{black_box, criterion_group, criterion_main, Criterion, BenchmarkId, Throughput};
use qataaum_simulator::{StateVectorSimulator, DensityMatrixSimulator, Simulator};
use qataaum_parser::{Lexer, Parser};
use qataaum_ir::IrBuilder;
use qataaum_ir::gate::GateIrBuilder;
use num_complex::Complex64;

fn benchmark_state_vector_gates(c: &mut Criterion) {
    let mut group = c.benchmark_group("state_vector_gates");
    
    // Single-qubit gates
    group.bench_function("hadamard_1q", |b| {
        b.iter(|| {
            let mut sim = StateVectorSimulator::new(1);
            sim.h(black_box(0)).unwrap()
        });
    });
    
    group.bench_function("pauli_x_1q", |b| {
        b.iter(|| {
            let mut sim = StateVectorSimulator::new(1);
            sim.x(black_box(0)).unwrap()
        });
    });
    
    group.bench_function("rotation_1q", |b| {
        b.iter(|| {
            let mut sim = StateVectorSimulator::new(1);
            sim.rx(black_box(0), black_box(std::f64::consts::PI / 4.0)).unwrap()
        });
    });
    
    // Two-qubit gates
    group.bench_function("cnot_2q", |b| {
        b.iter(|| {
            let mut sim = StateVectorSimulator::new(2);
            sim.cx(black_box(0), black_box(1)).unwrap()
        });
    });
    
    group.finish();
}

fn benchmark_state_vector_scaling(c: &mut Criterion) {
    let mut group = c.benchmark_group("state_vector_scaling");
    
    for num_qubits in [2, 4, 6, 8, 10, 12].iter() {
        let state_size = 1 << num_qubits;
        group.throughput(Throughput::Elements(state_size as u64));
        
        group.bench_with_input(
            BenchmarkId::new("initialization", num_qubits),
            num_qubits,
            |b, &n| {
                b.iter(|| StateVectorSimulator::new(black_box(n)));
            },
        );
        
        group.bench_with_input(
            BenchmarkId::new("hadamard_all", num_qubits),
            num_qubits,
            |b, &n| {
                b.iter(|| {
                    let mut sim = StateVectorSimulator::new(n);
                    for i in 0..n {
                        sim.h(i).unwrap();
                    }
                });
            },
        );
        
        group.bench_with_input(
            BenchmarkId::new("cnot_chain", num_qubits),
            num_qubits,
            |b, &n| {
                b.iter(|| {
                    let mut sim = StateVectorSimulator::new(n);
                    for i in 0..n-1 {
                        sim.cx(i, i+1).unwrap();
                    }
                });
            },
        );
    }
    
    group.finish();
}

fn benchmark_density_matrix_gates(c: &mut Criterion) {
    let mut group = c.benchmark_group("density_matrix_gates");
    
    // Single-qubit gates
    group.bench_function("hadamard_1q", |b| {
        b.iter(|| {
            let mut sim = DensityMatrixSimulator::new(1);
            sim.h(black_box(0)).unwrap()
        });
    });
    
    group.bench_function("pauli_x_1q", |b| {
        b.iter(|| {
            let mut sim = DensityMatrixSimulator::new(1);
            sim.x(black_box(0)).unwrap()
        });
    });
    
    // Two-qubit gates
    group.bench_function("cnot_2q", |b| {
        b.iter(|| {
            let mut sim = DensityMatrixSimulator::new(2);
            sim.cx(black_box(0), black_box(1)).unwrap()
        });
    });
    
    group.finish();
}

fn benchmark_density_matrix_scaling(c: &mut Criterion) {
    let mut group = c.benchmark_group("density_matrix_scaling");
    
    for num_qubits in [2, 3, 4, 5, 6].iter() {
        let matrix_size = 1 << (2 * num_qubits);
        group.throughput(Throughput::Elements(matrix_size as u64));
        
        group.bench_with_input(
            BenchmarkId::new("initialization", num_qubits),
            num_qubits,
            |b, &n| {
                b.iter(|| DensityMatrixSimulator::new(black_box(n)));
            },
        );
        
        group.bench_with_input(
            BenchmarkId::new("hadamard_all", num_qubits),
            num_qubits,
            |b, &n| {
                b.iter(|| {
                    let mut sim = DensityMatrixSimulator::new(n);
                    for i in 0..n {
                        sim.h(i).unwrap();
                    }
                });
            },
        );
    }
    
    group.finish();
}

fn benchmark_circuit_simulation(c: &mut Criterion) {
    let mut group = c.benchmark_group("circuit_simulation");
    
    let test_cases = vec![
        ("bell_state", "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];", 2),
        ("ghz_3", "OPENQASM 2.0; qreg q[3]; h q[0]; cx q[0],q[1]; cx q[1],q[2];", 3),
        ("ghz_5", "OPENQASM 2.0; qreg q[5]; h q[0]; cx q[0],q[1]; cx q[1],q[2]; cx q[2],q[3]; cx q[3],q[4];", 5),
        ("qft_3", "OPENQASM 2.0; qreg q[3]; h q[0]; cp(1.5708) q[0],q[1]; cp(0.7854) q[0],q[2]; h q[1]; cp(1.5708) q[1],q[2]; h q[2];", 3),
    ];
    
    for (name, source, num_qubits) in test_cases {
        // Parse circuit
        let mut lexer = Lexer::new(source);
        let tokens = lexer.tokenize().unwrap();
        let mut parser = Parser::new(tokens);
        let ast = parser.parse().unwrap();
        let mut ir_builder = IrBuilder::new();
        let ir = ir_builder.build(&ast).unwrap();
        let mut gate_builder = GateIrBuilder::new();
        let gate_ir = gate_builder.build(&ir).unwrap();
        
        group.bench_with_input(
            BenchmarkId::new("state_vector", name),
            &(gate_ir.clone(), num_qubits),
            |b, (g, n)| {
                b.iter(|| {
                    let mut sim = StateVectorSimulator::new(*n);
                    for gate in g.gates() {
                        match gate.name() {
                            "h" => sim.h(gate.qubits()[0]).unwrap(),
                            "x" => sim.x(gate.qubits()[0]).unwrap(),
                            "cx" => sim.cx(gate.qubits()[0], gate.qubits()[1]).unwrap(),
                            "cp" => sim.cp(gate.qubits()[0], gate.qubits()[1], gate.params()[0]).unwrap(),
                            _ => {}
                        }
                    }
                });
            },
        );
        
        if num_qubits <= 6 {
            group.bench_with_input(
                BenchmarkId::new("density_matrix", name),
                &(gate_ir.clone(), num_qubits),
                |b, (g, n)| {
                    b.iter(|| {
                        let mut sim = DensityMatrixSimulator::new(*n);
                        for gate in g.gates() {
                            match gate.name() {
                                "h" => sim.h(gate.qubits()[0]).unwrap(),
                                "x" => sim.x(gate.qubits()[0]).unwrap(),
                                "cx" => sim.cx(gate.qubits()[0], gate.qubits()[1]).unwrap(),
                                "cp" => sim.cp(gate.qubits()[0], gate.qubits()[1], gate.params()[0]).unwrap(),
                                _ => {}
                            }
                        }
                    });
                },
            );
        }
    }
    
    group.finish();
}

fn benchmark_measurement(c: &mut Criterion) {
    let mut group = c.benchmark_group("measurement");
    
    for num_qubits in [2, 4, 6, 8, 10].iter() {
        group.bench_with_input(
            BenchmarkId::new("state_vector_single", num_qubits),
            num_qubits,
            |b, &n| {
                b.iter(|| {
                    let mut sim = StateVectorSimulator::new(n);
                    // Create superposition
                    for i in 0..n {
                        sim.h(i).unwrap();
                    }
                    // Measure first qubit
                    sim.measure(black_box(0)).unwrap()
                });
            },
        );
        
        group.bench_with_input(
            BenchmarkId::new("state_vector_all", num_qubits),
            num_qubits,
            |b, &n| {
                b.iter(|| {
                    let mut sim = StateVectorSimulator::new(n);
                    // Create superposition
                    for i in 0..n {
                        sim.h(i).unwrap();
                    }
                    // Measure all qubits
                    for i in 0..n {
                        sim.measure(i).unwrap();
                    }
                });
            },
        );
    }
    
    group.finish();
}

fn benchmark_noise_simulation(c: &mut Criterion) {
    let mut group = c.benchmark_group("noise_simulation");
    
    for num_qubits in [2, 3, 4, 5].iter() {
        group.bench_with_input(
            BenchmarkId::new("depolarizing_channel", num_qubits),
            num_qubits,
            |b, &n| {
                b.iter(|| {
                    let mut sim = DensityMatrixSimulator::new(n);
                    // Apply gates with noise
                    for i in 0..n {
                        sim.h(i).unwrap();
                        sim.apply_depolarizing_noise(i, black_box(0.01)).unwrap();
                    }
                });
            },
        );
        
        group.bench_with_input(
            BenchmarkId::new("amplitude_damping", num_qubits),
            num_qubits,
            |b, &n| {
                b.iter(|| {
                    let mut sim = DensityMatrixSimulator::new(n);
                    // Apply gates with noise
                    for i in 0..n {
                        sim.x(i).unwrap();
                        sim.apply_amplitude_damping(i, black_box(0.05)).unwrap();
                    }
                });
            },
        );
    }
    
    group.finish();
}

criterion_group!(
    benches,
    benchmark_state_vector_gates,
    benchmark_state_vector_scaling,
    benchmark_density_matrix_gates,
    benchmark_density_matrix_scaling,
    benchmark_circuit_simulation,
    benchmark_measurement,
    benchmark_noise_simulation
);
criterion_main!(benches);

// Made with Bob
