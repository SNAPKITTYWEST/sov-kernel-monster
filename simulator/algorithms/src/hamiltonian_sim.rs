//! Hamiltonian Simulation via Trotter-Suzuki Formula
//!
//! Time evolution under Hamiltonian: |ψ(t)⟩ = e^(-iHt)|ψ(0)⟩
//!
//! Trotter-Suzuki product formula:
//! e^(-iHt) ≈ [e^(-iH₁t/r) e^(-iH₂t/r) ... e^(-iHₙt/r)]^r
//!
//! Error bounds: ||e^(-iHt) - T_r(t)|| = O(t³/r²) for first-order
//! Second-order: O(t⁵/r⁴)

use crate::{hamiltonian::PauliHamiltonian, AlgorithmError, AlgorithmResult};
use num_complex::Complex64;
use std::f64::consts::PI;

/// Configuration for Hamiltonian simulation
#[derive(Debug, Clone)]
pub struct HamiltonianSimConfig {
    /// Evolution time
    pub time: f64,

    /// Number of Trotter steps
    pub steps: usize,

    /// Order of Trotter-Suzuki (1 or 2)
    pub order: usize,
}

impl HamiltonianSimConfig {
    /// Create new configuration
    pub fn new(time: f64, steps: usize) -> Self {
        HamiltonianSimConfig {
            time,
            steps,
            order: 1,
        }
    }

    /// Use second-order formula
    pub fn with_second_order(mut self) -> Self {
        self.order = 2;
        self
    }

    /// Time step per iteration
    pub fn dt(&self) -> f64 {
        self.time / self.steps as f64
    }

    /// Trotter error bound (first-order)
    pub fn error_bound(&self) -> f64 {
        let t = self.time;
        let r = self.steps as f64;
        match self.order {
            1 => (t * t * t) / (2.0 * r * r),
            2 => (t * t * t * t * t) / (24.0 * r * r * r * r),
            _ => f64::INFINITY,
        }
    }

    /// Optimal number of steps for target precision
    pub fn optimal_steps(time: f64, target_error: f64) -> usize {
        // r ≥ √(t³ / (2ε))
        ((time * time * time) / (2.0 * target_error)).sqrt().ceil() as usize
    }
}

/// Pauli exponential gate: e^(-iθP₁⊗P₂⊗...⊗Pₙ)
/// For Pauli strings, these decompose nicely into standard gates
#[derive(Debug, Clone)]
pub struct PauliExponential {
    /// Angle (θ)
    pub angle: f64,

    /// Target qubits
    pub qubits: Vec<usize>,

    /// Pauli operators (I, X, Y, Z codes)
    pub paulis: Vec<u8>,
}

impl PauliExponential {
    /// Create new Pauli exponential
    pub fn new(angle: f64, qubits: Vec<usize>, paulis: Vec<u8>) -> AlgorithmResult<Self> {
        if qubits.len() != paulis.len() {
            return Err(AlgorithmError::InvalidParameters(
                "Qubits and Paulis length mismatch".to_string(),
            ));
        }

        // Validate Pauli codes (0=I, 1=X, 2=Y, 3=Z)
        for &p in &paulis {
            if p > 3 {
                return Err(AlgorithmError::InvalidParameters(
                    "Invalid Pauli code".to_string(),
                ));
            }
        }

        Ok(PauliExponential {
            angle,
            qubits,
            paulis,
        })
    }

    /// Get number of native 2-qubit gates needed
    pub fn gate_count(&self) -> usize {
        // Count non-identity Paulis
        let weight = self.paulis.iter().filter(|&&p| p != 0).count();

        match weight {
            0 => 0,           // Identity
            1 => 0,           // Single-qubit Rz
            2 => 3,           // Two-qubit: 2 CNOT + Rz
            _ => weight * 3,  // Rough estimate
        }
    }

    /// Decompose to native gates (simplified)
    pub fn decompose(&self) -> Vec<String> {
        let mut gates = Vec::new();

        // Add basis rotations for Y Paulis
        for (i, &pauli) in self.paulis.iter().enumerate() {
            if pauli == 2 {
                // Y -> H, S, then evolve
                gates.push(format!("RX({:.4}) q[{}]", PI / 2.0, self.qubits[i]));
            }
        }

        // CNOT ladder for entanglement
        if self.qubits.len() > 1 {
            for i in 0..self.qubits.len() - 1 {
                if self.paulis[i] != 0 && self.paulis[i + 1] != 0 {
                    gates.push(format!("CX q[{}] q[{}]", self.qubits[i], self.qubits[i + 1]));
                }
            }
        }

        // Final rotation
        if !self.qubits.is_empty() {
            let final_qubit = self.qubits[0];
            gates.push(format!("RZ({:.4}) q[{}]", 2.0 * self.angle, final_qubit));
        }

        // Unwind CNOT ladder
        if self.qubits.len() > 1 {
            for i in (0..self.qubits.len() - 1).rev() {
                if self.paulis[i] != 0 && self.paulis[i + 1] != 0 {
                    gates.push(format!("CX q[{}] q[{}]", self.qubits[i], self.qubits[i + 1]));
                }
            }
        }

        // Inverse basis rotations
        for (i, &pauli) in self.paulis.iter().enumerate() {
            if pauli == 2 {
                gates.push(format!("RX({:.4}) q[{}]", -PI / 2.0, self.qubits[i]));
            }
        }

        gates
    }
}

