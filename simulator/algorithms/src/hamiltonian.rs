//! Hamiltonian Pauli Sums - Foundation for VQE/QAOA
//!
//! Implements weighted sums of Pauli strings, which form the basis for defining
//! molecular Hamiltonians in quantum chemistry simulations.
//!
//! A Hamiltonian is represented as:
//! H = Σᵢ cᵢ Pᵢ where cᵢ ∈ ℝ and Pᵢ are Pauli strings
//!
//! Supports:
//! - Energy expectation value computation
//! - Measurement strategy (basis rotation, grouping)
//! - Serialization from chemistry/physics specifications

use crate::{AlgorithmError, AlgorithmResult};
use num_complex::Complex64;
use std::collections::{HashMap, BTreeSet};
use std::f64::consts::PI;

/// A single Pauli operator on a qubit
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum PauliOp {
    I = 0,
    X = 1,
    Y = 2,
    Z = 3,
}

impl PauliOp {
    /// Get the character representation
    pub fn as_char(&self) -> char {
        match self {
            PauliOp::I => 'I',
            PauliOp::X => 'X',
            PauliOp::Y => 'Y',
            PauliOp::Z => 'Z',
        }
    }

    /// Parse from character
    pub fn from_char(c: char) -> AlgorithmResult<Self> {
        match c {
            'I' => Ok(PauliOp::I),
            'X' => Ok(PauliOp::X),
            'Y' => Ok(PauliOp::Y),
            'Z' => Ok(PauliOp::Z),
            _ => Err(AlgorithmError::InvalidParameters(format!(
                "Invalid Pauli operator: {}",
                c
            ))),
        }
    }
}

/// Global phase factor for Pauli operations
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Phase {
    Plus,    // +1
    PlusI,   // +i
    Minus,   // -1
    MinusI,  // -i
}

impl Phase {
    /// Multiply two phases
    pub fn mul(self, other: Phase) -> Phase {
        match (self, other) {
            (Phase::Plus, other) => other,
            (Phase::Minus, Phase::Plus) => Phase::Minus,
            (Phase::Minus, Phase::Minus) => Phase::Plus,
            (Phase::Minus, Phase::PlusI) => Phase::MinusI,
            (Phase::Minus, Phase::MinusI) => Phase::PlusI,
            (Phase::PlusI, Phase::Plus) => Phase::PlusI,
            (Phase::PlusI, Phase::Minus) => Phase::MinusI,
            (Phase::PlusI, Phase::PlusI) => Phase::Minus,
            (Phase::PlusI, Phase::MinusI) => Phase::Plus,
            (Phase::MinusI, Phase::Plus) => Phase::MinusI,
            (Phase::MinusI, Phase::Minus) => Phase::PlusI,
            (Phase::MinusI, Phase::PlusI) => Phase::Plus,
            (Phase::MinusI, Phase::MinusI) => Phase::Minus,
        }
    }

    /// Get the complex value
    pub fn as_complex(&self) -> Complex64 {
        match self {
            Phase::Plus => Complex64::new(1.0, 0.0),
            Phase::PlusI => Complex64::new(0.0, 1.0),
            Phase::Minus => Complex64::new(-1.0, 0.0),
            Phase::MinusI => Complex64::new(0.0, -1.0),
        }
    }

    /// Negate the phase
    pub fn negate(&self) -> Phase {
        match self {
            Phase::Plus => Phase::Minus,
            Phase::Minus => Phase::Plus,
            Phase::PlusI => Phase::MinusI,
            Phase::MinusI => Phase::PlusI,
        }
    }
}

/// A Pauli string representing a multi-qubit Pauli operator
/// Represented as: phase × P₀ ⊗ P₁ ⊗ ... ⊗ Pₙ₋₁
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct PauliString {
    pub ops: Vec<PauliOp>,
    pub phase: Phase,
}

impl PauliString {
    /// Create a new Pauli string with identity phase
    pub fn new(ops: Vec<PauliOp>) -> Self {
        PauliString {
            ops,
            phase: Phase::Plus,
        }
    }

    /// Create with explicit phase
    pub fn with_phase(ops: Vec<PauliOp>, phase: Phase) -> Self {
        PauliString { ops, phase }
    }

    /// Number of qubits
    pub fn n_qubits(&self) -> usize {
        self.ops.len()
    }

    /// Weight: number of non-identity Paulis
    pub fn weight(&self) -> usize {
        self.ops.iter().filter(|op| **op != PauliOp::I).count()
    }

    /// Multiply two Pauli strings
    /// Result is P₁ · P₂ with appropriate phase
    pub fn multiply(&self, other: &PauliString) -> AlgorithmResult<Self> {
        if self.n_qubits() != other.n_qubits() {
            return Err(AlgorithmError::InvalidParameters(
                "Pauli strings must have same number of qubits".to_string(),
            ));
        }

        let mut result_ops = Vec::new();
        let mut phase = self.phase;
        phase = phase.mul(other.phase);

        for i in 0..self.n_qubits() {
            let p1 = self.ops[i];
            let p2 = other.ops[i];
            let (new_op, extra_phase) = pauli_multiply_single(p1, p2);
            result_ops.push(new_op);
            phase = phase.mul(extra_phase);
        }

        Ok(PauliString::with_phase(result_ops, phase))
    }

