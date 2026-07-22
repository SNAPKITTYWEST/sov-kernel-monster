//! QATAAUM State-Vector Quantum Simulator
//!
//! A simple but correct state-vector simulator for quantum circuits.
//! Supports circuits up to ~10 qubits (limited by memory: 2^n complex amplitudes).
//!
//! Clean-room implementation based on standard quantum mechanics textbooks.

use num_complex::Complex64;
use qataaum_ir::{Gate, GateKind, GateProgram, GateSequenceId, GateTerminator, QubitId, BitId};
use std::collections::HashMap;
use std::f64::consts::PI;

pub mod state;
pub mod gates;
pub mod executor;

pub use state::*;
pub use gates::*;
pub use executor::*;

/// Result type for simulator operations
pub type SimResult<T> = Result<T, SimError>;

/// Simulator errors
#[derive(Debug, Clone)]
pub enum SimError {
    /// Invalid qubit index
    InvalidQubit(usize),
    
    /// Invalid classical bit index
    InvalidBit(usize),
    
    /// State not normalized
    NotNormalized,
    
    /// Unsupported gate
    UnsupportedGate(String),
    
    /// Too many qubits for simulator
    TooManyQubits(usize),
    
    /// Invalid gate parameters
    InvalidParameters(String),
}

impl std::fmt::Display for SimError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SimError::InvalidQubit(q) => write!(f, "Invalid qubit index: {}", q),
            SimError::InvalidBit(b) => write!(f, "Invalid bit index: {}", b),
            SimError::NotNormalized => write!(f, "State vector not normalized"),
            SimError::UnsupportedGate(g) => write!(f, "Unsupported gate: {}", g),
            SimError::TooManyQubits(n) => write!(f, "Too many qubits: {} (max ~20)", n),
            SimError::InvalidParameters(msg) => write!(f, "Invalid parameters: {}", msg),
        }
    }
}

impl std::error::Error for SimError {}

// Made with Bob