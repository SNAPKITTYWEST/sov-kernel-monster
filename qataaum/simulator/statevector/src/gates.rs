//! Quantum Gate Application
//!
//! Applies quantum gates to state vectors using matrix-vector multiplication.
//! Gates are represented as unitary matrices.

use num_complex::Complex64;
use crate::{StateVector, SimError, SimResult};
use std::f64::consts::PI;

/// Apply a single-qubit gate to a state vector
pub fn apply_single_qubit_gate(
    state: &mut StateVector,
    qubit: usize,
    matrix: &[[Complex64; 2]; 2],
) -> SimResult<()> {
    if qubit >= state.num_qubits {
        return Err(SimError::InvalidQubit(qubit));
    }
    
    let qubit_mask = 1 << qubit;
    let size = state.amplitudes.len();
    
    // Apply gate to each pair of amplitudes
    for i in 0..size {
        if (i & qubit_mask) == 0 {
            let j = i | qubit_mask; // Flip the qubit bit
            
            let amp0 = state.amplitudes[i];
            let amp1 = state.amplitudes[j];
            
            // Matrix multiplication: [a b] [amp0]
            //                        [c d] [amp1]
            state.amplitudes[i] = matrix[0][0] * amp0 + matrix[0][1] * amp1;
            state.amplitudes[j] = matrix[1][0] * amp0 + matrix[1][1] * amp1;
        }
    }
    
    Ok(())
}

/// Apply a two-qubit gate to a state vector
pub fn apply_two_qubit_gate(
    state: &mut StateVector,
    control: usize,
    target: usize,
    matrix: &[[Complex64; 4]; 4],
) -> SimResult<()> {
    if control >= state.num_qubits {
        return Err(SimError::InvalidQubit(control));
    }
    if target >= state.num_qubits {
        return Err(SimError::InvalidQubit(target));
    }
    if control == target {
        return Err(SimError::InvalidParameters("Control and target must be different".to_string()));
    }
    
    let control_mask = 1 << control;
    let target_mask = 1 << target;
    let size = state.amplitudes.len();
    
    // Apply gate to each group of 4 amplitudes
    for i in 0..size {
        if (i & control_mask) == 0 && (i & target_mask) == 0 {
            let i00 = i;
            let i01 = i | target_mask;
            let i10 = i | control_mask;
            let i11 = i | control_mask | target_mask;
            
            let amp00 = state.amplitudes[i00];
            let amp01 = state.amplitudes[i01];
            let amp10 = state.amplitudes[i10];
            let amp11 = state.amplitudes[i11];
            
            // Matrix multiplication
            state.amplitudes[i00] = matrix[0][0] * amp00 + matrix[0][1] * amp01 + matrix[0][2] * amp10 + matrix[0][3] * amp11;
            state.amplitudes[i01] = matrix[1][0] * amp00 + matrix[1][1] * amp01 + matrix[1][2] * amp10 + matrix[1][3] * amp11;
            state.amplitudes[i10] = matrix[2][0] * amp00 + matrix[2][1] * amp01 + matrix[2][2] * amp10 + matrix[2][3] * amp11;
            state.amplitudes[i11] = matrix[3][0] * amp00 + matrix[3][1] * amp01 + matrix[3][2] * amp10 + matrix[3][3] * amp11;
        }
    }
    
    Ok(())
}

// Standard gate matrices

/// Pauli-X (NOT) gate matrix
pub fn x_matrix() -> [[Complex64; 2]; 2] {
    [
        [Complex64::new(0.0, 0.0), Complex64::new(1.0, 0.0)],
        [Complex64::new(1.0, 0.0), Complex64::new(0.0, 0.0)],
    ]
}

/// Pauli-Y gate matrix
pub fn y_matrix() -> [[Complex64; 2]; 2] {
    [
        [Complex64::new(0.0, 0.0), Complex64::new(0.0, -1.0)],
        [Complex64::new(0.0, 1.0), Complex64::new(0.0, 0.0)],
    ]
}

/// Pauli-Z gate matrix
pub fn z_matrix() -> [[Complex64; 2]; 2] {
    [
        [Complex64::new(1.0, 0.0), Complex64::new(0.0, 0.0)],
        [Complex64::new(0.0, 0.0), Complex64::new(-1.0, 0.0)],
    ]
}

/// Hadamard gate matrix
pub fn h_matrix() -> [[Complex64; 2]; 2] {
    let inv_sqrt2 = 1.0 / 2.0_f64.sqrt();
    [
        [Complex64::new(inv_sqrt2, 0.0), Complex64::new(inv_sqrt2, 0.0)],
        [Complex64::new(inv_sqrt2, 0.0), Complex64::new(-inv_sqrt2, 0.0)],
    ]
}

/// S gate (√Z) matrix
pub fn s_matrix() -> [[Complex64; 2]; 2] {
    [
        [Complex64::new(1.0, 0.0), Complex64::new(0.0, 0.0)],
        [Complex64::new(0.0, 0.0), Complex64::new(0.0, 1.0)],
    ]
}

/// S† gate matrix
pub fn sdg_matrix() -> [[Complex64; 2]; 2] {
    [
        [Complex64::new(1.0, 0.0), Complex64::new(0.0, 0.0)],
        [Complex64::new(0.0, 0.0), Complex64::new(0.0, -1.0)],
    ]
}

/// T gate (√S) matrix
pub fn t_matrix() -> [[Complex64; 2]; 2] {
    let phase = Complex64::new(0.0, PI / 4.0).exp();
    [
        [Complex64::new(1.0, 0.0), Complex64::new(0.0, 0.0)],
        [Complex64::new(0.0, 0.0), phase],
    ]
}

