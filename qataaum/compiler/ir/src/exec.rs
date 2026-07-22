//! QATAAUM IR Level 8: EXEC
//!
//! Backend package with executable instructions, metadata, proof receipts,
//! and result schema. This is the final IR ready for backend execution.

use crate::pulse::PulseIR;
use crate::schedule::Duration;
use crate::topo::PhysicalQubit;

/// Hash type for cryptographic verification
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Hash(pub String);

/// Timestamp in ISO 8601 format
#[derive(Debug, Clone, PartialEq)]
pub struct Timestamp(pub String);

/// Version information
#[derive(Debug, Clone, PartialEq)]
pub struct Version {
    pub major: u32,
    pub minor: u32,
    pub patch: u32,
}

impl std::fmt::Display for Version {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "{}.{}.{}", self.major, self.minor, self.patch)
    }
}

/// Backend identifier
#[derive(Debug, Clone, PartialEq)]
pub struct Backend {
    pub provider: String,
    pub name: String,
    pub version: String,
}

/// Processor identifier
#[derive(Debug, Clone, PartialEq)]
pub struct Processor {
    pub family: String,
    pub revision: String,
    pub num_qubits: usize,
}

/// Executable metadata
#[derive(Debug, Clone, PartialEq)]
pub struct ExecutableMetadata {
    pub job_id: String,
    pub circuit_hash: Hash,
    pub compilation_hash: Hash,
    pub backend: Backend,
    pub processor: Processor,
    pub timestamp: Timestamp,
    pub compiler_version: Version,
    pub optimization_level: u32,
}

/// Timing information for an instruction
#[derive(Debug, Clone, PartialEq)]
pub struct TimingInfo {
    pub start_time: Duration,
    pub duration: Duration,
    pub alignment: u32,
}

/// Resource used by an instruction
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Resource {
    Qubit(PhysicalQubit),
    ClassicalBit(usize),
    MeasurementUnit,
    ControlUnit,
    Frame(usize),
}

/// Proof witness for verification
#[derive(Debug, Clone, PartialEq)]
pub struct Witness {
    pub witness_type: String,
    pub data: Vec<u8>,
    pub verifier: String,
}

/// Executable instruction
#[derive(Debug, Clone, PartialEq)]
pub enum Instruction {
    /// Pulse-level instruction
    Pulse {
        frame_id: usize,
        waveform_id: usize,
        duration: Duration,
    },
    /// Measurement instruction
    Measure {
        qubit: PhysicalQubit,
        classical_bit: usize,
    },
    /// Delay instruction
    Delay {
        qubits: Vec<PhysicalQubit>,
        duration: Duration,
    },
    /// Barrier instruction
    Barrier {
        qubits: Vec<PhysicalQubit>,
    },
    /// Conditional instruction
    Conditional {
        condition: usize,
        true_branch: Vec<Instruction>,
        false_branch: Vec<Instruction>,
    },
}

/// Executable instruction with metadata
#[derive(Debug, Clone, PartialEq)]
pub struct ExecutableInstruction {
    pub instruction: Instruction,
    pub timing: TimingInfo,
    pub resources: Vec<Resource>,
    pub verification: Option<Witness>,
}

/// Proof obligation
#[derive(Debug, Clone, PartialEq)]
pub struct ProofObligation {
    pub obligation_type: String,
    pub description: String,
    pub required: bool,
}

/// Proof receipt
#[derive(Debug, Clone, PartialEq)]
pub struct ProofReceipt {
    pub obligation: ProofObligation,
    pub witness: Witness,
    pub verified: bool,
    pub verifier: String,
    pub timestamp: Timestamp,
}

/// Result schema defining expected output format
#[derive(Debug, Clone, PartialEq)]
pub struct ResultSchema {
    pub num_classical_bits: usize,
    pub num_shots: usize,
    pub measurement_qubits: Vec<PhysicalQubit>,
    pub result_format: String,
}

/// Verification data for executable integrity
#[derive(Debug, Clone, PartialEq)]
pub struct VerificationData {
    pub signature: Hash,
    pub certificate_chain: Vec<Hash>,
    pub sealed: bool,
    pub seal_timestamp: Option<Timestamp>,
}

/// IR Level 8: Executable representation
#[derive(Debug, Clone, PartialEq)]
pub struct ExecutableIR {
    pub metadata: ExecutableMetadata,
    pub instructions: Vec<ExecutableInstruction>,
    pub proof_receipts: Vec<ProofReceipt>,
    pub result_schema: ResultSchema,
    pub verification: VerificationData,
}

impl ExecutableIR {
    pub fn new(metadata: ExecutableMetadata) -> Self {
        Self {
            metadata,
            instructions: Vec::new(),
            proof_receipts: Vec::new(),
            result_schema: ResultSchema {
                num_classical_bits: 0,
                num_shots: 1024,
                measurement_qubits: Vec::new(),
                result_format: "counts".to_string(),
            },
            verification: VerificationData {
                signature: Hash("unsigned".to_string()),
                certificate_chain: Vec::new(),
                sealed: false,
                seal_timestamp: None,
            },
        }
    }
    
    pub fn add_instruction(&mut self, instruction: ExecutableInstruction) {
        self.instructions.push(instruction);
    }
    
    pub fn add_proof_receipt(&mut self, receipt: ProofReceipt) {
        self.proof_receipts.push(receipt);
    }
    
    pub fn seal(&mut self) {
        self.verification.sealed = true;
        self.verification.seal_timestamp = Some(Timestamp(
            chrono::Utc::now().to_rfc3339()
        ));
        
        // Generate signature (simplified - would use real crypto)
        let content = format!("{:?}", self.instructions);
        self.verification.signature = Hash(format!("sha256:{}", content.len()));
    }
    
