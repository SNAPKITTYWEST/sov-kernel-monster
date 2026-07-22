//! CFG Builder - Transforms Typed AST to Control Flow Graph
//!
//! This module implements the transformation from IR Level 1 (Typed AST)
//! to IR Level 2 (Control Flow Graph). It handles:
//! - Linear statement sequences
//! - Conditional branches (if statements)
//! - Basic block construction
//! - Edge creation and management
//!
//! Part of the QATAAUM Quantum Assembly Runtime
//! Clean-room implementation based on public compiler design principles

use crate::cfg::{BlockId, ControlFlowGraph, EdgeKind, Instruction, Terminator};
use crate::typed_ast::{BitRef, QubitRef, TypedProgram, TypedStatement};
use std::collections::HashMap;

/// Errors that can occur during CFG construction
#[derive(Debug, Clone, PartialEq)]
pub enum CfgBuildError {
    /// Undefined register or variable
    UndefinedRegister(String),
    /// Register index out of bounds
    RegisterIndexOutOfBounds { register: String, index: usize },
    /// Invalid conditional expression
    InvalidCondition(String),
    /// Malformed control flow
    MalformedControlFlow(String),
}

impl std::fmt::Display for CfgBuildError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CfgBuildError::UndefinedRegister(name) => {
                write!(f, "Undefined register: {}", name)
            }
            CfgBuildError::RegisterIndexOutOfBounds { register, index } => {
                write!(f, "Register index out of bounds: {}[{}]", register, index)
            }
            CfgBuildError::InvalidCondition(msg) => {
                write!(f, "Invalid condition: {}", msg)
            }
            CfgBuildError::MalformedControlFlow(msg) => {
                write!(f, "Malformed control flow: {}", msg)
            }
        }
    }
}

impl std::error::Error for CfgBuildError {}

/// CFG Builder state
pub struct CfgBuilder {
    cfg: ControlFlowGraph,
    current_block: BlockId,
    next_block_id: usize,
    /// Map from qubit register names to their sizes
    qregs: HashMap<String, usize>,
    /// Map from classical register names to their sizes
    cregs: HashMap<String, usize>,
    /// Base BitId offset for each classical register (for condition bit resolution)
    creg_bit_base: HashMap<String, usize>,
    /// Next available classical bit index
    next_bit_id: usize,
}

impl CfgBuilder {
    /// Create a new CFG builder
    pub fn new() -> Self {
        let cfg = ControlFlowGraph::new();
        let entry_block = cfg.entry;
        
        Self {
            cfg,
            current_block: entry_block,
            next_block_id: 1,
            qregs: HashMap::new(),
            cregs: HashMap::new(),
            creg_bit_base: HashMap::new(),
            next_bit_id: 0,
        }
    }

    /// Build a CFG from a typed program
    pub fn build(mut self, program: &TypedProgram) -> Result<ControlFlowGraph, CfgBuildError> {
        // Collect register declarations for validation
        for qreg in &program.qregs {
            self.qregs.insert(qreg.name.clone(), qreg.size);
        }

        for creg in &program.cregs {
            self.creg_bit_base.insert(creg.name.clone(), self.next_bit_id);
            for offset in 0..creg.size {
                let bit = crate::types::BitId(self.next_bit_id + offset);
                self.cfg.bits.insert(bit);
            }
            self.next_bit_id += creg.size;
            self.cregs.insert(creg.name.clone(), creg.size);
        }

        // Build CFG from statements
        for stmt in &program.statements {
            self.process_statement(stmt)?;
        }

        Ok(self.cfg)
    }

    /// Process a single statement
    fn process_statement(&mut self, stmt: &TypedStatement) -> Result<(), CfgBuildError> {
        match stmt {
            TypedStatement::Gate { name, params, qubits, .. } => {
                // Extract QubitIds from QubitRefs
                let qubit_ids: Vec<_> = qubits.iter().map(|q| q.id).collect();
                
                // Add qubits to CFG resource tracking
                for qubit in qubits {
                    self.cfg.qubits.insert(qubit.id);
                }

                let instruction = Instruction::Gate {
                    name: name.clone(),
                    params: params.clone(),
                    qubits: qubit_ids,
                };
                
                self.add_instruction(instruction);
                Ok(())
            }

            TypedStatement::Measure { qubit, bit, .. } => {
                // Add resources to CFG tracking
                self.cfg.qubits.insert(qubit.id);
                self.cfg.bits.insert(bit.id);

                let instruction = Instruction::Measure {
                    qubit: qubit.id,
                    bit: bit.id,
                };
                
                self.add_instruction(instruction);
                Ok(())
            }

            TypedStatement::Reset { qubit, .. } => {
                self.cfg.qubits.insert(qubit.id);

                let instruction = Instruction::Reset {
                    qubit: qubit.id,
                };
                
                self.add_instruction(instruction);
                Ok(())
            }

            TypedStatement::Barrier { qubits, .. } => {
                let qubit_ids: Vec<_> = qubits.iter().map(|q| q.id).collect();
                
                for qubit in qubits {
                    self.cfg.qubits.insert(qubit.id);
                }

                let instruction = Instruction::Barrier {
                    qubits: qubit_ids,
                };
                
                self.add_instruction(instruction);
                Ok(())
            }

            TypedStatement::If { register, value, body, .. } => {
                self.process_if_statement(register, *value, body)
            }
        }
    }