/// T† gate matrix
pub fn tdg_matrix() -> [[Complex64; 2]; 2] {
    let phase = Complex64::new(0.0, -PI / 4.0).exp();
    [
        [Complex64::new(1.0, 0.0), Complex64::new(0.0, 0.0)],
        [Complex64::new(0.0, 0.0), phase],
    ]
}

/// Rotation around X axis
pub fn rx_matrix(theta: f64) -> [[Complex64; 2]; 2] {
    let cos = (theta / 2.0).cos();
    let sin = (theta / 2.0).sin();
    [
        [Complex64::new(cos, 0.0), Complex64::new(0.0, -sin)],
        [Complex64::new(0.0, -sin), Complex64::new(cos, 0.0)],
    ]
}

/// Rotation around Y axis
pub fn ry_matrix(theta: f64) -> [[Complex64; 2]; 2] {
    let cos = (theta / 2.0).cos();
    let sin = (theta / 2.0).sin();
    [
        [Complex64::new(cos, 0.0), Complex64::new(-sin, 0.0)],
        [Complex64::new(sin, 0.0), Complex64::new(cos, 0.0)],
    ]
}

/// Rotation around Z axis
pub fn rz_matrix(theta: f64) -> [[Complex64; 2]; 2] {
    let phase_neg = Complex64::new(0.0, -theta / 2.0).exp();
    let phase_pos = Complex64::new(0.0, theta / 2.0).exp();
    [
        [phase_neg, Complex64::new(0.0, 0.0)],
        [Complex64::new(0.0, 0.0), phase_pos],
    ]
}

/// Phase gate
pub fn phase_matrix(theta: f64) -> [[Complex64; 2]; 2] {
    let phase = Complex64::new(0.0, theta).exp();
    [
        [Complex64::new(1.0, 0.0), Complex64::new(0.0, 0.0)],
        [Complex64::new(0.0, 0.0), phase],
    ]
}

/// CNOT (CX) gate matrix
pub fn cx_matrix() -> [[Complex64; 4]; 4] {
    let zero = Complex64::new(0.0, 0.0);
    let one = Complex64::new(1.0, 0.0);
    [
        [one, zero, zero, zero],
        [zero, one, zero, zero],
        [zero, zero, zero, one],
        [zero, zero, one, zero],
    ]
}

/// CZ gate matrix
pub fn cz_matrix() -> [[Complex64; 4]; 4] {
    let zero = Complex64::new(0.0, 0.0);
    let one = Complex64::new(1.0, 0.0);
    let neg_one = Complex64::new(-1.0, 0.0);
    [
        [one, zero, zero, zero],
        [zero, one, zero, zero],
        [zero, zero, one, zero],
        [zero, zero, zero, neg_one],
    ]
}

/// SWAP gate matrix
pub fn swap_matrix() -> [[Complex64; 4]; 4] {
    let zero = Complex64::new(0.0, 0.0);
    let one = Complex64::new(1.0, 0.0);
    [
        [one, zero, zero, zero],
        [zero, zero, one, zero],
        [zero, one, zero, zero],
        [zero, zero, zero, one],
    ]
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_x_gate() {
        let mut state = StateVector::new(1).unwrap();
        apply_single_qubit_gate(&mut state, 0, &x_matrix()).unwrap();
        
        // Should be in |1⟩ state
        assert!((state.amplitude(0).norm() - 0.0).abs() < 1e-10);
        assert!((state.amplitude(1).norm() - 1.0).abs() < 1e-10);
    }
    
    #[test]
    fn test_h_gate() {
        let mut state = StateVector::new(1).unwrap();
        apply_single_qubit_gate(&mut state, 0, &h_matrix()).unwrap();
        
        // Should be in |+⟩ state: (|0⟩ + |1⟩)/√2
        let expected = 1.0 / 2.0_f64.sqrt();
        assert!((state.amplitude(0).re - expected).abs() < 1e-10);
        assert!((state.amplitude(1).re - expected).abs() < 1e-10);
    }
    
    #[test]
    fn test_cnot_gate() {
        let mut state = StateVector::new(2).unwrap();
        
        // Apply X to control qubit
        apply_single_qubit_gate(&mut state, 0, &x_matrix()).unwrap();
        
        // Apply CNOT
        apply_two_qubit_gate(&mut state, 0, 1, &cx_matrix()).unwrap();
        
        // Should be in |11⟩ state
        assert!((state.amplitude(0).norm() - 0.0).abs() < 1e-10);
        assert!((state.amplitude(1).norm() - 0.0).abs() < 1e-10);
        assert!((state.amplitude(2).norm() - 0.0).abs() < 1e-10);
        assert!((state.amplitude(3).norm() - 1.0).abs() < 1e-10);
    }
    
    #[test]
    fn test_bell_state() {
        let mut state = StateVector::new(2).unwrap();
        
        // Create Bell state: (|00⟩ + |11⟩)/√2
        apply_single_qubit_gate(&mut state, 0, &h_matrix()).unwrap();
        apply_two_qubit_gate(&mut state, 0, 1, &cx_matrix()).unwrap();
        
        let expected = 1.0 / 2.0_f64.sqrt();
        assert!((state.amplitude(0).re - expected).abs() < 1e-10);
        assert!((state.amplitude(1).norm() - 0.0).abs() < 1e-10);
        assert!((state.amplitude(2).norm() - 0.0).abs() < 1e-10);
        assert!((state.amplitude(3).re - expected).abs() < 1e-10);
    }
}

// Made with Bob
