//! IR Level 4: GATE - Hardware-independent gate representation
//!
//! This module provides a hardware-independent representation of quantum gates
//! and operations. It serves as the foundation for optimization passes and
//! hardware-specific lowering.
//!
//! Key features:
//! - Standard gate library (Pauli, Hadamard, CNOT, Toffoli, etc.)
//! - Parameterized rotation gates
//! - Gate decomposition framework
//! - Gate equivalence checking
//! - Basis gate translation

use std::collections::HashMap;
use std::f64::consts::PI;

/// A hardware-independent gate program
#[derive(Debug, Clone)]
pub struct GateProgram {
    /// Entry point gate sequence
    pub entry: GateSequenceId,
    
    /// All gate sequences in the program
    pub sequences: HashMap<GateSequenceId, GateSequence>,
    
    /// Quantum resources (qubits)
    pub qubits: Vec<QubitId>,
    
    /// Classical resources (bits)
    pub bits: Vec<BitId>,
    
    /// Gate statistics
    pub stats: GateStats,
}

/// Unique identifier for a gate sequence
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct GateSequenceId(pub usize);

/// A sequence of gates with optional branching
#[derive(Debug, Clone)]
pub struct GateSequence {
    /// Sequence identifier
    pub id: GateSequenceId,
    
    /// Gates in this sequence
    pub gates: Vec<Gate>,
    
    /// Terminator (how this sequence ends)
    pub terminator: GateTerminator,
}

/// How a gate sequence terminates
#[derive(Debug, Clone)]
pub enum GateTerminator {
    /// Return from the program
    Return,
    
    /// Unconditional jump to another sequence
    Jump(GateSequenceId),
    
    /// Conditional branch based on classical bit
    Branch {
        condition: BitId,
        true_seq: GateSequenceId,
        false_seq: GateSequenceId,
    },
}

/// A quantum gate operation
#[derive(Debug, Clone, PartialEq)]
pub struct Gate {
    /// Gate kind and parameters
    pub kind: GateKind,
    
    /// Target qubits
    pub qubits: Vec<QubitId>,
    
    /// Optional classical control bits
    pub controls: Vec<BitId>,
    
    /// Source location for debugging
    pub location: Option<SourceLocation>,
}

/// Types of quantum gates
#[derive(Debug, Clone, PartialEq)]
pub enum GateKind {
    // Single-qubit Pauli gates
    /// Pauli-X (NOT) gate
    X,
    /// Pauli-Y gate
    Y,
    /// Pauli-Z gate
    Z,
    
    // Single-qubit Hadamard
    /// Hadamard gate
    H,
    
    // Single-qubit phase gates
    /// S gate (√Z)
    S,
    /// S† gate
    Sdg,
    /// T gate (√S)
    T,
    /// T† gate
    Tdg,
    
    // Single-qubit rotation gates
    /// Rotation around X axis
    Rx(f64),
    /// Rotation around Y axis
    Ry(f64),
    /// Rotation around Z axis
    Rz(f64),
    /// Phase gate
    Phase(f64),
    
    // Two-qubit gates
    /// Controlled-NOT (CNOT)
    CX,
    /// Controlled-Y
    CY,
    /// Controlled-Z
    CZ,
    /// SWAP gate
    Swap,
    
    // Three-qubit gates
    /// Toffoli (CCX) gate
    CCX,
    
    // Measurement and reset
    /// Measure qubit into classical bit
    Measure { target_bit: BitId },
    /// Reset qubit to |0⟩
    Reset,
    
    // Barriers
    /// Optimization barrier
    Barrier,
    
    // Custom gates (for decomposition)
    /// User-defined gate with matrix
    Custom {
        name: String,
        matrix: Vec<Vec<Complex>>,
    },
}

/// Complex number for gate matrices
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Complex {
    pub re: f64,
    pub im: f64,
}

impl Complex {
    pub fn new(re: f64, im: f64) -> Self {
        Complex { re, im }
    }
    
    pub fn real(re: f64) -> Self {
        Complex { re, im: 0.0 }
    }
    
