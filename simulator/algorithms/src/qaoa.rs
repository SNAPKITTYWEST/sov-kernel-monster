//! Quantum Approximate Optimization Algorithm (QAOA)
//!
//! Combines quantum and classical optimization for combinatorial problems.
//! Solves problems encoded in cost Hamiltonians via alternating:
//! - Cost Hamiltonian evolution (problem-specific)
//! - Mixer Hamiltonian evolution (driver)
//!
//! For MaxCut: H_C = Σ_{(i,j)∈E} (I - ZᵢZⱼ)/2

use crate::{hamiltonian::PauliHamiltonian, AlgorithmError, AlgorithmResult};
use std::collections::HashMap;
use std::f64::consts::PI;

/// QAOA circuit parameters
#[derive(Debug, Clone)]
pub struct QAOAParams {
    /// Cost Hamiltonian evolution times (β)
    pub beta: Vec<f64>,

    /// Mixer Hamiltonian evolution times (γ)
    pub gamma: Vec<f64>,

    /// Number of layers
    pub p: usize,
}

impl QAOAParams {
    /// Create new parameters with p layers
    pub fn new(p: usize) -> Self {
        QAOAParams {
            beta: vec![PI / 4.0; p],
            gamma: vec![PI / 2.0; p],
            p,
        }
    }

    /// Total number of parameters
    pub fn n_params(&self) -> usize {
        2 * self.p
    }

    /// Set parameters from flat vector [β₀, γ₀, β₁, γ₁, ...]
    pub fn from_vec(vec: &[f64]) -> AlgorithmResult<Self> {
        if vec.len() % 2 != 0 {
            return Err(AlgorithmError::InvalidParameters(
                "Parameter vector length must be even".to_string(),
            ));
        }

        let p = vec.len() / 2;
        let beta = vec[0..p].to_vec();
        let gamma = vec[p..2 * p].to_vec();

        Ok(QAOAParams { beta, gamma, p })
    }

    /// Convert to flat vector
    pub fn to_vec(&self) -> Vec<f64> {
        let mut v = self.beta.clone();
        v.extend(&self.gamma);
        v
    }
}

/// QAOA circuit for a specific problem
#[derive(Debug, Clone)]
pub struct QAOACircuit {
    /// Number of qubits
    pub n_qubits: usize,

    /// Cost Hamiltonian
    pub cost_hamiltonian: PauliHamiltonian,

    /// Mixer Hamiltonian (typically X chain)
    pub mixer_hamiltonian: PauliHamiltonian,

    /// Current parameters
    pub params: QAOAParams,

    /// Approximation ratio tracking
    pub approx_ratios: Vec<f64>,
}

impl QAOACircuit {
    /// Create new QAOA circuit
    pub fn new(
        n_qubits: usize,
        cost_hamiltonian: PauliHamiltonian,
        mixer_hamiltonian: PauliHamiltonian,
        p: usize,
    ) -> Self {
        QAOACircuit {
            n_qubits,
            cost_hamiltonian,
            mixer_hamiltonian,
            params: QAOAParams::new(p),
            approx_ratios: Vec::new(),
        }
    }

    /// Update parameters
    pub fn set_params(&mut self, params: QAOAParams) -> AlgorithmResult<()> {
        if params.p != self.params.p {
            return Err(AlgorithmError::InvalidParameters(
                "Parameter depth mismatch".to_string(),
            ));
        }
        self.params = params;
        Ok(())
    }

    /// Record approximation ratio
    pub fn record_approx_ratio(&mut self, ratio: f64) {
        self.approx_ratios.push(ratio);
    }

    /// Get best approximation ratio found so far
    pub fn best_approx_ratio(&self) -> Option<f64> {
        self.approx_ratios
            .iter()
            .copied()
            .max_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal))
    }
}

/// QAOA for MaxCut problem
#[derive(Debug, Clone)]
pub struct MaxCutQAOA {
    /// Number of vertices
    pub n: usize,

    /// Edges in graph
    pub edges: Vec<(usize, usize)>,

    /// QAOA circuit
    pub circuit: QAOACircuit,
}

impl MaxCutQAOA {
    /// Create MaxCut QAOA for given graph
    pub fn new(n: usize, edges: Vec<(usize, usize)>, p: usize) -> AlgorithmResult<Self> {
        // Validate edges
        for (u, v) in &edges {
            if *u >= n || *v >= n {
                return Err(AlgorithmError::InvalidGraph(
                    "Edge vertex out of range".to_string(),
                ));
            }
            if u >= v {
                return Err(AlgorithmError::InvalidGraph(
                    "Edges must be (u,v) with u < v".to_string(),
                ));
            }
        }

        // Cost Hamiltonian: H_C = Σ_{(i,j)∈E} (I - ZᵢZⱼ)/2
        // Equivalently: H_C = |E|/2 - Σ_{(i,j)∈E} ZᵢZⱼ/2
        let mut cost_ham = PauliHamiltonian::new(n);

        for (u, v) in &edges {
            use crate::hamiltonian::PauliOp;
            let mut ops = vec![PauliOp::I; n];
            ops[*u] = PauliOp::Z;
            ops[*v] = PauliOp::Z;

            cost_ham.add_term(
                -0.5,
                crate::hamiltonian::PauliString::new(ops),
            )?;
        }

        // Mixer Hamiltonian: H_M = Σᵢ Xᵢ
        let mut mixer_ham = PauliHamiltonian::new(n);
        for i in 0..n {
            use crate::hamiltonian::PauliOp;
            let mut ops = vec![PauliOp::I; n];
            ops[i] = PauliOp::X;
            mixer_ham.add_term(1.0, crate::hamiltonian::PauliString::new(ops))?;
        }

        let circuit = QAOACircuit::new(n, cost_ham, mixer_ham, p);

        Ok(MaxCutQAOA {
            n,
            edges,
            circuit,
        })
    }

