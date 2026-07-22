//! Gate Cancellation Pass
//!
//! Removes inverse gate pairs that cancel each other out:
//! - H-H → identity
//! - X-X → identity
//! - Y-Y → identity
//! - Z-Z → identity
//! - S-S† → identity
//! - T-T† → identity
//! - Rx(θ)-Rx(-θ) → identity
//!
//! This is a fundamental optimization that reduces gate count and circuit depth.

use qataaum_ir::{Gate, GateKind, GateProgram, GateSequence, GateSequenceId};

/// Gate cancellation optimization pass
pub struct GateCancellationPass {
    /// Number of gates removed
    pub gates_removed: usize,
    
    /// Number of passes made
    pub passes: usize,
}

impl GateCancellationPass {
    /// Create a new gate cancellation pass
    pub fn new() -> Self {
        GateCancellationPass {
            gates_removed: 0,
            passes: 0,
        }
    }
    
    /// Run the pass on a gate program
    pub fn run(&mut self, program: &mut GateProgram) {
        self.gates_removed = 0;
        self.passes = 0;
        
        // Keep running until no more cancellations are found
        loop {
            let removed = self.run_once(program);
            self.passes += 1;
            
            if removed == 0 {
                break;
            }
        }
        
        // Recompute statistics after optimization
        program.compute_stats();
    }
    
    /// Run a single pass over the program
    fn run_once(&mut self, program: &mut GateProgram) -> usize {
        let mut total_removed = 0;
        
        // Process each sequence
        let seq_ids: Vec<GateSequenceId> = program.sequences.keys().copied().collect();
        for seq_id in seq_ids {
            if let Some(seq) = program.sequences.get_mut(&seq_id) {
                let removed = self.cancel_gates_in_sequence(seq);
                total_removed += removed;
                self.gates_removed += removed;
            }
        }
        
        total_removed
    }
    
    /// Cancel gates within a single sequence
    fn cancel_gates_in_sequence(&self, sequence: &mut GateSequence) -> usize {
        let mut removed = 0;
        let mut i = 0;
        
        while i + 1 < sequence.gates.len() {
            let gate1 = &sequence.gates[i];
            let gate2 = &sequence.gates[i + 1];
            
            if self.gates_cancel(gate1, gate2) {
                // Remove both gates
                sequence.gates.remove(i);
                sequence.gates.remove(i); // Index shifts after first removal
                removed += 2;
                
                // Don't increment i - check the new gate at position i
            } else {
                i += 1;
            }
        }
        
        removed
    }
    
    /// Check if two gates cancel each other
    fn gates_cancel(&self, gate1: &Gate, gate2: &Gate) -> bool {
        // Gates must operate on the same qubits
        if gate1.qubits != gate2.qubits {
            return false;
        }
        
        // Gates must have the same classical controls
        if gate1.controls != gate2.controls {
            return false;
        }
        
        // Check if gate kinds are inverses
        self.kinds_cancel(&gate1.kind, &gate2.kind)
    }
    
    /// Check if two gate kinds are inverses
    fn kinds_cancel(&self, kind1: &GateKind, kind2: &GateKind) -> bool {
        match (kind1, kind2) {
            // Self-inverse gates
            (GateKind::H, GateKind::H) => true,
            (GateKind::X, GateKind::X) => true,
            (GateKind::Y, GateKind::Y) => true,
            (GateKind::Z, GateKind::Z) => true,
            (GateKind::CX, GateKind::CX) => true,
            (GateKind::CY, GateKind::CY) => true,
            (GateKind::CZ, GateKind::CZ) => true,
            (GateKind::Swap, GateKind::Swap) => true,
            (GateKind::CCX, GateKind::CCX) => true,
            
            // S and S†
            (GateKind::S, GateKind::Sdg) => true,
            (GateKind::Sdg, GateKind::S) => true,
            
            // T and T†
            (GateKind::T, GateKind::Tdg) => true,
            (GateKind::Tdg, GateKind::T) => true,
            
            // Rotation gates with opposite angles
            (GateKind::Rx(theta1), GateKind::Rx(theta2)) => {
                (theta1 + theta2).abs() < 1e-10
            }
            (GateKind::Ry(theta1), GateKind::Ry(theta2)) => {
                (theta1 + theta2).abs() < 1e-10
            }
            (GateKind::Rz(theta1), GateKind::Rz(theta2)) => {
                (theta1 + theta2).abs() < 1e-10
            }
            (GateKind::Phase(theta1), GateKind::Phase(theta2)) => {
                (theta1 + theta2).abs() < 1e-10
            }
            
            _ => false,
        }
    }
}

