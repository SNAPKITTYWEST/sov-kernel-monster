//! Rotation Folding Pass
//!
//! Combines consecutive rotation gates on the same qubit:
//! - Rx(θ₁) + Rx(θ₂) → Rx(θ₁ + θ₂)
//! - Ry(θ₁) + Ry(θ₂) → Ry(θ₁ + θ₂)
//! - Rz(θ₁) + Rz(θ₂) → Rz(θ₁ + θ₂)
//! - Phase(θ₁) + Phase(θ₂) → Phase(θ₁ + θ₂)
//!
//! Also handles special cases:
//! - Rz(2π) → identity (removed)
//! - Rz(π) → Z gate
//! - Rz(π/2) → S gate
//! - Rz(π/4) → T gate

use qataaum_ir::{Gate, GateKind, GateProgram, GateSequence, GateSequenceId};
use std::f64::consts::PI;

/// Rotation folding optimization pass
pub struct RotationFoldingPass {
    /// Number of rotations folded
    pub rotations_folded: usize,
    
    /// Number of rotations simplified
    pub rotations_simplified: usize,
    
    /// Number of passes made
    pub passes: usize,
}

impl RotationFoldingPass {
    /// Create a new rotation folding pass
    pub fn new() -> Self {
        RotationFoldingPass {
            rotations_folded: 0,
            rotations_simplified: 0,
            passes: 0,
        }
    }
    
    /// Run the pass on a gate program
    pub fn run(&mut self, program: &mut GateProgram) {
        self.rotations_folded = 0;
        self.rotations_simplified = 0;
        self.passes = 0;
        
        // Keep running until no more folding is possible
        loop {
            let folded = self.run_once(program);
            self.passes += 1;
            
            if folded == 0 {
                break;
            }
        }
        
        // Recompute statistics after optimization
        program.compute_stats();
    }
    
    /// Run a single pass over the program
    fn run_once(&mut self, program: &mut GateProgram) -> usize {
        let mut total_folded = 0;
        
        // Process each sequence
        let seq_ids: Vec<GateSequenceId> = program.sequences.keys().copied().collect();
        for seq_id in seq_ids {
            if let Some(seq) = program.sequences.get_mut(&seq_id) {
                let folded = self.fold_rotations_in_sequence(seq);
                total_folded += folded;
            }
        }
        
        total_folded
    }
    
    /// Fold rotations within a single sequence
    fn fold_rotations_in_sequence(&mut self, sequence: &mut GateSequence) -> usize {
        let mut folded = 0;
        let mut i = 0;
        
        while i + 1 < sequence.gates.len() {
            let gate1 = &sequence.gates[i];
            let gate2 = &sequence.gates[i + 1];
            
            if let Some(combined) = self.try_fold_rotations(gate1, gate2) {
                // Replace first gate with combined rotation
                sequence.gates[i] = combined;
                // Remove second gate
                sequence.gates.remove(i + 1);
                
                self.rotations_folded += 1;
                folded += 1;
                
                // Don't increment i - check if we can fold more
            } else {
                i += 1;
            }
        }
        
        // Simplify individual rotations
        for gate in &mut sequence.gates {
            if self.simplify_rotation(gate) {
                self.rotations_simplified += 1;
                folded += 1;
            }
        }
        
        // Remove identity rotations (angle ≈ 0 or ≈ 2πn)
        sequence.gates.retain(|gate| !self.is_identity_rotation(gate));
        
        folded
    }
    
    /// Try to fold two consecutive rotation gates
    fn try_fold_rotations(&self, gate1: &Gate, gate2: &Gate) -> Option<Gate> {
        // Gates must operate on the same qubits
        if gate1.qubits != gate2.qubits {
            return None;
        }
        
        // Gates must have the same classical controls
        if gate1.controls != gate2.controls {
            return None;
        }
        
        // Try to combine rotation angles
        let combined_kind = match (&gate1.kind, &gate2.kind) {
            (GateKind::Rx(theta1), GateKind::Rx(theta2)) => {
                Some(GateKind::Rx(theta1 + theta2))
            }
            (GateKind::Ry(theta1), GateKind::Ry(theta2)) => {
                Some(GateKind::Ry(theta1 + theta2))
            }
            (GateKind::Rz(theta1), GateKind::Rz(theta2)) => {
                Some(GateKind::Rz(theta1 + theta2))
            }
            (GateKind::Phase(theta1), GateKind::Phase(theta2)) => {
                Some(GateKind::Phase(theta1 + theta2))
            }
            _ => None,
        }?;
        
        Some(Gate {
            kind: combined_kind,
            qubits: gate1.qubits.clone(),
            controls: gate1.controls.clone(),
            location: gate1.location.clone(),
        })
    }
    