    pub fn imag(im: f64) -> Self {
        Complex { re: 0.0, im }
    }
}

/// Qubit identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct QubitId(pub usize);

/// Classical bit identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct BitId(pub usize);

/// Source location for debugging
#[derive(Debug, Clone, PartialEq)]
pub struct SourceLocation {
    pub line: usize,
    pub column: usize,
}

/// Statistics about gates in the program
#[derive(Debug, Clone, Default)]
pub struct GateStats {
    /// Total number of gates
    pub total_gates: usize,
    
    /// Number of single-qubit gates
    pub single_qubit_gates: usize,
    
    /// Number of two-qubit gates
    pub two_qubit_gates: usize,
    
    /// Number of three-qubit gates
    pub three_qubit_gates: usize,
    
    /// Circuit depth (critical path length)
    pub depth: usize,
    
    /// Gate counts by type
    pub gate_counts: HashMap<String, usize>,
}

impl GateProgram {
    /// Create a new empty gate program
    pub fn new() -> Self {
        let entry_id = GateSequenceId(0);
        let mut sequences = HashMap::new();
        sequences.insert(entry_id, GateSequence {
            id: entry_id,
            gates: Vec::new(),
            terminator: GateTerminator::Return,
        });
        
        GateProgram {
            entry: entry_id,
            sequences,
            qubits: Vec::new(),
            bits: Vec::new(),
            stats: GateStats::default(),
        }
    }
    
    /// Add a qubit to the program
    pub fn add_qubit(&mut self) -> QubitId {
        let id = QubitId(self.qubits.len());
        self.qubits.push(id);
        id
    }
    
    /// Add a classical bit to the program
    pub fn add_bit(&mut self) -> BitId {
        let id = BitId(self.bits.len());
        self.bits.push(id);
        id
    }
    
    /// Create a new gate sequence
    pub fn new_sequence(&mut self) -> GateSequenceId {
        let id = GateSequenceId(self.sequences.len());
        self.sequences.insert(id, GateSequence {
            id,
            gates: Vec::new(),
            terminator: GateTerminator::Return,
        });
        id
    }
    
    /// Add a gate to a sequence
    pub fn add_gate(&mut self, seq_id: GateSequenceId, gate: Gate) {
        if let Some(seq) = self.sequences.get_mut(&seq_id) {
            seq.gates.push(gate);
        }
    }
    
    /// Set the terminator for a sequence
    pub fn set_terminator(&mut self, seq_id: GateSequenceId, terminator: GateTerminator) {
        if let Some(seq) = self.sequences.get_mut(&seq_id) {
            seq.terminator = terminator;
        }
    }
    
    /// Compute statistics for the program
    pub fn compute_stats(&mut self) {
        let mut stats = GateStats::default();
        
        for seq in self.sequences.values() {
            for gate in &seq.gates {
                stats.total_gates += 1;
                
                let gate_name = gate.kind.name();
                *stats.gate_counts.entry(gate_name).or_insert(0) += 1;
                
                match gate.qubits.len() {
                    1 => stats.single_qubit_gates += 1,
                    2 => stats.two_qubit_gates += 1,
                    3 => stats.three_qubit_gates += 1,
                    _ => {}
                }
            }
        }
        
        // Compute depth (simplified - assumes sequential execution)
        stats.depth = self.sequences.get(&self.entry)
            .map(|seq| seq.gates.len())
            .unwrap_or(0);
        
        self.stats = stats;
    }
}

impl Gate {
    /// Create a new gate
    pub fn new(kind: GateKind, qubits: Vec<QubitId>) -> Self {
        Gate {
            kind,
            qubits,
            controls: Vec::new(),
            location: None,
        }
    }
    
    /// Create a gate with classical controls
    pub fn with_controls(kind: GateKind, qubits: Vec<QubitId>, controls: Vec<BitId>) -> Self {
        Gate {
            kind,
            qubits,
            controls,
            location: None,
        }
    }
    
    /// Check if this gate is a single-qubit gate
    pub fn is_single_qubit(&self) -> bool {
        self.qubits.len() == 1
    }
    
