//! Quantum Circuit Executor
//!
//! Executes GateProgram on the state-vector simulator.

use crate::{StateVector, SimError, SimResult, gates::*};
use qataaum_ir::{Gate, GateKind, GateProgram, GateSequenceId, GateTerminator, QubitId, BitId};
use std::collections::HashMap;
use rand::thread_rng;

/// Execution result containing final state and measurements
#[derive(Debug, Clone)]
pub struct ExecutionResult {
    /// Final quantum state
    pub state: StateVector,
    
    /// Classical measurement results
    pub measurements: HashMap<usize, u8>,
    
    /// Number of gates executed
    pub gates_executed: usize,
}

/// Quantum circuit executor
pub struct Executor {
    /// Current quantum state
    state: StateVector,
    
    /// Classical bit storage
    bits: Vec<u8>,
    
    /// Measurement results
    measurements: HashMap<usize, u8>,
    
    /// Gates executed counter
    gates_executed: usize,
}

impl Executor {
    /// Create a new executor for a program
    pub fn new(num_qubits: usize, num_bits: usize) -> SimResult<Self> {
        Ok(Executor {
            state: StateVector::new(num_qubits)?,
            bits: vec![0; num_bits],
            measurements: HashMap::new(),
            gates_executed: 0,
        })
    }
    
    /// Execute a gate program
    pub fn execute(&mut self, program: &GateProgram) -> SimResult<ExecutionResult> {
        // Start from entry sequence
        self.execute_sequence(program, program.entry)?;
        
        Ok(ExecutionResult {
            state: self.state.clone(),
            measurements: self.measurements.clone(),
            gates_executed: self.gates_executed,
        })
    }
    
    /// Execute a single sequence
    fn execute_sequence(&mut self, program: &GateProgram, seq_id: GateSequenceId) -> SimResult<()> {
        let seq = program.sequences.get(&seq_id)
            .ok_or_else(|| SimError::InvalidParameters(format!("Unknown sequence: {:?}", seq_id)))?;
        
        // Execute all gates in sequence
        for gate in &seq.gates {
            self.execute_gate(gate)?;
        }
        
        // Handle terminator
        match &seq.terminator {
            GateTerminator::Return => {
                // Done
            }
            GateTerminator::Jump(target) => {
                self.execute_sequence(program, *target)?;
            }
            GateTerminator::Branch { condition, true_seq, false_seq } => {
                let bit_value = self.bits.get(condition.0)
                    .ok_or_else(|| SimError::InvalidBit(condition.0))?;
                
                let next_seq = if *bit_value != 0 { *true_seq } else { *false_seq };
                self.execute_sequence(program, next_seq)?;
            }
        }
        
        Ok(())
    }
    