    /// Simplify a rotation gate to a simpler form if possible
    fn simplify_rotation(&self, gate: &mut Gate) -> bool {
        let angle = match &gate.kind {
            GateKind::Rz(theta) => *theta,
            _ => return false,
        };
        
        // Normalize angle to [0, 2π)
        let normalized = self.normalize_angle(angle);
        
        // Check for special angles
        const EPSILON: f64 = 1e-10;
        
        if (normalized - PI).abs() < EPSILON {
            // Rz(π) = Z
            gate.kind = GateKind::Z;
            true
        } else if (normalized - PI / 2.0).abs() < EPSILON {
            // Rz(π/2) = S
            gate.kind = GateKind::S;
            true
        } else if (normalized - PI / 4.0).abs() < EPSILON {
            // Rz(π/4) = T
            gate.kind = GateKind::T;
            true
        } else if (normalized - 3.0 * PI / 2.0).abs() < EPSILON {
            // Rz(3π/2) = S†
            gate.kind = GateKind::Sdg;
            true
        } else if (normalized - 7.0 * PI / 4.0).abs() < EPSILON {
            // Rz(7π/4) = T†
            gate.kind = GateKind::Tdg;
            true
        } else {
            false
        }
    }
    
    /// Check if a rotation is effectively identity
    fn is_identity_rotation(&self, gate: &Gate) -> bool {
        let angle = match &gate.kind {
            GateKind::Rx(theta) | GateKind::Ry(theta) | 
            GateKind::Rz(theta) | GateKind::Phase(theta) => *theta,
            _ => return false,
        };
        
        // Normalize angle to [0, 2π)
        let normalized = self.normalize_angle(angle);
        
        // Check if angle is close to 0 or 2π
        const EPSILON: f64 = 1e-10;
        normalized.abs() < EPSILON || (normalized - 2.0 * PI).abs() < EPSILON
    }
    
    /// Normalize angle to [0, 2π)
    fn normalize_angle(&self, angle: f64) -> f64 {
        let mut normalized = angle % (2.0 * PI);
        if normalized < 0.0 {
            normalized += 2.0 * PI;
        }
        normalized
    }
}

impl Default for RotationFoldingPass {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use qataaum_ir::QubitId;
    
    #[test]
    fn test_fold_rx_rotations() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        
        // Add Rx(π/4) + Rx(π/4) = Rx(π/2)
        program.add_gate(program.entry, Gate::new(GateKind::Rx(PI / 4.0), vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::Rx(PI / 4.0), vec![q0]));
        
        let mut pass = RotationFoldingPass::new();
        pass.run(&mut program);
        
        assert_eq!(pass.rotations_folded, 1);
        let gates = &program.sequences.get(&program.entry).unwrap().gates;
        assert_eq!(gates.len(), 1);
        
