//! Density Matrix Quantum Simulator
//!
//! This module implements a density-matrix-based quantum simulator that can
//! handle mixed states, decoherence, and noise channels. Unlike the state-vector
//! simulator, this can represent statistical mixtures of quantum states.
//!
//! # Density Matrix Representation
//!
//! A density matrix ρ is a positive semi-definite Hermitian matrix with trace 1.
//! For an n-qubit system, ρ is a 2^n × 2^n complex matrix.
//!
//! Pure states: ρ = |ψ⟩⟨ψ|
//! Mixed states: ρ = Σ p_i |ψ_i⟩⟨ψ_i| where Σ p_i = 1
//!
//! # Clean-Room Implementation
//!
//! This simulator is based on standard quantum mechanics textbooks and papers:
//! - Nielsen & Chuang, "Quantum Computation and Quantum Information"
//! - Preskill, "Lecture Notes on Quantum Computation"
//! - Standard density matrix formalism
//!
//! No proprietary IBM simulation code is used.

use num_complex::Complex64;

/// Complex number type
type Complex = Complex64;

/// Density matrix simulator for quantum circuits
pub struct DensityMatrixSimulator {
    /// Number of qubits
    num_qubits: usize,
    
    /// Density matrix (2^n × 2^n)
    /// Stored in row-major order
    density_matrix: Vec<Complex>,
    
    /// Dimension (2^num_qubits)
    dim: usize,
}

impl DensityMatrixSimulator {
    /// Create a new density matrix simulator with n qubits in |0⟩ state
    pub fn new(num_qubits: usize) -> Self {
        let dim = 1 << num_qubits; // 2^num_qubits
        let mut density_matrix = vec![Complex::new(0.0, 0.0); dim * dim];
        
        // Initialize to |0...0⟩⟨0...0|
        density_matrix[0] = Complex::new(1.0, 0.0);
        
        Self {
            num_qubits,
            density_matrix,
            dim,
        }
    }
    
    /// Get the number of qubits
    pub fn num_qubits(&self) -> usize {
        self.num_qubits
    }
    
    /// Get element (i, j) of the density matrix
    fn get(&self, i: usize, j: usize) -> Complex {
        self.density_matrix[i * self.dim + j]
    }
    
    /// Set element (i, j) of the density matrix
    pub fn set(&mut self, i: usize, j: usize, value: Complex) {
        self.density_matrix[i * self.dim + j] = value;
    }
    
    /// Apply a single-qubit unitary gate
    pub fn apply_single_qubit_gate(&mut self, qubit: usize, gate: &[[Complex; 2]; 2]) {
        let new_rho = self.apply_unitary_single_qubit(qubit, gate);
        self.density_matrix = new_rho;
    }
    
    /// Apply a two-qubit unitary gate
    pub fn apply_two_qubit_gate(&mut self, control: usize, target: usize, gate: &[[Complex; 4]; 4]) {
        let new_rho = self.apply_unitary_two_qubit(control, target, gate);
        self.density_matrix = new_rho;
    }
    
    /// Apply Pauli X gate
    pub fn x(&mut self, qubit: usize) {
        let gate = [
            [Complex::new(0.0, 0.0), Complex::new(1.0, 0.0)],
            [Complex::new(1.0, 0.0), Complex::new(0.0, 0.0)],
        ];
        self.apply_single_qubit_gate(qubit, &gate);
    }
    
    /// Apply Pauli Y gate
    pub fn y(&mut self, qubit: usize) {
        let gate = [
            [Complex::new(0.0, 0.0), Complex::new(0.0, -1.0)],
            [Complex::new(0.0, 1.0), Complex::new(0.0, 0.0)],
        ];
        self.apply_single_qubit_gate(qubit, &gate);
    }
    
    /// Apply Pauli Z gate
    pub fn z(&mut self, qubit: usize) {
        let gate = [
            [Complex::new(1.0, 0.0), Complex::new(0.0, 0.0)],
            [Complex::new(0.0, 0.0), Complex::new(-1.0, 0.0)],
        ];
        self.apply_single_qubit_gate(qubit, &gate);
    }
    
    /// Apply Hadamard gate
    pub fn h(&mut self, qubit: usize) {
        let sqrt2_inv = 1.0 / 2.0_f64.sqrt();
        let gate = [
            [Complex::new(sqrt2_inv, 0.0), Complex::new(sqrt2_inv, 0.0)],
            [Complex::new(sqrt2_inv, 0.0), Complex::new(-sqrt2_inv, 0.0)],
        ];
        self.apply_single_qubit_gate(qubit, &gate);
    }
    
    /// Apply CNOT gate
    pub fn cnot(&mut self, control: usize, target: usize) {
        let gate = [
            [Complex::new(1.0, 0.0), Complex::new(0.0, 0.0), Complex::new(0.0, 0.0), Complex::new(0.0, 0.0)],
            [Complex::new(0.0, 0.0), Complex::new(1.0, 0.0), Complex::new(0.0, 0.0), Complex::new(0.0, 0.0)],
            [Complex::new(0.0, 0.0), Complex::new(0.0, 0.0), Complex::new(0.0, 0.0), Complex::new(1.0, 0.0)],
            [Complex::new(0.0, 0.0), Complex::new(0.0, 0.0), Complex::new(1.0, 0.0), Complex::new(0.0, 0.0)],
        ];
        self.apply_two_qubit_gate(control, target, &gate);
    }
    