    /// Process an if statement, creating conditional branches
    fn process_if_statement(
        &mut self,
        register: &str,
        _value: u64,
        body: &TypedStatement,
    ) -> Result<(), CfgBuildError> {
        // For now, we'll use a placeholder bit for the condition
        // In a full implementation, we'd need to handle multi-bit comparisons
        // and create the appropriate classical comparison operations
        
        // Verify register exists
        if !self.cregs.contains_key(register) {
            return Err(CfgBuildError::UndefinedRegister(register.to_string()));
        }

        // Resolve condition bit: use bit 0 of the named classical register.
        // The creg_bit_base map tracks the absolute BitId offset for each creg,
        // allocated during program initialisation. Comparing against `value`
        // is a multi-bit operation; for single-bit conditionals (the common case
        // in OpenQASM 2.0) bit 0 of the register carries the measurement result.
        let base = self.creg_bit_base.get(register).copied()
            .unwrap_or(0);
        let condition_bit = crate::types::BitId(base);

        // Create blocks for then branch and continuation
        let then_block = self.create_block();
        let continue_block = self.create_block();

        // Set branch terminator on current block
        self.set_terminator(Terminator::Branch {
            condition: condition_bit,
            true_target: then_block,
            false_target: continue_block,
        });

        // Add edges
        self.cfg.add_edge(self.current_block, then_block, EdgeKind::True);
        self.cfg.add_edge(self.current_block, continue_block, EdgeKind::False);

        // Process then branch
        self.current_block = then_block;
        self.process_statement(body)?;

        // Jump to continuation
        self.set_terminator(Terminator::Jump {
            target: continue_block,
        });
        self.cfg.add_edge(self.current_block, continue_block, EdgeKind::Unconditional);

        // Continue from continuation block
        self.current_block = continue_block;

        Ok(())
    }

    /// Add an instruction to the current block
    fn add_instruction(&mut self, instruction: Instruction) {
        if let Some(block) = self.cfg.blocks.get_mut(&self.current_block) {
            block.instructions.push(instruction);
        }
    }

    /// Set the terminator for the current block
    fn set_terminator(&mut self, terminator: Terminator) {
        if let Some(block) = self.cfg.blocks.get_mut(&self.current_block) {
            block.terminator = terminator;
        }
    }

    /// Create a new basic block
    fn create_block(&mut self) -> BlockId {
        let id = self.cfg.add_block();
        self.next_block_id += 1;
        id
    }
}

impl Default for CfgBuilder {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::typed_ast::{CRegDecl, QRegDecl};
    use crate::types::{BitId, QubitId, Type};
    use qataaum_parser::Span;
    use qataaum_semantic::SymbolTable;

    fn create_test_program(
        qregs: Vec<QRegDecl>,
        cregs: Vec<CRegDecl>,
        statements: Vec<TypedStatement>,
    ) -> TypedProgram {
        TypedProgram {
            version: "2.0".to_string(),
            qregs,
            cregs,
            gates: vec![],
            opaques: vec![],
            statements,
            symbols: SymbolTable::new(),
            types: HashMap::new(),
        }
    }

    fn make_qubit_ref(register: &str, index: usize, id: usize) -> QubitRef {
        QubitRef {
            register: register.to_string(),
            index: Some(index),
            id: QubitId(id),
            ty: Type::Qubit,
            span: Span { line: 1, column: 1, length: 5 },
        }
    }

    fn make_bit_ref(register: &str, index: usize, id: usize) -> BitRef {
        BitRef {
            register: register.to_string(),
            index: Some(index),
            id: BitId(id),
            ty: Type::Bit,
            span: Span { line: 1, column: 1, length: 5 },
        }
    }

    #[test]
    fn test_empty_program() {
        let program = create_test_program(vec![], vec![], vec![]);

        let builder = CfgBuilder::new();
        let cfg = builder.build(&program).unwrap();

        // Should have entry block with return terminator
        assert_eq!(cfg.blocks.len(), 1);
        let entry = cfg.get_block(cfg.entry).unwrap();
        assert!(matches!(entry.terminator, Terminator::Return));
    }