        if let GateKind::Rx(angle) = gates[0].kind {
            assert!((angle - PI / 2.0).abs() < 1e-10);
        } else {
            panic!("Expected Rx gate");
        }
    }
    
    #[test]
    fn test_fold_ry_rotations() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        
        // Add Ry(π/3) + Ry(π/6) = Ry(π/2)
        program.add_gate(program.entry, Gate::new(GateKind::Ry(PI / 3.0), vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::Ry(PI / 6.0), vec![q0]));
        
        let mut pass = RotationFoldingPass::new();
        pass.run(&mut program);
        
        assert_eq!(pass.rotations_folded, 1);
        let gates = &program.sequences.get(&program.entry).unwrap().gates;
        assert_eq!(gates.len(), 1);
        
        if let GateKind::Ry(angle) = gates[0].kind {
            assert!((angle - PI / 2.0).abs() < 1e-10);
        } else {
            panic!("Expected Ry gate");
        }
    }
    
    #[test]
    fn test_fold_rz_rotations() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        
        // Add Rz(π/4) + Rz(π/4) = Rz(π/2) = S
        program.add_gate(program.entry, Gate::new(GateKind::Rz(PI / 4.0), vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::Rz(PI / 4.0), vec![q0]));
        
        let mut pass = RotationFoldingPass::new();
        pass.run(&mut program);
        
        assert_eq!(pass.rotations_folded, 1);
        assert_eq!(pass.rotations_simplified, 1);
        let gates = &program.sequences.get(&program.entry).unwrap().gates;
        assert_eq!(gates.len(), 1);
        assert!(matches!(gates[0].kind, GateKind::S));
    }
    
    #[test]
    fn test_simplify_rz_to_z() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        
        // Rz(π) = Z
        program.add_gate(program.entry, Gate::new(GateKind::Rz(PI), vec![q0]));
        
        let mut pass = RotationFoldingPass::new();
        pass.run(&mut program);
        
        assert_eq!(pass.rotations_simplified, 1);
        let gates = &program.sequences.get(&program.entry).unwrap().gates;
        assert_eq!(gates.len(), 1);
        assert!(matches!(gates[0].kind, GateKind::Z));
    }
    
    #[test]
    fn test_simplify_rz_to_s() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        
        // Rz(π/2) = S
        program.add_gate(program.entry, Gate::new(GateKind::Rz(PI / 2.0), vec![q0]));
        
        let mut pass = RotationFoldingPass::new();
        pass.run(&mut program);
        
        assert_eq!(pass.rotations_simplified, 1);
        let gates = &program.sequences.get(&program.entry).unwrap().gates;
        assert_eq!(gates.len(), 1);
        assert!(matches!(gates[0].kind, GateKind::S));
    }
    
    #[test]
    fn test_simplify_rz_to_t() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        
        // Rz(π/4) = T
        program.add_gate(program.entry, Gate::new(GateKind::Rz(PI / 4.0), vec![q0]));
        
        let mut pass = RotationFoldingPass::new();
        pass.run(&mut program);
        
        assert_eq!(pass.rotations_simplified, 1);
        let gates = &program.sequences.get(&program.entry).unwrap().gates;
        assert_eq!(gates.len(), 1);
        assert!(matches!(gates[0].kind, GateKind::T));
    }
    
    #[test]
    fn test_remove_identity_rotation() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        
        // Rz(2π) = identity (should be removed)
        program.add_gate(program.entry, Gate::new(GateKind::Rz(2.0 * PI), vec![q0]));
        
        let mut pass = RotationFoldingPass::new();
        pass.run(&mut program);
        
        let gates = &program.sequences.get(&program.entry).unwrap().gates;
        assert_eq!(gates.len(), 0);
    }
    
    #[test]
    fn test_fold_to_identity() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        
        // Rz(π) + Rz(π) = Rz(2π) = identity
        program.add_gate(program.entry, Gate::new(GateKind::Rz(PI), vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::Rz(PI), vec![q0]));
        
        let mut pass = RotationFoldingPass::new();
        pass.run(&mut program);
        
        assert_eq!(pass.rotations_folded, 1);
        let gates = &program.sequences.get(&program.entry).unwrap().gates;
        assert_eq!(gates.len(), 0); // Identity removed
    }
    
    #[test]
    fn test_no_fold_different_qubits() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        let q1 = program.add_qubit();
        
        // Rotations on different qubits should not fold
        program.add_gate(program.entry, Gate::new(GateKind::Rz(PI / 4.0), vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::Rz(PI / 4.0), vec![q1]));
        
        let mut pass = RotationFoldingPass::new();
        pass.run(&mut program);
        
        assert_eq!(pass.rotations_folded, 0);
        let gates = &program.sequences.get(&program.entry).unwrap().gates;
        assert_eq!(gates.len(), 2);
    }
    
    #[test]
    fn test_no_fold_different_axes() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        
        // Rotations on different axes should not fold
        program.add_gate(program.entry, Gate::new(GateKind::Rx(PI / 4.0), vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::Ry(PI / 4.0), vec![q0]));
        
        let mut pass = RotationFoldingPass::new();
        pass.run(&mut program);
        
        assert_eq!(pass.rotations_folded, 0);
        let gates = &program.sequences.get(&program.entry).unwrap().gates;
        assert_eq!(gates.len(), 2);
    }
}

// Made with Bob