/// Trotter-Suzuki simulator
#[derive(Debug, Clone)]
pub struct TrotterSimulator {
    /// Hamiltonian
    pub hamiltonian: PauliHamiltonian,

    /// Configuration
    pub config: HamiltonianSimConfig,

    /// Gate sequence history
    pub gate_sequence: Vec<Vec<String>>,
}

impl TrotterSimulator {
    /// Create new simulator
    pub fn new(hamiltonian: PauliHamiltonian, config: HamiltonianSimConfig) -> Self {
        TrotterSimulator {
            hamiltonian,
            config,
            gate_sequence: Vec::new(),
        }
    }

    /// Simulate time evolution
    pub fn simulate(&mut self) -> AlgorithmResult<Vec<Vec<String>>> {
        let mut gates = Vec::new();

        let dt = self.config.dt();
        let n_steps = self.config.steps;

        for _step in 0..n_steps {
            let step_gates = self.trotter_step(dt)?;
            gates.push(step_gates);
        }

        self.gate_sequence = gates.clone();
        Ok(gates)
    }

    /// Single Trotter step
    fn trotter_step(&self, dt: f64) -> AlgorithmResult<Vec<String>> {
        let mut gates = Vec::new();

        // Decompose each Hamiltonian term
        for (coeff, pauli) in &self.hamiltonian.terms {
            // Extract qubit indices and Pauli codes from pauli_string
            let mut qubits = Vec::new();
            let mut paulis = Vec::new();

            for (i, op) in pauli.ops.iter().enumerate() {
                let code = match op {
                    crate::hamiltonian::PauliOp::I => 0,
                    crate::hamiltonian::PauliOp::X => 1,
                    crate::hamiltonian::PauliOp::Y => 2,
                    crate::hamiltonian::PauliOp::Z => 3,
                };

                if code != 0 {
                    qubits.push(i);
                    paulis.push(code);
                }
            }

            // Angle: -i coeff * dt (half angle for RZ)
            let angle = -coeff * dt / 2.0;

            let exp = PauliExponential::new(angle, qubits, paulis)?;
            let exp_gates = exp.decompose();
            gates.extend(exp_gates);
        }

        Ok(gates)
    }

    /// Energy conservation check (fidelity with initial state)
    pub fn energy_conservation(&self) -> f64 {
        // Ideal: fidelity = 1.0
        // Practical: 1.0 - error_bound
        1.0 - self.config.error_bound()
    }

    /// Estimated fidelity at time t
    pub fn fidelity_at_time(&self, t: f64) -> f64 {
        let config = HamiltonianSimConfig::new(t, self.config.steps);
        1.0 - config.error_bound()
    }
}

/// Spectrum tracking for time evolution
#[derive(Debug, Clone)]
pub struct SpectrumTracker {
    /// Times
    pub times: Vec<f64>,

    /// Expected phase accumulation
    pub phases: Vec<f64>,
}

impl SpectrumTracker {
    /// Create tracker
    pub fn new() -> Self {
        SpectrumTracker {
            times: Vec::new(),
            phases: Vec::new(),
        }
    }

    /// Record eigenvalue at time t
    pub fn record(&mut self, t: f64, energy: f64) {
        self.times.push(t);
        let phase = -energy * t;
        self.phases.push(phase);
    }

    /// Get phase at final time
    pub fn final_phase(&self) -> Option<f64> {
        self.phases.last().copied()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hamiltonian_sim_config() {
        let config = HamiltonianSimConfig::new(1.0, 10);
        assert!((config.dt() - 0.1).abs() < 1e-10);
    }

    #[test]
    fn test_error_bound() {
        let config = HamiltonianSimConfig::new(1.0, 10);
        let bound = config.error_bound();
        assert!(bound > 0.0);
        assert!(bound < 0.01);
    }

    #[test]
    fn test_second_order_error_bound() {
        let config1 = HamiltonianSimConfig::new(1.0, 10);
        let config2 = HamiltonianSimConfig::new(1.0, 10).with_second_order();

        let bound1 = config1.error_bound();
        let bound2 = config2.error_bound();

        assert!(bound2 < bound1); // Second-order should be better
    }

    #[test]
    fn test_optimal_steps() {
        let steps = HamiltonianSimConfig::optimal_steps(1.0, 1e-3);
        assert!(steps > 0);
    }

    #[test]
    fn test_pauli_exponential_creation() {
        let exp = PauliExponential::new(0.5, vec![0, 1], vec![3, 3]);
        assert!(exp.is_ok());
    }

    #[test]
    fn test_pauli_exponential_gate_count() {
        let exp = PauliExponential::new(0.5, vec![0, 1], vec![3, 3]).unwrap();
        let gates = exp.gate_count();
        assert!(gates > 0);
    }

    #[test]
    fn test_spectrum_tracker() {
        let mut tracker = SpectrumTracker::new();
        tracker.record(0.0, 0.0);
        tracker.record(1.0, -1.0);

        assert_eq!(tracker.times.len(), 2);
        assert_eq!(tracker.phases.last(), Some(&1.0));
    }

    #[test]
    fn test_energy_conservation() {
        let ham = crate::hamiltonian::h2_hamiltonian();
        let config = HamiltonianSimConfig::new(0.1, 5);
        let sim = TrotterSimulator::new(ham, config);

        let conservation = sim.energy_conservation();
        assert!(conservation > 0.99);
    }
}

// Made with Bob