    /// Check if this gate is a two-qubit gate
    pub fn is_two_qubit(&self) -> bool {
        self.qubits.len() == 2
    }
    
    /// Check if this gate is a measurement
    pub fn is_measurement(&self) -> bool {
        matches!(self.kind, GateKind::Measure { .. })
    }
    
    /// Check if this gate is a barrier
    pub fn is_barrier(&self) -> bool {
        matches!(self.kind, GateKind::Barrier)
    }
    
    /// Get the inverse of this gate (if it exists)
    pub fn inverse(&self) -> Option<Gate> {
        let inv_kind = match &self.kind {
            GateKind::X => Some(GateKind::X),
            GateKind::Y => Some(GateKind::Y),
            GateKind::Z => Some(GateKind::Z),
            GateKind::H => Some(GateKind::H),
            GateKind::S => Some(GateKind::Sdg),
            GateKind::Sdg => Some(GateKind::S),
            GateKind::T => Some(GateKind::Tdg),
            GateKind::Tdg => Some(GateKind::T),
            GateKind::Rx(theta) => Some(GateKind::Rx(-theta)),
            GateKind::Ry(theta) => Some(GateKind::Ry(-theta)),
            GateKind::Rz(theta) => Some(GateKind::Rz(-theta)),
            GateKind::Phase(theta) => Some(GateKind::Phase(-theta)),
            GateKind::CX => Some(GateKind::CX),
            GateKind::CY => Some(GateKind::CY),
            GateKind::CZ => Some(GateKind::CZ),
            GateKind::Swap => Some(GateKind::Swap),
            GateKind::CCX => Some(GateKind::CCX),
            _ => None,
        }?;
        
        Some(Gate {
            kind: inv_kind,
            qubits: self.qubits.clone(),
            controls: self.controls.clone(),
            location: self.location.clone(),
        })
    }
    
    /// Check if this gate commutes with another gate
    pub fn commutes_with(&self, other: &Gate) -> bool {
        // Gates on different qubits always commute
        let self_qubits: std::collections::HashSet<_> = self.qubits.iter().collect();
        let other_qubits: std::collections::HashSet<_> = other.qubits.iter().collect();
        
        if self_qubits.is_disjoint(&other_qubits) {
            return true;
        }
        
        // Same qubit - check specific gate types
        if self.qubits == other.qubits {
            match (&self.kind, &other.kind) {
                // Z gates commute with each other
                (GateKind::Z, GateKind::Z) => true,
                (GateKind::Z, GateKind::Rz(_)) => true,
                (GateKind::Rz(_), GateKind::Z) => true,
                (GateKind::Rz(_), GateKind::Rz(_)) => true,
                
                // Barriers don't commute with anything
                (GateKind::Barrier, _) | (_, GateKind::Barrier) => false,
                
                // Measurements don't commute
                (GateKind::Measure { .. }, _) | (_, GateKind::Measure { .. }) => false,
                
                _ => false,
            }
        } else {
            false
        }
    }
}

impl GateKind {
    /// Get the name of this gate kind
    pub fn name(&self) -> String {
        match self {
            GateKind::X => "x".to_string(),
            GateKind::Y => "y".to_string(),
            GateKind::Z => "z".to_string(),
            GateKind::H => "h".to_string(),
            GateKind::S => "s".to_string(),
            GateKind::Sdg => "sdg".to_string(),
            GateKind::T => "t".to_string(),
            GateKind::Tdg => "tdg".to_string(),
            GateKind::Rx(_) => "rx".to_string(),
            GateKind::Ry(_) => "ry".to_string(),
            GateKind::Rz(_) => "rz".to_string(),
            GateKind::Phase(_) => "phase".to_string(),
            GateKind::CX => "cx".to_string(),
            GateKind::CY => "cy".to_string(),
            GateKind::CZ => "cz".to_string(),
            GateKind::Swap => "swap".to_string(),
            GateKind::CCX => "ccx".to_string(),
            GateKind::Measure { .. } => "measure".to_string(),
            GateKind::Reset => "reset".to_string(),
            GateKind::Barrier => "barrier".to_string(),
            GateKind::Custom { name, .. } => name.clone(),
        }
    }
    