    /// Apply depolarizing noise channel
    /// With probability p, apply a random Pauli error
    pub fn depolarizing_noise(&mut self, qubit: usize, p: f64) {
        if p <= 0.0 || p >= 1.0 {
            return;
        }
        
        let p_pauli = p / 3.0;
        let p_identity = 1.0 - p;
        
        // ρ' = (1-p)ρ + (p/3)(XρX + YρY + ZρZ)
        let original = self.density_matrix.clone();
        
        // Apply identity with probability (1-p)
        for i in 0..self.density_matrix.len() {
            self.density_matrix[i] = original[i] * p_identity;
        }
        
        // Apply X with probability p/3
        let mut temp_sim = DensityMatrixSimulator {
            num_qubits: self.num_qubits,
            density_matrix: original.clone(),
            dim: self.dim,
        };
        temp_sim.x(qubit);
        for i in 0..self.density_matrix.len() {
            self.density_matrix[i] += temp_sim.density_matrix[i] * p_pauli;
        }
        
        // Apply Y with probability p/3
        temp_sim.density_matrix = original.clone();
        temp_sim.y(qubit);
        for i in 0..self.density_matrix.len() {
            self.density_matrix[i] += temp_sim.density_matrix[i] * p_pauli;
        }
        
        // Apply Z with probability p/3
        temp_sim.density_matrix = original;
        temp_sim.z(qubit);
        for i in 0..self.density_matrix.len() {
            self.density_matrix[i] += temp_sim.density_matrix[i] * p_pauli;
        }
    }
    
    /// Measure a qubit and return the result (0 or 1)
    /// This performs a projective measurement and collapses the state
    pub fn measure(&mut self, qubit: usize) -> u8 {
        let prob_one = self.measure_probability(qubit, 1);
        
        // Simulate measurement outcome
        let outcome = if rand::random::<f64>() < prob_one { 1 } else { 0 };
        
        // Collapse the state
        self.collapse_measurement(qubit, outcome);
        
        outcome
    }
    
    /// Get the probability of measuring a specific outcome
    pub fn measure_probability(&self, qubit: usize, outcome: u8) -> f64 {
        let mut prob = 0.0;
        
        for i in 0..self.dim {
            if ((i >> qubit) & 1) == outcome as usize {
                prob += self.get(i, i).re;
            }
        }
        
        prob
    }
    
    /// Collapse the state after measurement
    fn collapse_measurement(&mut self, qubit: usize, outcome: u8) {
        let prob = self.measure_probability(qubit, outcome);
        if prob < 1e-10 {
            return; // Avoid division by zero
        }
        
        let mut new_rho = vec![Complex::new(0.0, 0.0); self.dim * self.dim];
        
        for i in 0..self.dim {
            for j in 0..self.dim {
                if ((i >> qubit) & 1) == outcome as usize && ((j >> qubit) & 1) == outcome as usize {
                    new_rho[i * self.dim + j] = self.get(i, j) / prob;
                }
            }
        }
        
        self.density_matrix = new_rho;
    }
    
    /// Get the purity of the state: Tr(ρ²)
    /// Pure states have purity 1, maximally mixed states have purity 1/dim
    pub fn purity(&self) -> f64 {
        let rho_squared = self.matrix_multiply(&self.density_matrix, &self.density_matrix);
        self.trace(&rho_squared).re
    }
    
    /// Get the trace of a matrix
    fn trace(&self, matrix: &[Complex]) -> Complex {
        let mut tr = Complex::new(0.0, 0.0);
        for i in 0..self.dim {
            tr += matrix[i * self.dim + i];
        }
        tr
    }
    
    /// Multiply two matrices
    fn matrix_multiply(&self, a: &[Complex], b: &[Complex]) -> Vec<Complex> {
        let mut result = vec![Complex::new(0.0, 0.0); self.dim * self.dim];
        
        for i in 0..self.dim {
            for j in 0..self.dim {
                let mut sum = Complex::new(0.0, 0.0);
                for k in 0..self.dim {
                    sum += a[i * self.dim + k] * b[k * self.dim + j];
                }
                result[i * self.dim + j] = sum;
            }
        }
        
        result
    }
    
    /// Apply single-qubit unitary: ρ' = U ρ U†
    fn apply_unitary_single_qubit(&self, qubit: usize, gate: &[[Complex; 2]; 2]) -> Vec<Complex> {
        let mut new_rho = vec![Complex::new(0.0, 0.0); self.dim * self.dim];
        
        for i in 0..self.dim {
            for j in 0..self.dim {
                let i_bit = (i >> qubit) & 1;
                let j_bit = (j >> qubit) & 1;
                
                for k in 0..2 {
                    for l in 0..2 {
                        let i_new = (i & !(1 << qubit)) | (k << qubit);
                        let j_new = (j & !(1 << qubit)) | (l << qubit);
                        
                        new_rho[i * self.dim + j] += 
                            gate[k][i_bit] * self.get(i_new, j_new) * gate[l][j_bit].conj();
                    }
                }
            }
        }
        
        new_rho
    }
    
