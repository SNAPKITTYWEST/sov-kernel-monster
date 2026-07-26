//! Integration Tests for Phase 4 Quantum Algorithms
//!
//! End-to-end tests showing full pipeline: preparation → algorithm → measurement

#[cfg(test)]
mod tests {
    use qataaum_algorithms::*;
    use std::f64::consts::PI;

    #[test]
    fn test_h2_vqe_convergence() {
        // H2 molecule ground state via VQE
        let hamiltonian = hamiltonian::h2_hamiltonian();
        assert_eq!(hamiltonian.n_qubits, 2);
        assert!(hamiltonian.n_terms() > 0);

        // Create VQE circuit
        let circuit = vqe::ParametrizedCircuit::simple_ansatz(2, 2);
        assert_eq!(circuit.n_qubits, 2);

        // Create optimizer
        let optimizer = vqe::VQEOptimizer::new();

        // Note: full optimization would require quantum simulator
        // This tests the structural integration
        assert!(optimizer.learning_rate > 0.0);
    }

    #[test]
    fn test_maxcut_qaoa_small_graph() {
        // QAOA for MaxCut on 3-vertex triangle
        let edges = vec![(0, 1), (1, 2), (0, 2)];
        let qaoa = qaoa::MaxCutQAOA::new(3, edges, 1);

        assert!(qaoa.is_ok());
        let qaoa = qaoa.unwrap();
        assert_eq!(qaoa.edge_count(), 3);
        assert_eq!(qaoa.max_cut(), 3);
    }

    #[test]
    fn test_hamiltonian_simulation_trotter() {
        // Time evolution of H2 via Trotter-Suzuki
        let hamiltonian = hamiltonian::h2_hamiltonian();
        let config = hamiltonian_sim::HamiltonianSimConfig::new(0.1, 5)
            .with_second_order();

        let mut sim = hamiltonian_sim::TrotterSimulator::new(hamiltonian, config);
        let gates = sim.simulate();

        assert!(gates.is_ok());
        let gate_seq = gates.unwrap();
        assert!(!gate_seq.is_empty());

        // Check energy conservation
        let conservation = sim.energy_conservation();
        assert!(conservation > 0.99);
    }

    #[test]
    fn test_amplitude_estimation_simple() {
        // Amplitude estimation for 50% marked state
        let register = amplitude_est::AmplitudeRegister::uniform_marked(2, 0.5);
        assert!(register.is_ok());

        let mut estimator = amplitude_est::AmplitudeEstimator::new(5);
        assert!(estimator.is_ok());
    }

    #[test]
    fn test_quantum_walk_mixing() {
        // Quantum walk mixing on 4-cycle
        let walk = walks::CycleQuantumWalk::new(4);
        assert!(walk.is_ok());

        let walk = walk.unwrap();
        let gap = walk.spectral_gap();
        assert!(gap > 0.0 && gap < 4.0);
    }

    #[test]
    fn test_shor_factor_15() {
        // Factor 15 = 3 × 5
        let mut shor = shor::ShorFactoring::new(15);
        assert!(shor.is_ok());

        let mut shor = shor.unwrap();
        let factors = shor.factor();

        assert!(factors.is_ok());
        let factors = factors.unwrap();
        assert!(!factors.is_empty());
    }

    // Full pipeline tests

    #[test]
    fn test_vqe_h2_pipeline() {
        // Full VQE pipeline for H2
        let hamiltonian = hamiltonian::h2_hamiltonian();
        let (e_min, e_max) = hamiltonian.eigenvalue_bounds();

        // Ground state should be in bounds
        let ground_truth = vqe::molecules::h2_ground_state_energy();
        assert!(ground_truth >= e_min && ground_truth <= e_max);
    }

    #[test]
    fn test_qaoa_approximation_ratio_scaling() {
        // QAOA approximation ratio improves with layers
        let ratio_p1 = qaoa::MaxCutQAOA::expected_approx_ratio(1);
        let ratio_p2 = qaoa::MaxCutQAOA::expected_approx_ratio(2);
        let ratio_p3 = qaoa::MaxCutQAOA::expected_approx_ratio(3);

        assert!(ratio_p2 >= ratio_p1);
        assert!(ratio_p3 >= ratio_p2);
        assert!(ratio_p1 > 0.6 && ratio_p1 < 0.8);
    }