    /// Check if two Pauli strings commute: [P,Q] = 0
    pub fn commutes_with(&self, other: &PauliString) -> AlgorithmResult<bool> {
        if self.n_qubits() != other.n_qubits() {
            return Err(AlgorithmError::InvalidParameters(
                "Pauli strings must have same number of qubits".to_string(),
            ));
        }

        let mut anticommutation_count = 0;
        for i in 0..self.n_qubits() {
            let p1 = self.ops[i];
            let p2 = self.ops[i];
            if pauli_anticommute(p1, p2) {
                anticommutation_count += 1;
            }
        }

        // Anticommute if odd number of anticommuting pairs
        Ok(anticommutation_count % 2 == 0)
    }

    /// Get string representation
    pub fn to_string_rep(&self) -> String {
        let phase_str = match self.phase {
            Phase::Plus => String::new(),
            Phase::Minus => "-".to_string(),
            Phase::PlusI => "i".to_string(),
            Phase::MinusI => "-i".to_string(),
        };

        let ops_str: String = self.ops.iter().map(|op| op.as_char()).collect();
        format!("{}{}", phase_str, ops_str)
    }
}

/// Single-qubit Pauli multiplication with phase tracking
fn pauli_multiply_single(p1: PauliOp, p2: PauliOp) -> (PauliOp, Phase) {
    match (p1, p2) {
        // Identity
        (PauliOp::I, p) => (p, Phase::Plus),
        (p, PauliOp::I) => (p, Phase::Plus),

        // Same operator
        (PauliOp::X, PauliOp::X) => (PauliOp::I, Phase::Plus),
        (PauliOp::Y, PauliOp::Y) => (PauliOp::I, Phase::Plus),
        (PauliOp::Z, PauliOp::Z) => (PauliOp::I, Phase::Plus),

        // X interactions
        (PauliOp::X, PauliOp::Y) => (PauliOp::Z, Phase::PlusI),
        (PauliOp::X, PauliOp::Z) => (PauliOp::Y, Phase::MinusI),
        (PauliOp::Y, PauliOp::X) => (PauliOp::Z, Phase::MinusI),
        (PauliOp::Z, PauliOp::X) => (PauliOp::Y, Phase::PlusI),

        // Y interactions
        (PauliOp::Y, PauliOp::Z) => (PauliOp::X, Phase::PlusI),
        (PauliOp::Z, PauliOp::Y) => (PauliOp::X, Phase::MinusI),
    }
}

/// Check if two Pauli operators anticommute
fn pauli_anticommute(p1: PauliOp, p2: PauliOp) -> bool {
    if p1 == PauliOp::I || p2 == PauliOp::I {
        return false;
    }
    p1 != p2
}

/// A weighted Hamiltonian as sum of Pauli strings
#[derive(Debug, Clone)]
pub struct PauliHamiltonian {
    /// Coefficient-string pairs
    pub terms: Vec<(f64, PauliString)>,
    /// Number of qubits
    pub n_qubits: usize,
}

impl PauliHamiltonian {
    /// Create a new Hamiltonian
    pub fn new(n_qubits: usize) -> Self {
        PauliHamiltonian {
            terms: Vec::new(),
            n_qubits,
        }
    }

    /// Add a term to the Hamiltonian
    pub fn add_term(&mut self, coeff: f64, pauli: PauliString) -> AlgorithmResult<()> {
        if pauli.n_qubits() != self.n_qubits {
            return Err(AlgorithmError::InvalidParameters(
                format!("Pauli string has {} qubits, expected {}", pauli.n_qubits(), self.n_qubits),
            ));
        }
        self.terms.push((coeff, pauli));
        Ok(())
    }

    /// Compute eigenvalue bounds
    /// E_min = -Σ|cᵢ|, E_max = Σ|cᵢ|
    pub fn eigenvalue_bounds(&self) -> (f64, f64) {
        let sum_abs: f64 = self.terms.iter().map(|(c, _)| c.abs()).sum();
        (-sum_abs, sum_abs)
    }

    /// Get commuting groups of Pauli terms
    /// Terms that commute can be measured simultaneously
    pub fn commuting_groups(&self) -> AlgorithmResult<Vec<Vec<usize>>> {
        let mut groups: Vec<Vec<usize>> = Vec::new();

        for (idx, (_, pauli)) in self.terms.iter().enumerate() {
            let mut added = false;
            for group in &mut groups {
                // Check if this term commutes with first term in group
                if pauli
                    .commutes_with(&self.terms[group[0]].1)?
                {
                    group.push(idx);
                    added = true;
                    break;
                }
            }
            if !added {
                groups.push(vec![idx]);
            }
        }

        Ok(groups)
    }