    /// Apply two-qubit unitary: ρ' = U ρ U†
    fn apply_unitary_two_qubit(&self, control: usize, target: usize, gate: &[[Complex; 4]; 4]) -> Vec<Complex> {
        let mut new_rho = vec![Complex::new(0.0, 0.0); self.dim * self.dim];
        
        for i in 0..self.dim {
            for j in 0..self.dim {
                let i_ctrl = (i >> control) & 1;
                let i_targ = (i >> target) & 1;
                let i_bits = (i_ctrl << 1) | i_targ;
                
                let j_ctrl = (j >> control) & 1;
                let j_targ = (j >> target) & 1;
                let j_bits = (j_ctrl << 1) | j_targ;
                
                for k in 0..4 {
                    for l in 0..4 {
                        let k_ctrl = (k >> 1) & 1;
                        let k_targ = k & 1;
                        let l_ctrl = (l >> 1) & 1;
                        let l_targ = l & 1;
                        
                        let i_new = (i & !(1 << control) & !(1 << target)) | 
                                   (k_ctrl << control) | (k_targ << target);
                        let j_new = (j & !(1 << control) & !(1 << target)) | 
                                   (l_ctrl << control) | (l_targ << target);
                        
                        new_rho[i * self.dim + j] += 
                            gate[k][i_bits] * self.get(i_new, j_new) * gate[l][j_bits].conj();
                    }
                }
            }
        }
        
        new_rho
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_initialization() {
        let sim = DensityMatrixSimulator::new(2);
        assert_eq!(sim.num_qubits(), 2);
        assert_eq!(sim.dim, 4);
        
        // Check that ρ(0,0) = 1 (|00⟩⟨00|)
        assert!((sim.get(0, 0).re - 1.0).abs() < 1e-10);
        assert!(sim.get(0, 0).im.abs() < 1e-10);
    }
    
    #[test]
    fn test_pauli_x() {
        let mut sim = DensityMatrixSimulator::new(1);
        sim.x(0);
        
        // After X, should be in |1⟩⟨1| state
        assert!((sim.get(1, 1).re - 1.0).abs() < 1e-10);
        assert!(sim.get(0, 0).re.abs() < 1e-10);
    }
    
    #[test]
    fn test_hadamard() {
        let mut sim = DensityMatrixSimulator::new(1);
        sim.h(0);
        
        // After H on |0⟩, should be in |+⟩⟨+| = (|0⟩⟨0| + |0⟩⟨1| + |1⟩⟨0| + |1⟩⟨1|)/2
        assert!((sim.get(0, 0).re - 0.5).abs() < 1e-10);
        assert!((sim.get(0, 1).re - 0.5).abs() < 1e-10);
        assert!((sim.get(1, 0).re - 0.5).abs() < 1e-10);
        assert!((sim.get(1, 1).re - 0.5).abs() < 1e-10);
    }
    
    #[test]
    fn test_purity_pure_state() {
        let sim = DensityMatrixSimulator::new(2);
        let purity = sim.purity();
        
        // Pure state should have purity = 1
        assert!((purity - 1.0).abs() < 1e-10);
    }
    
    #[test]
    fn test_depolarizing_noise() {
        let mut sim = DensityMatrixSimulator::new(1);
        sim.depolarizing_noise(0, 0.5);
        
        // After depolarizing noise, purity should decrease
        let purity = sim.purity();
        assert!(purity < 1.0);
        assert!(purity > 0.0);
    }
    
    #[test]
    fn test_measurement_probabilities() {
        let mut sim = DensityMatrixSimulator::new(1);
        sim.h(0);
        
        // After H, should have 50/50 probability
        let prob_0 = sim.measure_probability(0, 0);
        let prob_1 = sim.measure_probability(0, 1);
        
        assert!((prob_0 - 0.5).abs() < 1e-10);
        assert!((prob_1 - 0.5).abs() < 1e-10);
    }
    
    #[test]
    fn test_cnot() {
        let mut sim = DensityMatrixSimulator::new(2);
        sim.h(0);
        sim.cnot(0, 1);
        
        // Should create Bell state |Φ+⟩ = (|00⟩ + |11⟩)/√2
        // ρ = (|00⟩⟨00| + |00⟩⟨11| + |11⟩⟨00| + |11⟩⟨11|)/2
        assert!((sim.get(0, 0).re - 0.5).abs() < 1e-10);
        assert!((sim.get(3, 3).re - 0.5).abs() < 1e-10);
        assert!((sim.get(0, 3).re - 0.5).abs() < 1e-10);
        assert!((sim.get(3, 0).re - 0.5).abs() < 1e-10);
    }
}

// Made with Bob