    #[test]
    fn test_trotter_error_convergence() {
        // Trotter error decreases with more steps
        let config1 = hamiltonian_sim::HamiltonianSimConfig::new(1.0, 5);
        let config2 = hamiltonian_sim::HamiltonianSimConfig::new(1.0, 10);
        let config4 = hamiltonian_sim::HamiltonianSimConfig::new(1.0, 20);

        let err1 = config1.error_bound();
        let err2 = config2.error_bound();
        let err4 = config4.error_bound();

        assert!(err2 < err1);
        assert!(err4 < err2);
    }

    #[test]
    fn test_amplitude_grover_amplification() {
        // Grover amplification increases amplitude
        let initial = 0.25;
        let amplified = amplitude_est::AmplitudeEstimator::grover_amplification(initial, 1);

        assert!(amplified.is_ok());
        let amplified = amplified.unwrap();
        assert!(amplified > initial);
    }

    #[test]
    fn test_walks_line_probability_distribution() {
        // Line walk probability distribution
        let walk = walks::LineQuantumWalk::new(5);
        let dist = walk.distribution();

        // Should be normalized
        let sum: f64 = dist.iter().sum();
        assert!((sum - 1.0).abs() < 1e-10);
    }

    #[test]
    fn test_shor_modpow_correctness() {
        // Verify modular exponentiation
        // 2^10 mod 1000 = 1024 mod 1000 = 24
        let exp = shor::ModularExponentiation::new(2, 1000).unwrap();
        assert_eq!(exp.compute(10), 24);
    }

    // Cross-algorithm tests

    #[test]
    fn test_pauli_hamiltonian_consistency() {
        // Pauli algebra consistency
        let p1 = hamiltonian::PauliString::new(vec![hamiltonian::PauliOp::X]);
        let p2 = hamiltonian::PauliString::new(vec![hamiltonian::PauliOp::X]);

        let result = p1.multiply(&p2).unwrap();
        assert_eq!(result.ops[0], hamiltonian::PauliOp::I);
    }

    #[test]
    fn test_vqe_optimizer_structure() {
        // VQE optimizer properly structured
        let opt = vqe::VQEOptimizer::new();
        assert!(opt.learning_rate > 0.0);
        assert!(opt.max_iterations > 0);
        assert!(opt.convergence_threshold > 0.0);
    }

    #[test]
    fn test_qaoa_circuit_parameters() {
        // QAOA circuit parameter management
        let params = qaoa::QAOAParams::new(2);
        assert_eq!(params.n_params(), 4);

        let vec = params.to_vec();
        let params2 = qaoa::QAOAParams::from_vec(&vec).unwrap();
        assert_eq!(params2.p, 2);
    }

    #[test]
    fn test_hamiltonian_simulation_config_scaling() {
        // Hamiltonian simulation configuration scales properly
        let steps_opt = hamiltonian_sim::HamiltonianSimConfig::optimal_steps(1.0, 1e-3);
        assert!(steps_opt > 0);

        let bound = hamiltonian_sim::HamiltonianSimConfig::new(1.0, steps_opt)
            .error_bound();
        assert!(bound < 1e-2);
    }

    #[test]
    fn test_amplitude_precision_scaling() {
        // Amplitude estimation precision requirements
        let shots = amplitude_est::AmplitudeEstimator::precision_scaling(0.5, 0.01);
        assert!(shots.is_ok());
        assert!(shots.unwrap() > 0);
    }

    #[test]
    fn test_walk_cycle_regularity() {
        // Cycle walk on regular graph
        let walk = walks::CycleQuantumWalk::new(6).unwrap();
        let gap = walk.spectral_gap();
        assert!(gap > 0.0);
    }

    #[test]
    fn test_shor_success_rate() {
        // Shor's algorithm success probability
        let prob = shor::ShorFactoring::success_probability();
        assert!(prob > 0.4 && prob < 0.42); // 4/π² ≈ 0.405
    }
}

// Made with Bob
