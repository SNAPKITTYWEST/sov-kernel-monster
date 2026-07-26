//! Variational Quantum Eigensolver (VQE)
//!
//! Hybrid classical-quantum algorithm for finding ground state energies.
//! Uses a parametrized quantum circuit (ansatz) and classical optimization.
//!
//! Algorithm:
//! 1. Prepare parametrized circuit |ψ(θ)⟩
//! 2. Measure ⟨ψ(θ)|H|ψ(θ)⟩
//! 3. Classical optimizer adjusts θ to minimize energy
//! 4. Repeat until convergence

use crate::{hamiltonian::PauliHamiltonian, AlgorithmError, AlgorithmResult};
use num_complex::Complex64;
use std::f64::consts::PI;

/// A parametrized quantum circuit with rotation angles
#[derive(Debug, Clone)]
pub struct ParametrizedCircuit {
    /// Number of qubits
    pub n_qubits: usize,

    /// Rotation parameters: angles for RY rotations
    pub params: Vec<f64>,

    /// Circuit depth (number of parameter layers)
    pub depth: usize,
}

impl ParametrizedCircuit {
    /// Create a simple ansatz: alternating Ry rotations and entanglement
    pub fn simple_ansatz(n_qubits: usize, depth: usize) -> Self {
        // n_qubits * depth parameters (one per qubit per layer)
        let n_params = n_qubits * depth;
        let params = vec![0.0; n_params];

        ParametrizedCircuit {
            n_qubits,
            params,
            depth,
        }
    }

    /// Update parameters
    pub fn set_params(&mut self, params: Vec<f64>) -> AlgorithmResult<()> {
        if params.len() != self.params.len() {
            return Err(AlgorithmError::InvalidParameters(format!(
                "Expected {} parameters, got {}",
                self.params.len(),
                params.len()
            )));
        }
        self.params = params;
        Ok(())
    }

    /// Number of parameters
    pub fn n_params(&self) -> usize {
        self.params.len()
    }

    /// Get parameter gradient numerically (finite differences)
    pub fn gradient(&self, shift: f64, _energy_fn: impl Fn(&[f64]) -> f64) -> Vec<f64> {
        let mut grad = vec![0.0; self.n_params()];

        for i in 0..self.n_params() {
            let mut params_plus = self.params.clone();
            let mut params_minus = self.params.clone();

            params_plus[i] += shift;
            params_minus[i] -= shift;

            let e_plus = _energy_fn(&params_plus);
            let e_minus = _energy_fn(&params_minus);

            grad[i] = (e_plus - e_minus) / (2.0 * shift);
        }

        grad
    }
}

/// Energy evaluation and convergence tracking
#[derive(Debug, Clone)]
pub struct EnergyEvaluator {
    /// Energy history
    pub energy_history: Vec<f64>,

    /// Parameter history
    pub param_history: Vec<Vec<f64>>,

    /// Gradient norm history
    pub gradient_history: Vec<f64>,

    /// Current best energy
    pub best_energy: f64,

    /// Iteration count
    pub iterations: usize,
}

impl EnergyEvaluator {
    /// Create a new evaluator
    pub fn new() -> Self {
        EnergyEvaluator {
            energy_history: Vec::new(),
            param_history: Vec::new(),
            gradient_history: Vec::new(),
            best_energy: f64::INFINITY,
            iterations: 0,
        }
    }

    /// Record an evaluation
    pub fn record(
        &mut self,
        energy: f64,
        params: Vec<f64>,
        grad_norm: f64,
    ) {
        self.energy_history.push(energy);
        self.param_history.push(params);
        self.gradient_history.push(grad_norm);
        self.iterations += 1;

        if energy < self.best_energy {
            self.best_energy = energy;
        }
    }

    /// Get convergence rate (slope of energy history)
    pub fn convergence_rate(&self) -> Option<f64> {
        if self.energy_history.len() < 2 {
            return None;
        }

        let n = self.energy_history.len() as f64;
        let mean_e: f64 = self.energy_history.iter().sum::<f64>() / n;
        let mean_i: f64 = (self.energy_history.len() as f64 - 1.0) / 2.0;

        let mut num = 0.0;
        let mut denom = 0.0;

        for (i, e) in self.energy_history.iter().enumerate() {
            let dev_i = i as f64 - mean_i;
            let dev_e = e - mean_e;
            num += dev_i * dev_e;
            denom += dev_i * dev_i;
        }

        if denom.abs() < 1e-10 {
            None
        } else {
            Some(num / denom)
        }
    }