    pub fn is_sealed(&self) -> bool {
        self.verification.sealed
    }
}

/// Executable compiler that converts PulseIR to ExecutableIR
pub struct ExecutableCompiler {
    backend: Backend,
    processor: Processor,
}

impl ExecutableCompiler {
    pub fn new(backend: Backend, processor: Processor) -> Self {
        Self { backend, processor }
    }
    
    pub fn compile(&self, pulse_ir: &PulseIR) -> Result<ExecutableIR, String> {
        let metadata = ExecutableMetadata {
            job_id: uuid::Uuid::new_v4().to_string(),
            circuit_hash: Hash("circuit_hash".to_string()),
            compilation_hash: Hash("compilation_hash".to_string()),
            backend: self.backend.clone(),
            processor: self.processor.clone(),
            timestamp: Timestamp(chrono::Utc::now().to_rfc3339()),
            compiler_version: Version {
                major: 0,
                minor: 1,
                patch: 0,
            },
            optimization_level: 2,
        };
        
        let mut exec_ir = ExecutableIR::new(metadata);
        
        // Convert pulse operations to executable instructions
        for pulse_op in &pulse_ir.pulse_sequence {
            let instruction = match pulse_op {
                crate::pulse::PulseOp::Play { frame, waveform, duration } => {
                    ExecutableInstruction {
                        instruction: Instruction::Pulse {
                            frame_id: frame.0,
                            waveform_id: waveform.0,
                            duration: *duration,
                        },
                        timing: TimingInfo {
                            start_time: Duration(0.0),
                            duration: *duration,
                            alignment: 16,
                        },
                        resources: vec![Resource::Frame(frame.0)],
                        verification: None,
                    }
                }
                crate::pulse::PulseOp::Delay { frame, duration } => {
                    ExecutableInstruction {
                        instruction: Instruction::Delay {
                            qubits: vec![],
                            duration: *duration,
                        },
                        timing: TimingInfo {
                            start_time: Duration(0.0),
                            duration: *duration,
                            alignment: 1,
                        },
                        resources: vec![Resource::Frame(frame.0)],
                        verification: None,
                    }
                }
                _ => continue,
            };
            
            exec_ir.add_instruction(instruction);
        }
        
        // Set result schema
        exec_ir.result_schema.measurement_qubits = pulse_ir
            .frames
            .iter()
            .map(|f| f.qubit)
            .collect();
        exec_ir.result_schema.num_classical_bits = pulse_ir.frames.len();
        
        Ok(exec_ir)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_version_display() {
        let version = Version {
            major: 1,
            minor: 2,
            patch: 3,
        };
        assert_eq!(version.to_string(), "1.2.3");
    }

    #[test]
    fn test_executable_creation() {
        let metadata = ExecutableMetadata {
            job_id: "test-job-123".to_string(),
            circuit_hash: Hash("abc123".to_string()),
            compilation_hash: Hash("def456".to_string()),
            backend: Backend {
                provider: "test".to_string(),
                name: "simulator".to_string(),
                version: "1.0".to_string(),
            },
            processor: Processor {
                family: "test".to_string(),
                revision: "r1".to_string(),
                num_qubits: 5,
            },
            timestamp: Timestamp("2026-01-01T00:00:00Z".to_string()),
            compiler_version: Version {
                major: 0,
                minor: 1,
                patch: 0,
            },
            optimization_level: 2,
        };
        
        let exec_ir = ExecutableIR::new(metadata);
        assert_eq!(exec_ir.instructions.len(), 0);
        assert!(!exec_ir.is_sealed());
    }

    #[test]
    fn test_executable_sealing() {
        let metadata = ExecutableMetadata {
            job_id: "test-job".to_string(),
            circuit_hash: Hash("hash".to_string()),
            compilation_hash: Hash("hash".to_string()),
            backend: Backend {
                provider: "test".to_string(),
                name: "sim".to_string(),
                version: "1.0".to_string(),
            },
            processor: Processor {
                family: "test".to_string(),
                revision: "r1".to_string(),
                num_qubits: 2,
            },
            timestamp: Timestamp("2026-01-01T00:00:00Z".to_string()),
            compiler_version: Version {
                major: 0,
                minor: 1,
                patch: 0,
            },
            optimization_level: 1,
        };
        
        let mut exec_ir = ExecutableIR::new(metadata);
        assert!(!exec_ir.is_sealed());
        
        exec_ir.seal();
        assert!(exec_ir.is_sealed());
        assert!(exec_ir.verification.seal_timestamp.is_some());
    }

    #[test]
    fn test_add_instruction() {
        let metadata = ExecutableMetadata {
            job_id: "test".to_string(),
            circuit_hash: Hash("h".to_string()),
            compilation_hash: Hash("h".to_string()),
            backend: Backend {
                provider: "t".to_string(),
                name: "s".to_string(),
                version: "1".to_string(),
            },
            processor: Processor {
                family: "t".to_string(),
                revision: "r1".to_string(),
                num_qubits: 1,
            },
            timestamp: Timestamp("2026-01-01T00:00:00Z".to_string()),
            compiler_version: Version {
                major: 0,
                minor: 1,
                patch: 0,
            },
            optimization_level: 0,
        };
        
        let mut exec_ir = ExecutableIR::new(metadata);
        
        exec_ir.add_instruction(ExecutableInstruction {
            instruction: Instruction::Delay {
                qubits: vec![PhysicalQubit(0)],
                duration: Duration(100.0),
            },
            timing: TimingInfo {
                start_time: Duration(0.0),
                duration: Duration(100.0),
                alignment: 1,
            },
            resources: vec![Resource::Qubit(PhysicalQubit(0))],
            verification: None,
        });
        
        assert_eq!(exec_ir.instructions.len(), 1);
    }
}

// Made with Bob
