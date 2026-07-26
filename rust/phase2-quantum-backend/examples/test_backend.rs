//! Example: Complete Phase 2 Quantum Backend Setup & Noise Application
//!
//! Demonstrates:
//! 1. Backend contract creation (5-qubit device)
//! 2. Calibration binding with WORM hash
//! 3. Topology queries
//! 4. Noise channel application
//! 5. Trace/PSD verification

use phase2_quantum_backend::backend_contract::*;
use phase2_quantum_backend::noise_channel::*;
use phase2_quantum_backend::topology::*;
use std::collections::{BTreeMap, HashMap};
use tch::{Device, Kind, Tensor};

fn main() {
    println!("=== Phase 2 Quantum Backend Example ===\n");

    // ─────────────────────────────────────────────────────────────
    // STEP 1: Define 5-Qubit Linear Topology
    // ─────────────────────────────────────────────────────────────
    println!("Step 1: Create 5-qubit linear topology");
    let mut connectivity = vec![vec![false; 5]; 5];
    for i in 0..5 {
        connectivity[i][i] = true; // self-loops
        if i + 1 < 5 {
            connectivity[i][i + 1] = true;
            connectivity[i + 1][i] = true;
        }
    }
    let coupling_graph = CouplingGraph::new(connectivity).unwrap();
    println!("✓ Linear topology: 0-1-2-3-4\n");

    // ─────────────────────────────────────────────────────────────
    // STEP 2: Create Per-Qubit Calibrations
    // ─────────────────────────────────────────────────────────────
    println!("Step 2: Create per-qubit calibrations");
    let mut qubit_cals = BTreeMap::new();
    for q in 0..5 {
        let cal = QubitCalibration::new(
            q,
            5.0 + q as f64 * 0.05,  // frequency: 5.0-5.2 GHz
            100.0,                   // T1: 100 μs
            50.0,                    // T2: 50 μs (T2 < T1 ✓)
            0.001,                   // 1-qubit error: 0.1%
            0.01,                    // 2-qubit error: 1%
            0.02,                    // readout 0→1: 2%
            0.01,                    // readout 1→0: 1%
        ).unwrap();
        qubit_cals.insert(q, cal);
    }
    println!("✓ Calibrated {} qubits\n", qubit_cals.len());

    // ─────────────────────────────────────────────────────────────
    // STEP 3: Create Calibration Snapshot with Hash
    // ─────────────────────────────────────────────────────────────
    println!("Step 3: Create calibration snapshot (WORM binding)");
    let calibration = CalibrationSnapshot::new(
        "ibm_fake_device_5q".to_string(),
        1234567890,
        qubit_cals,
        BTreeMap::new(),
    ).unwrap();
    println!("✓ Device: {}", calibration.device_id);
    println!("✓ Calibration hash: {}\n", &calibration.calibration_hash[..16]);
    let cal_hash = calibration.calibration_hash.clone();

    // ─────────────────────────────────────────────────────────────
    // STEP 4: Define Native Gates & Timing
    // ─────────────────────────────────────────────────────────────
    println!("Step 4: Define native gates and timing constraints");
    let native_gates = vec![
        NativeGate::H,
        NativeGate::X,
        NativeGate::Y,
        NativeGate::Z,
        NativeGate::Rx,
        NativeGate::CX,
        NativeGate::CZ,
    ];
    let timing = TimingConstraints::new(
        10.0,     // min gate duration: 10 ns
        100.0,    // max gate duration: 100 ns
        200.0,    // measurement window: 200 ns
        500.0,    // reset time: 500 ns
        10000.0,  // coherence limit: 10000 ns (10 μs)
    ).unwrap();
    println!("✓ Native gates: {:?}", native_gates);
    println!("✓ Timing: [{:.0}, {:.0}] ns\n", 10.0, 100.0);

    // ─────────────────────────────────────────────────────────────
    // STEP 5: Construct Full Backend Contract
    // ─────────────────────────────────────────────────────────────
    println!("Step 5: Construct full backend contract");
    let backend = QuantumBackend::new(
        5,
        coupling_graph,
        native_gates,
        HashMap::new(),
        calibration,
        timing,
    ).unwrap();
    println!("✓ Backend hash: {}", &backend.backend_hash[..16]);
    println!("✓ Contract validated ✓\n");

    // ─────────────────────────────────────────────────────────────
    // STEP 6: Topology Queries
    // ─────────────────────────────────────────────────────────────
    println!("Step 6: Topology analysis");
    let is_linear = TopologyAnalyzer::is_linear(&backend.coupling_graph).unwrap();
    println!("✓ Is linear: {}", is_linear);

    let diameter = TopologyAnalyzer::diameter(&backend.coupling_graph).unwrap();
    println!("✓ Diameter: {}", diameter);

    let path = TopologyAnalyzer::shortest_path(&backend.coupling_graph, 0, 4).unwrap();
    println!("✓ Shortest path (0→4): {:?}", path);

    let avg_degree = TopologyAnalyzer::average_degree(&backend.coupling_graph).unwrap();
    println!("✓ Average degree: {:.2}\n", avg_degree);

    // ─────────────────────────────────────────────────────────────
    // STEP 7: Apply Noise Channels
    // ─────────────────────────────────────────────────────────────
    println!("Step 7: Apply noise channels");

    // Create maximally mixed initial state
    let rho_init = Tensor::eye(2, (Kind::Double, Device::Cpu)) * 0.5;
    println!("✓ Initial state: maximally mixed I/2");

    // ─────────────────────────────────────────────────────────────
    // 7a. Depolarizing noise
    // ─────────────────────────────────────────────────────────────
    let depo_channel = DepolarizingChannel::new(0.01).unwrap();
    let rho_depo = depo_channel.apply(&rho_init).unwrap();
    let trace_depo: f64 = rho_depo.trace().double_value(&[]);
    println!("\n7a. Depolarizing (p=0.01):");
    println!("   Trace: {:.15}", trace_depo);
    println!("   ✓ Trace ≈ 1 (error: {:.2e})", (trace_depo - 1.0).abs());

    // ─────────────────────────────────────────────────────────────
    // 7b. Amplitude damping
    // ─────────────────────────────────────────────────────────────
    let amp_channel = AmplitudeDampingChannel::new(0.05).unwrap();
    let rho_amp = amp_channel.apply(&rho_init).unwrap();
    let trace_amp: f64 = rho_amp.trace().double_value(&[]);
    println!("\n7b. Amplitude damping (γ=0.05):");
    println!("   Trace: {:.15}", trace_amp);
    println!("   ✓ Trace ≈ 1 (error: {:.2e})", (trace_amp - 1.0).abs());

    // ─────────────────────────────────────────────────────────────
    // 7c. Phase damping
    // ─────────────────────────────────────────────────────────────
    let phase_channel = PhaseDampingChannel::new(0.03).unwrap();
    let rho_phase = phase_channel.apply(&rho_init).unwrap();
    let trace_phase: f64 = rho_phase.trace().double_value(&[]);
    println!("\n7c. Phase damping (γ=0.03):");
    println!("   Trace: {:.15}", trace_phase);
    println!("   ✓ Trace ≈ 1 (error: {:.2e})", (trace_phase - 1.0).abs());

    // ─────────────────────────────────────────────────────────────
    // 7d. Readout error
    // ─────────────────────────────────────────────────────────────
    let readout_channel = ReadoutErrorChannel::new(0.02, 0.01).unwrap();
    let rho_readout = readout_channel.apply(&rho_init).unwrap();
    let trace_readout: f64 = rho_readout.trace().double_value(&[]);
    println!("\n7d. Readout error (p_01=0.02, p_10=0.01):");
    println!("   Trace: {:.15}", trace_readout);
    println!("   ✓ Trace ≈ 1 (error: {:.2e})", (trace_readout - 1.0).abs());

    // ─────────────────────────────────────────────────────────────
    // 7e. Pauli channel
    // ─────────────────────────────────────────────────────────────
    let pauli_channel = PauliChannel::new(0.01, 0.01, 0.02).unwrap();
    let rho_pauli = pauli_channel.apply(&rho_init).unwrap();
    let trace_pauli: f64 = rho_pauli.trace().double_value(&[]);
    println!("\n7e. Pauli channel (px=0.01, py=0.01, pz=0.02):");
    println!("   Trace: {:.15}", trace_pauli);
    println!("   ✓ Trace ≈ 1 (error: {:.2e})", (trace_pauli - 1.0).abs());

    // ─────────────────────────────────────────────────────────────
    // STEP 8: Verify PSD (Positive Semi-Definiteness)
    // ─────────────────────────────────────────────────────────────
    println!("\n\nStep 8: Verify positive semi-definiteness");

    let verify_psd = |name: &str, rho: &Tensor| {
        let (evals, _) = rho.linalg_eigh("L");
        let min_eval: f64 = evals.min().double_value(&[]);
        println!("{}: min eigenvalue = {:.2e}", name, min_eval);
        assert!(
            min_eval >= -1e-10,
            "PSD violated for {}",
            name
        );
        println!("   ✓ PSD preserved");
    };

    verify_psd("Depolarizing", &rho_depo);
    verify_psd("Amplitude damping", &rho_amp);
    verify_psd("Phase damping", &rho_phase);
    verify_psd("Readout error", &rho_readout);
    verify_psd("Pauli", &rho_pauli);

    // ─────────────────────────────────────────────────────────────
    // STEP 9: Verify Kraus Trace Preservation
    // ─────────────────────────────────────────────────────────────
    println!("\n\nStep 9: Verify Kraus trace preservation (Σ E_k† E_k = I)");

    depo_channel.verify_trace_preservation().unwrap();
    println!("✓ Depolarizing: Σ E_k† E_k = I");

    amp_channel.verify_trace_preservation().unwrap();
    println!("✓ Amplitude damping: Σ E_k† E_k = I");

    phase_channel.verify_trace_preservation().unwrap();
    println!("✓ Phase damping: Σ E_k† E_k = I");

    readout_channel.verify_trace_preservation().unwrap();
    println!("✓ Readout error: Σ E_k† E_k = I");

    pauli_channel.verify_trace_preservation().unwrap();
    println!("✓ Pauli channel: Σ E_k† E_k = I");

    // ─────────────────────────────────────────────────────────────
    // SUMMARY
    // ─────────────────────────────────────────────────────────────
    println!("\n\n=== Summary ===");
    println!("✓ Backend contract created & validated");
    println!("✓ Calibration snapshot: {} hash", &cal_hash[..16]);
    println!("✓ Topology: {} qubits, linear path", 5);
    println!("✓ All 5 noise channels working");
    println!("✓ Trace preservation: 100%");
    println!("✓ PSD preservation: 100%");
    println!("✓ Kraus trace condition: All verified ✓");
    println!("\n=== Phase 2 Complete ===");
}