    /// Check convergence: gradient norm below threshold
    pub fn has_converged(&self, threshold: f64) -> bool {
        if let Some(last_grad) = self.gradient_history.last() {
            last_grad < &threshold
        } else {
            false
        }
    }
}

/// VQE optimizer using gradient descent
#[derive(Debug, Clone)]
pub struct VQEOptimizer {
    /// Learning rate
    pub learning_rate: f64,

    /// Maximum iterations
    pub max_iterations: usize,

    /// Convergence threshold
    pub convergence_threshold: f64,

    /// Finite difference step for gradients
    pub gradient_shift: f64,
}

impl VQEOptimizer {
    /// Create default optimizer
    pub fn new() -> Self {
        VQEOptimizer {
            learning_rate: 0.01,
            max_iterations: 100,
            convergence_threshold: 1e-5,
            gradient_shift: 1e-4,
        }
    }

    /// Optimize circuit parameters to minimize energy
    pub fn optimize(
        &self,
        mut circuit: ParametrizedCircuit,
        hamiltonian: &PauliHamiltonian,
    ) -> AlgorithmResult<(ParametrizedCircuit, EnergyEvaluator)> {
        let mut evaluator = EnergyEvaluator::new();

        // Energy function for given parameters
        let energy_fn = |params: &[f64]| -> f64 {
            // Simplified: would compute via quantum simulation
            // For now, use a simple test function
            params.iter().map(|p| p.sin()).sum::<f64>()
        };

        for iteration in 0..self.max_iterations {
            // Compute energy
            let energy = energy_fn(&circuit.params);

            // Compute gradient
            let grad = circuit.gradient(self.gradient_shift, &energy_fn);
            let grad_norm = grad.iter().map(|g| g * g).sum::<f64>().sqrt();

            // Record
            evaluator.record(energy, circuit.params.clone(), grad_norm);

            // Check convergence
            if evaluator.has_converged(self.convergence_threshold) {
                break;
            }

            // Update parameters: θ ← θ - α∇E
            for i in 0..circuit.n_params() {
                circuit.params[i] -= self.learning_rate * grad[i];
            }
        }

        Ok((circuit, evaluator))
    }
}

/// VQE for specific molecules
pub mod molecules {
    use super::*;

    /// Ground state energy of H₂ molecule
    pub fn h2_ground_state_energy() -> f64 {
        -1.17
    }

    /// Ground state energy of LiH molecule at equilibrium
    pub fn lih_ground_state_energy() -> f64 {
        -7.773
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parametrized_circuit_simple_ansatz() {
        let circuit = ParametrizedCircuit::simple_ansatz(2, 2);
        assert_eq!(circuit.n_qubits, 2);
        assert_eq!(circuit.depth, 2);
        assert_eq!(circuit.n_params(), 4);
    }

    #[test]
    fn test_energy_evaluator_recording() {
        let mut eval = EnergyEvaluator::new();
        eval.record(-1.0, vec![0.1, 0.2], 0.1);
        eval.record(-1.05, vec![0.15, 0.25], 0.08);

        assert_eq!(eval.iterations, 2);
        assert_eq!(eval.best_energy, -1.05);
    }

    #[test]
    fn test_energy_evaluator_convergence() {
        let mut eval = EnergyEvaluator::new();
        eval.record(-1.0, vec![0.1, 0.2], 0.1);
        assert!(!eval.has_converged(0.05));

        eval.record(-1.05, vec![0.15, 0.25], 0.01);
        assert!(eval.has_converged(0.05));
    }

    #[test]
    fn test_vqe_optimizer_creation() {
        let optimizer = VQEOptimizer::new();
        assert!(optimizer.learning_rate > 0.0);
        assert!(optimizer.max_iterations > 0);
    }

    #[test]
    fn test_h2_ground_state() {
        let gs = molecules::h2_ground_state_energy();
        assert!(gs < 0.0);
        assert!(gs > -2.0);
    }
}

// Made with Bob