    /// Execute a single gate
    fn execute_gate(&mut self, gate: &Gate) -> SimResult<()> {
        // Check classical controls
        for control_bit in &gate.controls {
            let bit_value = self.bits.get(control_bit.0)
                .ok_or_else(|| SimError::InvalidBit(control_bit.0))?;
            if *bit_value == 0 {
                // Control not satisfied, skip gate
                return Ok(());
            }
        }
        
        match &gate.kind {
            // Single-qubit Pauli gates
            GateKind::X => {
                let q = gate.qubits[0].0;
                apply_single_qubit_gate(&mut self.state, q, &x_matrix())?;
            }
            GateKind::Y => {
                let q = gate.qubits[0].0;
                apply_single_qubit_gate(&mut self.state, q, &y_matrix())?;
            }
            GateKind::Z => {
                let q = gate.qubits[0].0;
                apply_single_qubit_gate(&mut self.state, q, &z_matrix())?;
            }
            
            // Hadamard
            GateKind::H => {
                let q = gate.qubits[0].0;
                apply_single_qubit_gate(&mut self.state, q, &h_matrix())?;
            }
            
            // Phase gates
            GateKind::S => {
                let q = gate.qubits[0].0;
                apply_single_qubit_gate(&mut self.state, q, &s_matrix())?;
            }
            GateKind::Sdg => {
                let q = gate.qubits[0].0;
                apply_single_qubit_gate(&mut self.state, q, &sdg_matrix())?;
            }
            GateKind::T => {
                let q = gate.qubits[0].0;
                apply_single_qubit_gate(&mut self.state, q, &t_matrix())?;
            }
            GateKind::Tdg => {
                let q = gate.qubits[0].0;
                apply_single_qubit_gate(&mut self.state, q, &tdg_matrix())?;
            }
            
            // Rotation gates
            GateKind::Rx(theta) => {
                let q = gate.qubits[0].0;
                apply_single_qubit_gate(&mut self.state, q, &rx_matrix(*theta))?;
            }
            GateKind::Ry(theta) => {
                let q = gate.qubits[0].0;
                apply_single_qubit_gate(&mut self.state, q, &ry_matrix(*theta))?;
            }
            GateKind::Rz(theta) => {
                let q = gate.qubits[0].0;
                apply_single_qubit_gate(&mut self.state, q, &rz_matrix(*theta))?;
            }
            GateKind::Phase(theta) => {
                let q = gate.qubits[0].0;
                apply_single_qubit_gate(&mut self.state, q, &phase_matrix(*theta))?;
            }
            
            // Two-qubit gates
            GateKind::CX => {
                let ctrl = gate.qubits[0].0;
                let tgt = gate.qubits[1].0;
                apply_two_qubit_gate(&mut self.state, ctrl, tgt, &cx_matrix())?;
            }
            GateKind::CZ => {
                let ctrl = gate.qubits[0].0;
                let tgt = gate.qubits[1].0;
                apply_two_qubit_gate(&mut self.state, ctrl, tgt, &cz_matrix())?;
            }
            GateKind::Swap => {
                let q0 = gate.qubits[0].0;
                let q1 = gate.qubits[1].0;
                apply_two_qubit_gate(&mut self.state, q0, q1, &swap_matrix())?;
            }
            
            // Measurement
            GateKind::Measure { target_bit } => {
                let q = gate.qubits[0].0;
                let mut rng = thread_rng();
                let outcome = self.state.measure_qubit(q, &mut rng)?;
                
                self.bits[target_bit.0] = outcome;
                self.measurements.insert(q, outcome);
            }
            
            // Reset
            GateKind::Reset => {
                let q = gate.qubits[0].0;
                self.state.reset_qubit(q)?;
            }
            
            // Barrier (no-op in simulation)
            GateKind::Barrier => {
                // No operation
            }
            
            // Unsupported gates
            GateKind::CY | GateKind::CCX | GateKind::Custom { .. } => {
                return Err(SimError::UnsupportedGate(gate.kind.name()));
            }
        }
        
        self.gates_executed += 1;
        Ok(())
    }
    
    /// Get the current state
    pub fn state(&self) -> &StateVector {
        &self.state
    }
    
    /// Get classical bit values
    pub fn bits(&self) -> &[u8] {
        &self.bits
    }
    
    /// Get measurement results
    pub fn measurements(&self) -> &HashMap<usize, u8> {
        &self.measurements
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use qataaum_ir::{Gate, GateKind, QubitId};
    
    #[test]
    fn test_execute_x_gate() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        
        program.add_gate(program.entry, Gate::new(GateKind::X, vec![q0]));
        
        let mut executor = Executor::new(1, 0).unwrap();
        let result = executor.execute(&program).unwrap();
        
        assert_eq!(result.gates_executed, 1);
        assert!((result.state.amplitude(1).norm() - 1.0).abs() < 1e-10);
    }
    
    #[test]
    fn test_execute_bell_state() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        let q1 = program.add_qubit();
        
        program.add_gate(program.entry, Gate::new(GateKind::H, vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::CX, vec![q0, q1]));
        
        let mut executor = Executor::new(2, 0).unwrap();
        let result = executor.execute(&program).unwrap();
        
        assert_eq!(result.gates_executed, 2);
        
        let expected = 1.0 / 2.0_f64.sqrt();
        assert!((result.state.amplitude(0).re - expected).abs() < 1e-10);
        assert!((result.state.amplitude(3).re - expected).abs() < 1e-10);
    }
    
    #[test]
    fn test_execute_measurement() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        let b0 = program.add_bit();
        
        program.add_gate(program.entry, Gate::new(GateKind::X, vec![q0]));
        program.add_gate(program.entry, Gate::new(
            GateKind::Measure { target_bit: b0 },
            vec![q0]
        ));
        
        let mut executor = Executor::new(1, 1).unwrap();
        let result = executor.execute(&program).unwrap();
        
        assert_eq!(result.measurements.get(&0), Some(&1));
    }
}

// Made with Bob