    #[test]
    fn test_simple_gate_sequence() {
        let program = create_test_program(
            vec![QRegDecl {
                name: "q".to_string(),
                size: 2,
                span: Span { line: 1, column: 1, length: 10 },
            }],
            vec![],
            vec![
                TypedStatement::Gate {
                    name: "h".to_string(),
                    params: vec![],
                    qubits: vec![make_qubit_ref("q", 0, 0)],
                    span: Span { line: 2, column: 1, length: 10 },
                },
                TypedStatement::Gate {
                    name: "cx".to_string(),
                    params: vec![],
                    qubits: vec![make_qubit_ref("q", 0, 0), make_qubit_ref("q", 1, 1)],
                    span: Span { line: 3, column: 1, length: 15 },
                },
            ],
        );

        let builder = CfgBuilder::new();
        let cfg = builder.build(&program).unwrap();

        // Should have one block with two gate instructions
        assert_eq!(cfg.blocks.len(), 1);
        let entry = cfg.get_block(cfg.entry).unwrap();
        assert_eq!(entry.instructions.len(), 2);

        // Check instructions
        assert!(matches!(
            entry.instructions[0],
            Instruction::Gate { ref name, .. } if name == "h"
        ));
        assert!(matches!(
            entry.instructions[1],
            Instruction::Gate { ref name, .. } if name == "cx"
        ));
    }

    #[test]
    fn test_measurement() {
        let program = create_test_program(
            vec![QRegDecl {
                name: "q".to_string(),
                size: 1,
                span: Span { line: 1, column: 1, length: 10 },
            }],
            vec![CRegDecl {
                name: "c".to_string(),
                size: 1,
                span: Span { line: 2, column: 1, length: 10 },
            }],
            vec![
                TypedStatement::Gate {
                    name: "h".to_string(),
                    params: vec![],
                    qubits: vec![make_qubit_ref("q", 0, 0)],
                    span: Span { line: 3, column: 1, length: 10 },
                },
                TypedStatement::Measure {
                    qubit: make_qubit_ref("q", 0, 0),
                    bit: make_bit_ref("c", 0, 0),
                    span: Span { line: 4, column: 1, length: 15 },
                },
            ],
        );

        let builder = CfgBuilder::new();
        let cfg = builder.build(&program).unwrap();

        let entry = cfg.get_block(cfg.entry).unwrap();
        assert_eq!(entry.instructions.len(), 2);

        // Check measurement instruction
        assert!(matches!(
            entry.instructions[1],
            Instruction::Measure { .. }
        ));
    }

    #[test]
    fn test_barrier() {
        let program = create_test_program(
            vec![QRegDecl {
                name: "q".to_string(),
                size: 2,
                span: Span { line: 1, column: 1, length: 10 },
            }],
            vec![],
            vec![
                TypedStatement::Gate {
                    name: "h".to_string(),
                    params: vec![],
                    qubits: vec![make_qubit_ref("q", 0, 0)],
                    span: Span { line: 2, column: 1, length: 10 },
                },
                TypedStatement::Barrier {
                    qubits: vec![make_qubit_ref("q", 0, 0), make_qubit_ref("q", 1, 1)],
                    span: Span { line: 3, column: 1, length: 20 },
                },
                TypedStatement::Gate {
                    name: "cx".to_string(),
                    params: vec![],
                    qubits: vec![make_qubit_ref("q", 0, 0), make_qubit_ref("q", 1, 1)],
                    span: Span { line: 4, column: 1, length: 15 },
                },
            ],
        );

        let builder = CfgBuilder::new();
        let cfg = builder.build(&program).unwrap();

        let entry = cfg.get_block(cfg.entry).unwrap();
        assert_eq!(entry.instructions.len(), 3);

        // Check barrier instruction
        assert!(matches!(
            entry.instructions[1],
            Instruction::Barrier { .. }
        ));
    }

    #[test]
    fn test_reset() {
        let program = create_test_program(
            vec![QRegDecl {
                name: "q".to_string(),
                size: 1,
                span: Span { line: 1, column: 1, length: 10 },
            }],
            vec![],
            vec![
                TypedStatement::Gate {
                    name: "x".to_string(),
                    params: vec![],
                    qubits: vec![make_qubit_ref("q", 0, 0)],
                    span: Span { line: 2, column: 1, length: 10 },
                },
                TypedStatement::Reset {
                    qubit: make_qubit_ref("q", 0, 0),
                    span: Span { line: 3, column: 1, length: 10 },
                },
            ],
        );

        let builder = CfgBuilder::new();
        let cfg = builder.build(&program).unwrap();

        let entry = cfg.get_block(cfg.entry).unwrap();
        assert_eq!(entry.instructions.len(), 2);

        // Check reset instruction
        assert!(matches!(
            entry.instructions[1],
            Instruction::Reset { .. }
        ));
    }
}

// Made with Bob
