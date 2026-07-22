//! Quantum State Vector Representation
//!
//! Represents the quantum state as a complex vector of amplitudes.
//! For n qubits, the state has 2^n complex amplitudes.

use num_complex::Complex64;
use crate::{SimError, SimResult};

/// A quantum state vector
#[derive(Debug, Clone)]
pub struct StateVector {
    /// Number of qubits
    pub num_qubits: usize,
    
    /// Complex amplitudes (length = 2^num_qubits)
    pub amplitudes: Vec<Complex64>,
}

impl StateVector {
    /// Create a new state vector initialized to |0...0⟩
    pub fn new(num_qubits: usize) -> SimResult<Self> {
        if num_qubits > 20 {
            return Err(SimError::TooManyQubits(num_qubits));
        }
        
        let size = 1 << num_qubits; // 2^num_qubits
        let mut amplitudes = vec![Complex64::new(0.0, 0.0); size];
        amplitudes[0] = Complex64::new(1.0, 0.0); // |0...0⟩ state
        
        Ok(StateVector {
            num_qubits,
            amplitudes,
        })
    }
    
    /// Create a state vector from amplitudes
    pub fn from_amplitudes(num_qubits: usize, amplitudes: Vec<Complex64>) -> SimResult<Self> {
        let expected_size = 1 << num_qubits;
        if amplitudes.len() != expected_size {
            return Err(SimError::InvalidParameters(
                format!("Expected {} amplitudes for {} qubits, got {}", 
                    expected_size, num_qubits, amplitudes.len())
            ));
        }
        
        let state = StateVector {
            num_qubits,
            amplitudes,
        };
        
        if !state.is_normalized() {
            return Err(SimError::NotNormalized);
        }
        
        Ok(state)
    }
    
    /// Check if the state is normalized (sum of |amplitude|^2 = 1)
    pub fn is_normalized(&self) -> bool {
        let sum: f64 = self.amplitudes.iter()
            .map(|a| a.norm_sqr())
            .sum();
        (sum - 1.0).abs() < 1e-10
    }
    
    /// Normalize the state vector
    pub fn normalize(&mut self) {
        let norm: f64 = self.amplitudes.iter()
            .map(|a| a.norm_sqr())
            .sum::<f64>()
            .sqrt();
        
        if norm > 1e-10 {
            for amp in &mut self.amplitudes {
                *amp /= norm;
            }
        }
    }
    
    /// Get the probability of measuring a specific computational basis state
    pub fn probability(&self, basis_state: usize) -> f64 {
        if basis_state >= self.amplitudes.len() {
            return 0.0;
        }
        self.amplitudes[basis_state].norm_sqr()
    }
    
    /// Get the amplitude for a specific basis state
    pub fn amplitude(&self, basis_state: usize) -> Complex64 {
        if basis_state >= self.amplitudes.len() {
            Complex64::new(0.0, 0.0)
        } else {
            self.amplitudes[basis_state]
        }
    }
    
    /// Measure a single qubit (returns 0 or 1)
    pub fn measure_qubit(&mut self, qubit: usize, rng: &mut impl rand::Rng) -> SimResult<u8> {
        if qubit >= self.num_qubits {
            return Err(SimError::InvalidQubit(qubit));
        }
        
        // Calculate probability of measuring |1⟩
        let prob_one = self.probability_qubit_one(qubit);
        
        // Sample measurement outcome
        let outcome = if rng.gen::<f64>() < prob_one { 1 } else { 0 };
        
        // Collapse state
        self.collapse_qubit(qubit, outcome);
        
        Ok(outcome)
    }
    
    /// Calculate probability of measuring |1⟩ on a qubit
    fn probability_qubit_one(&self, qubit: usize) -> f64 {
        let mut prob = 0.0;
        let qubit_mask = 1 << qubit;
        
        for (i, amp) in self.amplitudes.iter().enumerate() {
            if (i & qubit_mask) != 0 {
                prob += amp.norm_sqr();
            }
        }
        
        prob
    }
    