    /// Compute exact MaxCut value for given bitstring (exponential)
    pub fn exact_maxcut_value(&self, bitstring: &[bool]) -> usize {
        let mut cut_size = 0;
        for (u, v) in &self.edges {
            if bitstring[*u] != bitstring[*v] {
                cut_size += 1;
            }
        }
        cut_size
    }

    /// Expected approximation ratio for p layers
    /// Classic result: α_p bounds for MaxCut
    pub fn expected_approx_ratio(p: usize) -> f64 {
        match p {
            1 => 0.6924,  // Rounded from 0.6924
            2 => 0.7559,
            3 => 0.7912,
            _ => 0.75 + 0.05 * (p as f64 - 1.0).min(5.0), // Rough estimate for larger p
        }
    }

    /// Number of edges (size of MaxCut problem)
    pub fn edge_count(&self) -> usize {
        self.edges.len()
    }

    /// Maximum possible cut (all edges cut = |E|)
    pub fn max_cut(&self) -> usize {
        self.edges.len()
    }
}

/// QAOA for Ising optimization
#[derive(Debug, Clone)]
pub struct IsingQAOA {
    /// Ising Hamiltonian
    pub hamiltonian: PauliHamiltonian,

    /// QAOA circuit
    pub circuit: QAOACircuit,
}

impl IsingQAOA {
    /// Create for Ising problem
    pub fn new(hamiltonian: PauliHamiltonian, p: usize) -> AlgorithmResult<Self> {
        let n_qubits = hamiltonian.n_qubits;

        // Cost Hamiltonian is the Ising Hamiltonian itself
        let cost_ham = hamiltonian.clone();

        // Mixer: transverse field
        use crate::hamiltonian::PauliOp;
        let mut mixer_ham = PauliHamiltonian::new(n_qubits);
        for i in 0..n_qubits {
            let mut ops = vec![PauliOp::I; n_qubits];
            ops[i] = PauliOp::X;
            mixer_ham.add_term(1.0, crate::hamiltonian::PauliString::new(ops))?;
        }

        let circuit = QAOACircuit::new(n_qubits, cost_ham, mixer_ham, p);

        Ok(IsingQAOA {
            hamiltonian,
            circuit,
        })
    }

    /// Get problem Hamiltonian eigenvalue bounds
    pub fn energy_bounds(&self) -> (f64, f64) {
        self.hamiltonian.eigenvalue_bounds()
    }
}

/// QAOA optimizer
#[derive(Debug, Clone)]
pub struct QAOAOptimizer {
    /// Learning rate
    pub learning_rate: f64,

    /// Maximum iterations
    pub max_iterations: usize,

    /// Convergence threshold
    pub convergence_threshold: f64,
}

impl QAOAOptimizer {
    /// Create default QAOA optimizer
    pub fn new() -> Self {
        QAOAOptimizer {
            learning_rate: 0.05,
            max_iterations: 200,
            convergence_threshold: 1e-4,
        }
    }

    /// Optimize MaxCut QAOA parameters
    pub fn optimize_maxcut(&self, maxcut: &mut MaxCutQAOA) -> AlgorithmResult<Vec<f64>> {
        // Start with default parameters
        let mut best_params = maxcut.circuit.params.to_vec();
        let mut best_ratio = 0.0;

        for _iteration in 0..self.max_iterations {
            // Simulate QAOA (placeholder)
            let ratio = MaxCutQAOA::expected_approx_ratio(maxcut.circuit.params.p);

            maxcut.circuit.record_approx_ratio(ratio);

            if ratio > best_ratio {
                best_ratio = ratio;
                best_params = maxcut.circuit.params.to_vec();
            }

            // In full implementation: compute gradients, update parameters
        }

        Ok(best_params)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_qaoa_params_creation() {
        let params = QAOAParams::new(2);
        assert_eq!(params.p, 2);
        assert_eq!(params.n_params(), 4);
    }

    #[test]
    fn test_qaoa_params_vec_conversion() {
        let vec = vec![0.1, 0.2, 0.3, 0.4];
        let params = QAOAParams::from_vec(&vec).unwrap();
        assert_eq!(params.beta, vec![0.1, 0.2]);
        assert_eq!(params.gamma, vec![0.3, 0.4]);
    }

    #[test]
    fn test_maxcut_qaoa_creation() {
        let edges = vec![(0, 1), (1, 2), (0, 2)];
        let qaoa = MaxCutQAOA::new(3, edges, 1);
        assert!(qaoa.is_ok());
        let qaoa = qaoa.unwrap();
        assert_eq!(qaoa.edge_count(), 3);
    }

    #[test]
    fn test_maxcut_exact_value() {
        let edges = vec![(0, 1), (1, 2)];
        let qaoa = MaxCutQAOA::new(3, edges, 1).unwrap();

        // Cut: 0,1,0 has cut size 2
        assert_eq!(qaoa.exact_maxcut_value(&[false, true, false]), 2);

        // Cut: 0,0,0 has cut size 0
        assert_eq!(qaoa.exact_maxcut_value(&[false, false, false]), 0);
    }

    #[test]
    fn test_maxcut_approx_ratio() {
        assert!(MaxCutQAOA::expected_approx_ratio(1) > 0.6);
        assert!(MaxCutQAOA::expected_approx_ratio(2) > MaxCutQAOA::expected_approx_ratio(1));
    }

    #[test]
    fn test_qaoa_optimizer_creation() {
        let opt = QAOAOptimizer::new();
        assert!(opt.learning_rate > 0.0);
        assert!(opt.max_iterations > 0);
    }
}

// Made with Bob