    /// Check if this is a rotation gate
    pub fn is_rotation(&self) -> bool {
        matches!(self, GateKind::Rx(_) | GateKind::Ry(_) | GateKind::Rz(_) | GateKind::Phase(_))
    }
    
    /// Get rotation angle if this is a rotation gate
    pub fn rotation_angle(&self) -> Option<f64> {
        match self {
            GateKind::Rx(theta) | GateKind::Ry(theta) | GateKind::Rz(theta) | GateKind::Phase(theta) => Some(*theta),
            _ => None,
        }
    }
}

/// Gate decomposition utilities
pub mod decompose {
    use super::*;
    
    /// Decompose a gate into basis gates
    pub fn decompose_gate(gate: &Gate) -> Vec<Gate> {
        match &gate.kind {
            // Already basis gates
            GateKind::X | GateKind::Y | GateKind::Z | GateKind::H |
            GateKind::S | GateKind::Sdg | GateKind::T | GateKind::Tdg |
            GateKind::CX | GateKind::Measure { .. } | GateKind::Reset | GateKind::Barrier => {
                vec![gate.clone()]
            }
            
            // Decompose CY into CX and single-qubit gates
            GateKind::CY => {
                if gate.qubits.len() != 2 {
                    return vec![gate.clone()];
                }
                let ctrl = gate.qubits[0];
                let tgt = gate.qubits[1];
                vec![
                    Gate::new(GateKind::Sdg, vec![tgt]),
                    Gate::new(GateKind::CX, vec![ctrl, tgt]),
                    Gate::new(GateKind::S, vec![tgt]),
                ]
            }
            
            // Decompose CZ into H and CX
            GateKind::CZ => {
                if gate.qubits.len() != 2 {
                    return vec![gate.clone()];
                }
                let ctrl = gate.qubits[0];
                let tgt = gate.qubits[1];
                vec![
                    Gate::new(GateKind::H, vec![tgt]),
                    Gate::new(GateKind::CX, vec![ctrl, tgt]),
                    Gate::new(GateKind::H, vec![tgt]),
                ]
            }
            
            // Decompose SWAP into three CX gates
            GateKind::Swap => {
                if gate.qubits.len() != 2 {
                    return vec![gate.clone()];
                }
                let q0 = gate.qubits[0];
                let q1 = gate.qubits[1];
                vec![
                    Gate::new(GateKind::CX, vec![q0, q1]),
                    Gate::new(GateKind::CX, vec![q1, q0]),
                    Gate::new(GateKind::CX, vec![q0, q1]),
                ]
            }
            
            // Decompose Toffoli (CCX) into single and two-qubit gates
            GateKind::CCX => {
                if gate.qubits.len() != 3 {
                    return vec![gate.clone()];
                }
                let ctrl1 = gate.qubits[0];
                let ctrl2 = gate.qubits[1];
                let tgt = gate.qubits[2];
                vec![
                    Gate::new(GateKind::H, vec![tgt]),
                    Gate::new(GateKind::CX, vec![ctrl2, tgt]),
                    Gate::new(GateKind::Tdg, vec![tgt]),
                    Gate::new(GateKind::CX, vec![ctrl1, tgt]),
                    Gate::new(GateKind::T, vec![tgt]),
                    Gate::new(GateKind::CX, vec![ctrl2, tgt]),
                    Gate::new(GateKind::Tdg, vec![tgt]),
                    Gate::new(GateKind::CX, vec![ctrl1, tgt]),
                    Gate::new(GateKind::T, vec![ctrl2]),
                    Gate::new(GateKind::T, vec![tgt]),
                    Gate::new(GateKind::H, vec![tgt]),
                    Gate::new(GateKind::CX, vec![ctrl1, ctrl2]),
                    Gate::new(GateKind::T, vec![ctrl1]),
                    Gate::new(GateKind::Tdg, vec![ctrl2]),
                    Gate::new(GateKind::CX, vec![ctrl1, ctrl2]),
                ]
            }
            
            // Rotations are already atomic
            GateKind::Rx(_) | GateKind::Ry(_) | GateKind::Rz(_) | GateKind::Phase(_) => {
                vec![gate.clone()]
            }
            
            // Custom gates cannot be decomposed without matrix information
            GateKind::Custom { .. } => {
                vec![gate.clone()]
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_gate_program_creation() {
        let mut program = GateProgram::new();
        assert_eq!(program.sequences.len(), 1);
        assert_eq!(program.qubits.len(), 0);
        assert_eq!(program.bits.len(), 0);
    }
    
    #[test]
    fn test_add_qubits_and_bits() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        let q1 = program.add_qubit();
        let b0 = program.add_bit();
        
        assert_eq!(q0, QubitId(0));
        assert_eq!(q1, QubitId(1));
        assert_eq!(b0, BitId(0));
        assert_eq!(program.qubits.len(), 2);
        assert_eq!(program.bits.len(), 1);
    }
    
    #[test]
    fn test_gate_inverse() {
        let h_gate = Gate::new(GateKind::H, vec![QubitId(0)]);
        let h_inv = h_gate.inverse().unwrap();
        assert!(matches!(h_inv.kind, GateKind::H));
        
        let s_gate = Gate::new(GateKind::S, vec![QubitId(0)]);
        let s_inv = s_gate.inverse().unwrap();
        assert!(matches!(s_inv.kind, GateKind::Sdg));
        
        let rx_gate = Gate::new(GateKind::Rx(PI / 2.0), vec![QubitId(0)]);
        let rx_inv = rx_gate.inverse().unwrap();
        if let GateKind::Rx(angle) = rx_inv.kind {
            assert!((angle + PI / 2.0).abs() < 1e-10);
        } else {
            panic!("Expected Rx gate");
        }
    }
    
    #[test]
    fn test_gate_commutation() {
        let z1 = Gate::new(GateKind::Z, vec![QubitId(0)]);
        let z2 = Gate::new(GateKind::Z, vec![QubitId(0)]);
        assert!(z1.commutes_with(&z2));
        
        let x = Gate::new(GateKind::X, vec![QubitId(0)]);
        let z = Gate::new(GateKind::Z, vec![QubitId(0)]);
        assert!(!x.commutes_with(&z));
        
        let x0 = Gate::new(GateKind::X, vec![QubitId(0)]);
        let x1 = Gate::new(GateKind::X, vec![QubitId(1)]);
        assert!(x0.commutes_with(&x1));
    }
    
    #[test]
    fn test_decompose_swap() {
        let swap = Gate::new(GateKind::Swap, vec![QubitId(0), QubitId(1)]);
        let decomposed = decompose::decompose_gate(&swap);
        
        assert_eq!(decomposed.len(), 3);
        for gate in &decomposed {
            assert!(matches!(gate.kind, GateKind::CX));
        }
    }
    
    #[test]
    fn test_decompose_cz() {
        let cz = Gate::new(GateKind::CZ, vec![QubitId(0), QubitId(1)]);
        let decomposed = decompose::decompose_gate(&cz);
        
        assert_eq!(decomposed.len(), 3);
        assert!(matches!(decomposed[0].kind, GateKind::H));
        assert!(matches!(decomposed[1].kind, GateKind::CX));
        assert!(matches!(decomposed[2].kind, GateKind::H));
    }
    
    #[test]
    fn test_gate_statistics() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        let q1 = program.add_qubit();
        
        program.add_gate(program.entry, Gate::new(GateKind::H, vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::CX, vec![q0, q1]));
        program.add_gate(program.entry, Gate::new(GateKind::X, vec![q1]));
        
        program.compute_stats();
        
        assert_eq!(program.stats.total_gates, 3);
        assert_eq!(program.stats.single_qubit_gates, 2);
        assert_eq!(program.stats.two_qubit_gates, 1);
        assert_eq!(program.stats.depth, 3);
    }
}

// Made with Bob
