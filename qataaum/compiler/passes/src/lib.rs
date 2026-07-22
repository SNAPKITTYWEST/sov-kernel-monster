//! QATAAUM Compiler Optimization Passes
//!
//! This module provides optimization passes for quantum circuits:
//! - Gate cancellation (inverse pair elimination)
//! - Rotation folding (combining consecutive rotations)
//! - Commutation-based reordering
//! - Dead code elimination
//! - Hardware-aware scheduling
//! - Pulse-level compilation
//!
//! Clean-room implementation - not derived from Qiskit

pub mod gate_cancellation;
pub mod rotation_folding;
pub mod pass_manager;
pub mod scheduler;
pub mod pulse_compiler;

pub use gate_cancellation::*;
pub use rotation_folding::*;
pub use pass_manager::*;
pub use scheduler::*;
pub use pulse_compiler::*;

// Made with Bob