    /// Collapse state after measuring a qubit
    fn collapse_qubit(&mut self, qubit: usize, outcome: u8) {
        let qubit_mask = 1 << qubit;
        
        // Zero out amplitudes inconsistent with measurement
        for (i, amp) in self.amplitudes.iter_mut().enumerate() {
            let qubit_value = ((i & qubit_mask) != 0) as u8;
            if qubit_value != outcome {
                *amp = Complex64::new(0.0, 0.0);
            }
        }
        
        // Renormalize
        self.normalize();
    }
    
    /// Reset a qubit to |0⟩
    pub fn reset_qubit(&mut self, qubit: usize) -> SimResult<()> {
        if qubit >= self.num_qubits {
            return Err(SimError::InvalidQubit(qubit));
        }
        
        let qubit_mask = 1 << qubit;
        let size = self.amplitudes.len();
        
        // Collect amplitudes to move
        let mut moves = Vec::new();
        for i in 0..size {
            if (i & qubit_mask) != 0 {
                let target = i & !qubit_mask; // Clear the qubit bit
                moves.push((target, i, self.amplitudes[i]));
            }
        }
        
        // Apply moves
        for (target, source, amp) in moves {
            self.amplitudes[target] += amp;
            self.amplitudes[source] = Complex64::new(0.0, 0.0);
        }
        
        self.normalize();
        Ok(())
    }
    
    /// Get a string representation of the state
    pub fn to_string_compact(&self) -> String {
        let mut result = String::new();
        let threshold = 1e-10;
        
        for (i, amp) in self.amplitudes.iter().enumerate() {
            if amp.norm_sqr() > threshold {
                if !result.is_empty() {
                    result.push_str(" + ");
                }
                
                // Format amplitude
                let re = amp.re;
                let im = amp.im;
                
                if im.abs() < threshold {
                    result.push_str(&format!("{:.4}", re));
                } else if re.abs() < threshold {
                    result.push_str(&format!("{:.4}i", im));
                } else {
                    result.push_str(&format!("({:.4}{:+.4}i)", re, im));
                }
                
                // Format basis state
                result.push_str(&format!("|{:0width$b}⟩", i, width = self.num_qubits));
            }
        }
        
        if result.is_empty() {
            result = "0".to_string();
        }
        
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_new_state() {
        let state = StateVector::new(2).unwrap();
        assert_eq!(state.num_qubits, 2);
        assert_eq!(state.amplitudes.len(), 4);
        assert_eq!(state.amplitude(0), Complex64::new(1.0, 0.0));
        assert_eq!(state.amplitude(1), Complex64::new(0.0, 0.0));
        assert!(state.is_normalized());
    }
    
    #[test]
    fn test_probability() {
        let state = StateVector::new(2).unwrap();
        assert!((state.probability(0) - 1.0).abs() < 1e-10);
        assert!(state.probability(1).abs() < 1e-10);
    }
    
    #[test]
    fn test_normalize() {
        let amplitudes = vec![
            Complex64::new(1.0, 0.0),
            Complex64::new(1.0, 0.0),
            Complex64::new(0.0, 0.0),
            Complex64::new(0.0, 0.0),
        ];
        
        let mut state = StateVector {
            num_qubits: 2,
            amplitudes,
        };
        
        assert!(!state.is_normalized());
        state.normalize();
        assert!(state.is_normalized());
        
        let expected = 1.0 / 2.0_f64.sqrt();
        assert!((state.amplitude(0).re - expected).abs() < 1e-10);
        assert!((state.amplitude(1).re - expected).abs() < 1e-10);
    }
    
    #[test]
    fn test_too_many_qubits() {
        let result = StateVector::new(25);
        assert!(matches!(result, Err(SimError::TooManyQubits(25))));
    }
}

// Made with Bob