impl Default for GateCancellationPass {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use qataaum_ir::{QubitId, BitId};
    use std::f64::consts::PI;
    
    #[test]
    fn test_cancel_hadamard_pair() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        
        // Add H-H pair
        program.add_gate(program.entry, Gate::new(GateKind::H, vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::H, vec![q0]));
        
        let mut pass = GateCancellationPass::new();
        pass.run(&mut program);
        
        assert_eq!(pass.gates_removed, 2);
        assert_eq!(program.sequences.get(&program.entry).unwrap().gates.len(), 0);
    }
    
    #[test]
    fn test_cancel_pauli_pairs() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        
        // Add X-X, Y-Y, Z-Z pairs
        program.add_gate(program.entry, Gate::new(GateKind::X, vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::X, vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::Y, vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::Y, vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::Z, vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::Z, vec![q0]));
        
        let mut pass = GateCancellationPass::new();
        pass.run(&mut program);
        
        assert_eq!(pass.gates_removed, 6);
        assert_eq!(program.sequences.get(&program.entry).unwrap().gates.len(), 0);
    }
    
    #[test]
    fn test_cancel_s_sdg() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        
        // Add S-S† pair
        program.add_gate(program.entry, Gate::new(GateKind::S, vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::Sdg, vec![q0]));
        
        let mut pass = GateCancellationPass::new();
        pass.run(&mut program);
        
        assert_eq!(pass.gates_removed, 2);
        assert_eq!(program.sequences.get(&program.entry).unwrap().gates.len(), 0);
    }
    
    #[test]
    fn test_cancel_t_tdg() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        
        // Add T-T† pair
        program.add_gate(program.entry, Gate::new(GateKind::T, vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::Tdg, vec![q0]));
        
        let mut pass = GateCancellationPass::new();
        pass.run(&mut program);
        
        assert_eq!(pass.gates_removed, 2);
        assert_eq!(program.sequences.get(&program.entry).unwrap().gates.len(), 0);
    }
    
    #[test]
    fn test_cancel_rotation_pairs() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        
        // Add Rx(π/2)-Rx(-π/2) pair
        program.add_gate(program.entry, Gate::new(GateKind::Rx(PI / 2.0), vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::Rx(-PI / 2.0), vec![q0]));
        
        let mut pass = GateCancellationPass::new();
        pass.run(&mut program);
        
        assert_eq!(pass.gates_removed, 2);
        assert_eq!(program.sequences.get(&program.entry).unwrap().gates.len(), 0);
    }
    
    #[test]
    fn test_no_cancel_different_qubits() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        let q1 = program.add_qubit();
        
        // Add H on different qubits
        program.add_gate(program.entry, Gate::new(GateKind::H, vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::H, vec![q1]));
        
        let mut pass = GateCancellationPass::new();
        pass.run(&mut program);
        
        assert_eq!(pass.gates_removed, 0);
        assert_eq!(program.sequences.get(&program.entry).unwrap().gates.len(), 2);
    }
    
    #[test]
    fn test_cancel_cnot_pair() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        let q1 = program.add_qubit();
        
        // Add CX-CX pair (CNOT is self-inverse)
        program.add_gate(program.entry, Gate::new(GateKind::CX, vec![q0, q1]));
        program.add_gate(program.entry, Gate::new(GateKind::CX, vec![q0, q1]));
        
        let mut pass = GateCancellationPass::new();
        pass.run(&mut program);
        
        assert_eq!(pass.gates_removed, 2);
        assert_eq!(program.sequences.get(&program.entry).unwrap().gates.len(), 0);
    }
    
    #[test]
    fn test_multiple_passes() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        
        // Add H-X-X-H (should remove X-X first, then H-H)
        program.add_gate(program.entry, Gate::new(GateKind::H, vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::X, vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::X, vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::H, vec![q0]));
        
        let mut pass = GateCancellationPass::new();
        pass.run(&mut program);
        
        assert_eq!(pass.gates_removed, 4);
        assert!(pass.passes >= 2); // Should take at least 2 passes
        assert_eq!(program.sequences.get(&program.entry).unwrap().gates.len(), 0);
    }
}

// Made with Bob