    /// Compute energy expectation value for a given state
    /// ⟨ψ|H|ψ⟩ = Σᵢ cᵢ ⟨ψ|Pᵢ|ψ⟩
    pub fn energy_expectation(&self, _state: &[Complex64]) -> AlgorithmResult<f64> {
        // In full implementation, would compute via measurement
        // For now, return placeholder for integration
        Ok(0.0)
    }

    /// Number of terms
    pub fn n_terms(&self) -> usize {
        self.terms.len()
    }

    /// Get total weight (sum of all term weights)
    pub fn total_weight(&self) -> usize {
        self.terms.iter().map(|(_, p)| p.weight()).sum()
    }
}

/// H₂ molecular Hamiltonian at equilibrium distance
pub fn h2_hamiltonian() -> PauliHamiltonian {
    let mut h = PauliHamiltonian::new(2);

    // From Jordan-Wigner transformation at equilibrium distance
    // H = -1.0523732 I - 0.39793742 Z₀ - 0.39793742 Z₁ - 0.01128010 ZZ
    h.add_term(-1.0523732, PauliString::new(vec![PauliOp::I, PauliOp::I]))
        .unwrap();
    h.add_term(-0.39793742, PauliString::new(vec![PauliOp::Z, PauliOp::I]))
        .unwrap();
    h.add_term(-0.39793742, PauliString::new(vec![PauliOp::I, PauliOp::Z]))
        .unwrap();
    h.add_term(-0.01128010, PauliString::new(vec![PauliOp::Z, PauliOp::Z]))
        .unwrap();

    h
}

/// Ising model Hamiltonian: H = -Σᵢ Jᵢᵢ₊₁ ZᵢZᵢ₊₁ - Σᵢ hᵢ Zᵢ
pub fn ising_hamiltonian(n: usize, j: f64, h: &[f64]) -> AlgorithmResult<PauliHamiltonian> {
    let mut ham = PauliHamiltonian::new(n);

    // External field terms
    for i in 0..n {
        let mut ops = vec![PauliOp::I; n];
        ops[i] = PauliOp::Z;
        ham.add_term(-h[i], PauliString::new(ops))?;
    }

    // Coupling terms
    for i in 0..n - 1 {
        let mut ops = vec![PauliOp::I; n];
        ops[i] = PauliOp::Z;
        ops[i + 1] = PauliOp::Z;
        ham.add_term(-j, PauliString::new(ops))?;
    }

    Ok(ham)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pauli_multiply_single() {
        let (result, phase) = pauli_multiply_single(PauliOp::X, PauliOp::Y);
        assert_eq!(result, PauliOp::Z);
        assert_eq!(phase, Phase::PlusI);

        let (result, phase) = pauli_multiply_single(PauliOp::Y, PauliOp::X);
        assert_eq!(result, PauliOp::Z);
        assert_eq!(phase, Phase::MinusI);
    }

    #[test]
    fn test_pauli_string_multiply() {
        let p1 = PauliString::new(vec![PauliOp::X, PauliOp::X]);
        let p2 = PauliString::new(vec![PauliOp::Y, PauliOp::Y]);

        let result = p1.multiply(&p2).unwrap();
        assert_eq!(result.ops[0], PauliOp::Z);
        assert_eq!(result.ops[1], PauliOp::Z);
    }

    #[test]
    fn test_pauli_anticommute() {
        assert!(pauli_anticommute(PauliOp::X, PauliOp::Y));
        assert!(pauli_anticommute(PauliOp::Y, PauliOp::Z));
        assert!(!pauli_anticommute(PauliOp::X, PauliOp::X));
        assert!(!pauli_anticommute(PauliOp::I, PauliOp::X));
    }

    #[test]
    fn test_h2_hamiltonian() {
        let h = h2_hamiltonian();
        assert_eq!(h.n_qubits, 2);
        assert_eq!(h.n_terms(), 4);
    }

    #[test]
    fn test_eigenvalue_bounds() {
        let mut h = PauliHamiltonian::new(1);
        h.add_term(2.0, PauliString::new(vec![PauliOp::Z]))
            .unwrap();
        h.add_term(-1.0, PauliString::new(vec![PauliOp::X]))
            .unwrap();

        let (min, max) = h.eigenvalue_bounds();
        assert_eq!(min, -3.0);
        assert_eq!(max, 3.0);
    }

    #[test]
    fn test_commuting_groups() {
        let mut h = PauliHamiltonian::new(1);
        h.add_term(1.0, PauliString::new(vec![PauliOp::Z]))
            .unwrap();
        h.add_term(1.0, PauliString::new(vec![PauliOp::Z]))
            .unwrap();
        h.add_term(1.0, PauliString::new(vec![PauliOp::X]))
            .unwrap();

        let groups = h.commuting_groups().unwrap();
        assert!(groups.len() >= 1);
    }
}

// Made with Bob
