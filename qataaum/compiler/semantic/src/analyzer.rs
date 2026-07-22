//! Semantic analyzer implementation
//!
//! Clean-room implementation - not derived from Qiskit

use qataaum_parser::{Program, Statement, QubitRef, BitRef, GateOp, QuantumOp, Span};
use crate::error::{SemanticError, SemanticResult};
use crate::symbol_table::{SymbolTable, Symbol, SymbolKind};

/// Semantic analyzer for OpenQASM programs
pub struct SemanticAnalyzer {
    symbols: SymbolTable,
    errors: Vec<SemanticError>,
}

impl SemanticAnalyzer {
    /// Create a new semantic analyzer
    pub fn new() -> Self {
        Self {
            symbols: SymbolTable::new(),
            errors: Vec::new(),
        }
    }
    
    /// Analyze a program
    pub fn analyze(&mut self, program: &Program) -> SemanticResult<()> {
        // Clear previous state
        self.errors.clear();
        self.symbols = SymbolTable::new();
        
        // Analyze all statements
        for statement in &program.statements {
            if let Err(e) = self.analyze_statement(statement) {
                self.errors.push(e);
            }
        }
        
        // Return first error if any
        if let Some(error) = self.errors.first() {
            Err(error.clone())
        } else {
            Ok(())
        }
    }
    
    /// Get all collected errors
    pub fn errors(&self) -> &[SemanticError] {
        &self.errors
    }
    
    /// Get the symbol table
    pub fn symbol_table(&self) -> &SymbolTable {
        &self.symbols
    }
    
    /// Analyze a statement
    fn analyze_statement(&mut self, statement: &Statement) -> SemanticResult<()> {
        match statement {
            Statement::QRegDecl(qreg) => {
                self.analyze_qreg_decl(&qreg.name, qreg.size, qreg.span)
            }
            Statement::CRegDecl(creg) => {
                self.analyze_creg_decl(&creg.name, creg.size, creg.span)
            }
            Statement::GateDecl(gate) => {
                self.analyze_gate_decl(
                    &gate.name,
                    &gate.params,
                    &gate.qubits,
                    &gate.body,
                    gate.span,
                )
            }
            Statement::OpaqueDecl(opaque) => {
                self.analyze_opaque_decl(
                    &opaque.name,
                    &opaque.params,
                    &opaque.qubits,
                    opaque.span,
                )
            }
            Statement::QuantumOp(qop) => {
                self.analyze_quantum_op(qop)
            }
            Statement::Measure(measure) => {
                self.analyze_measure(&measure.qubit, &measure.bit, measure.span)
            }
            Statement::Reset(reset) => {
                self.analyze_reset(&reset.qubit, reset.span)
            }
            Statement::Barrier(barrier) => {
                self.analyze_barrier(&barrier.qubits, barrier.span)
            }
            Statement::If(if_stmt) => {
                self.analyze_if(&if_stmt.creg, if_stmt.value, &if_stmt.op, if_stmt.span)
            }
        }
    }
    
    /// Analyze quantum register declaration
    fn analyze_qreg_decl(&mut self, name: &str, size: usize, span: Span) -> SemanticResult<()> {
        if size == 0 {
            return Err(SemanticError::InvalidRegisterSize {
                name: name.to_string(),
                size,
                span,
            });
        }
        
        let symbol = Symbol {
            name: name.to_string(),
            kind: SymbolKind::QReg { size },
            span,
        };
        
        if let Err(existing) = self.symbols.define(symbol) {
            return Err(SemanticError::DuplicateSymbol {
                name: name.to_string(),
                original_span: existing.span,
                duplicate_span: span,
            });
        }
        
        Ok(())
    }
    
    /// Analyze classical register declaration
    fn analyze_creg_decl(&mut self, name: &str, size: usize, span: Span) -> SemanticResult<()> {
        if size == 0 {
            return Err(SemanticError::InvalidRegisterSize {
                name: name.to_string(),
                size,
                span,
            });
        }
        
        let symbol = Symbol {
            name: name.to_string(),
            kind: SymbolKind::CReg { size },
            span,
        };
        
        if let Err(existing) = self.symbols.define(symbol) {
            return Err(SemanticError::DuplicateSymbol {
                name: name.to_string(),
                original_span: existing.span,
                duplicate_span: span,
            });
        }
        
        Ok(())
    }
    
    /// Analyze gate declaration
    fn analyze_gate_decl(
        &mut self,
        name: &str,
        params: &[String],
        qubits: &[String],
        body: &[GateOp],
        span: Span,
    ) -> SemanticResult<()> {
        // Define gate in global scope
        let symbol = Symbol {
            name: name.to_string(),
            kind: SymbolKind::Gate {
                params: params.to_vec(),
                qubits: qubits.to_vec(),
            },
            span,
        };
        
        if let Err(existing) = self.symbols.define(symbol) {
            return Err(SemanticError::DuplicateSymbol {
                name: name.to_string(),
                original_span: existing.span,
                duplicate_span: span,
            });
        }
        
        // Enter local scope for gate body
        self.symbols.enter_scope();
        
        // Define parameters
        for param in params {
            let param_symbol = Symbol {
                name: param.clone(),
                kind: SymbolKind::Parameter,
                span,
            };
            self.symbols.define(param_symbol).ok(); // Ignore duplicates in params
        }
        
        // Define qubits
        for qubit in qubits {
            let qubit_symbol = Symbol {
                name: qubit.to_string(),
                kind: SymbolKind::Qubit,
                span,
            };
            self.symbols.define(qubit_symbol).ok(); // Ignore duplicates in qubits
        }
        
        // Analyze gate body
        for op in body {
            if let Err(e) = self.analyze_gate_op(op) {
                self.errors.push(e);
            }
        }
        
        // Exit local scope
        self.symbols.exit_scope();
        
        Ok(())
    }
    
    /// Analyze opaque gate declaration
    fn analyze_opaque_decl(
        &mut self,
        name: &str,
        params: &[String],
        qubits: &[String],
        span: Span,
    ) -> SemanticResult<()> {
        let symbol = Symbol {
            name: name.to_string(),
            kind: SymbolKind::Opaque {
                params: params.to_vec(),
                qubits: qubits.to_vec(),
            },
            span,
        };
        
        if let Err(existing) = self.symbols.define(symbol) {
            return Err(SemanticError::DuplicateSymbol {
                name: name.to_string(),
                original_span: existing.span,
                duplicate_span: span,
            });
        }
        
        Ok(())
    }
    
    /// Analyze gate operation (inside gate body)
    fn analyze_gate_op(&mut self, op: &GateOp) -> SemanticResult<()> {
        match op {
            GateOp::U(u) => {
                // Check that qubit is defined
                if self.symbols.lookup(&u.qubit).is_none() {
                    return Err(SemanticError::UndefinedSymbol {
                        name: u.qubit.clone(),
                        span: u.span,
                    });
                }
                Ok(())
            }
            GateOp::CX(cx) => {
                // Check that control and target are defined
                if self.symbols.lookup(&cx.control).is_none() {
                    return Err(SemanticError::UndefinedSymbol {
                        name: cx.control.clone(),
                        span: cx.span,
                    });
                }
                if self.symbols.lookup(&cx.target).is_none() {
                    return Err(SemanticError::UndefinedSymbol {
                        name: cx.target.clone(),
                        span: cx.span,
                    });
                }
                Ok(())
            }
            GateOp::Apply(qop) => {
                self.analyze_quantum_op(qop)
            }
            GateOp::Barrier(qubits) => {
                // Check that all qubits are defined
                for qubit in qubits {
                    if self.symbols.lookup(qubit).is_none() {
                        return Err(SemanticError::UndefinedSymbol {
                            name: qubit.clone(),
                            span: Span::new(0, 0, 0), // TODO: Better span tracking
                        });
                    }
                }
                Ok(())
            }
        }
    }
    
    /// Analyze quantum operation
    fn analyze_quantum_op(&mut self, qop: &QuantumOp) -> SemanticResult<()> {
        // Check if gate is defined
        if let Some((params, qubits)) = self.symbols.get_gate(&qop.gate) {
            // Check parameter count
            if qop.params.len() != params.len() {
                return Err(SemanticError::ParameterMismatch {
                    gate: qop.gate.clone(),
                    expected: params.len(),
                    found: qop.params.len(),
                    span: qop.span,
                });
            }
            
            // Check qubit count
            if qop.qubits.len() != qubits.len() {
                return Err(SemanticError::ArityMismatch {
                    gate: qop.gate.clone(),
                    expected: qubits.len(),
                    found: qop.qubits.len(),
                    span: qop.span,
                });
            }
        } else if !self.is_builtin_gate(&qop.gate) {
            return Err(SemanticError::UndefinedSymbol {
                name: qop.gate.clone(),
                span: qop.span,
            });
        }
        
        // Check that all qubit references are valid
        for qubit_ref in &qop.qubits {
            self.check_qubit_ref(qubit_ref)?;
        }
        
        Ok(())
    }
    
    /// Analyze measurement
    fn analyze_measure(&mut self, qubit: &QubitRef, bit: &BitRef, span: Span) -> SemanticResult<()> {
        self.check_qubit_ref(qubit)?;
        self.check_bit_ref(bit)?;
        
        // Check that sizes match if both are registers
        match (qubit, bit) {
            (QubitRef::Register { name: qname }, BitRef::Register { name: cname }) => {
                let qsize = self.symbols.get_qreg_size(qname).unwrap();
                let csize = self.symbols.get_creg_size(cname).unwrap();
                if qsize != csize {
                    return Err(SemanticError::InvalidMeasurementTarget {
                        message: format!(
                            "Register size mismatch: {} has {} qubits, {} has {} bits",
                            qname, qsize, cname, csize
                        ),
                        span,
                    });
                }
            }
            _ => {}
        }
        
        Ok(())
    }
    
    /// Analyze reset
    fn analyze_reset(&mut self, qubit: &QubitRef, _span: Span) -> SemanticResult<()> {
        self.check_qubit_ref(qubit)
    }
    
    /// Analyze barrier
    fn analyze_barrier(&mut self, qubits: &[QubitRef], _span: Span) -> SemanticResult<()> {
        for qubit in qubits {
            self.check_qubit_ref(qubit)?;
        }
        Ok(())
    }
    
    /// Analyze conditional
    fn analyze_if(
        &mut self,
        creg: &str,
        _value: i64,
        op: &QuantumOp,
        span: Span,
    ) -> SemanticResult<()> {
        // Check that classical register exists
        if !self.symbols.is_creg(creg) {
            return Err(SemanticError::UndefinedSymbol {
                name: creg.to_string(),
                span,
            });
        }
        
        // Analyze the quantum operation
        self.analyze_quantum_op(op)
    }
    
    /// Check qubit reference validity
    fn check_qubit_ref(&self, qubit_ref: &QubitRef) -> SemanticResult<()> {
        match qubit_ref {
            QubitRef::Indexed { name, index } => {
                if let Some(size) = self.symbols.get_qreg_size(name) {
                    if *index >= size {
                        return Err(SemanticError::InvalidRegisterIndex {
                            register: name.clone(),
                            index: *index,
                            size,
                            span: Span::new(0, 0, 0), // TODO: Better span tracking
                        });
                    }
                } else if self.symbols.lookup(name).is_none() {
                    return Err(SemanticError::UndefinedSymbol {
                        name: name.clone(),
                        span: Span::new(0, 0, 0),
                    });
                }
            }
            QubitRef::Register { name } => {
                if !self.symbols.is_qreg(name) && self.symbols.lookup(name).is_none() {
                    return Err(SemanticError::UndefinedSymbol {
                        name: name.clone(),
                        span: Span::new(0, 0, 0),
                    });
                }
            }
        }
        Ok(())
    }
    
    /// Check bit reference validity
    fn check_bit_ref(&self, bit_ref: &BitRef) -> SemanticResult<()> {
        match bit_ref {
            BitRef::Indexed { name, index } => {
                if let Some(size) = self.symbols.get_creg_size(name) {
                    if *index >= size {
                        return Err(SemanticError::InvalidRegisterIndex {
                            register: name.clone(),
                            index: *index,
                            size,
                            span: Span::new(0, 0, 0),
                        });
                    }
                } else {
                    return Err(SemanticError::UndefinedSymbol {
                        name: name.clone(),
                        span: Span::new(0, 0, 0),
                    });
                }
            }
            BitRef::Register { name } => {
                if !self.symbols.is_creg(name) {
                    return Err(SemanticError::UndefinedSymbol {
                        name: name.clone(),
                        span: Span::new(0, 0, 0),
                    });
                }
            }
        }
        Ok(())
    }
    
    /// Check if a gate is a built-in gate
    fn is_builtin_gate(&self, name: &str) -> bool {
        matches!(name, "U" | "CX" | "u" | "cx" | "h" | "x" | "y" | "z" | "s" | "t" | "sdg" | "tdg")
    }
}

impl Default for SemanticAnalyzer {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use qataaum_parser::{QRegDecl, CRegDecl};

    #[test]
    fn test_qreg_declaration() {
        let mut analyzer = SemanticAnalyzer::new();
        
        let qreg = QRegDecl {
            name: "q".to_string(),
            size: 2,
            span: Span::new(1, 0, 0),
        };
        
        assert!(analyzer.analyze_qreg_decl(&qreg.name, qreg.size, qreg.span).is_ok());
        assert!(analyzer.symbols.is_qreg("q"));
        assert_eq!(analyzer.symbols.get_qreg_size("q"), Some(2));
    }

    #[test]
    fn test_duplicate_register() {
        let mut analyzer = SemanticAnalyzer::new();
        
        let qreg1 = QRegDecl {
            name: "q".to_string(),
            size: 2,
            span: Span::new(1, 0, 0),
        };
        
        let qreg2 = QRegDecl {
            name: "q".to_string(),
            size: 3,
            span: Span::new(2, 0, 0),
        };
        
        assert!(analyzer.analyze_qreg_decl(&qreg1.name, qreg1.size, qreg1.span).is_ok());
        assert!(analyzer.analyze_qreg_decl(&qreg2.name, qreg2.size, qreg2.span).is_err());
    }

    #[test]
    fn test_invalid_register_size() {
        let mut analyzer = SemanticAnalyzer::new();
        
        let qreg = QRegDecl {
            name: "q".to_string(),
            size: 0,
            span: Span::new(1, 0, 0),
        };
        
        assert!(analyzer.analyze_qreg_decl(&qreg.name, qreg.size, qreg.span).is_err());
    }

    #[test]
    fn test_qubit_ref_validation() {
        let mut analyzer = SemanticAnalyzer::new();
        
        // Define a register
        analyzer.analyze_qreg_decl("q", 2, Span::new(1, 0, 0)).unwrap();
        
        // Valid index
        let valid_ref = QubitRef::Indexed {
            name: "q".to_string(),
            index: 0,
        };
        assert!(analyzer.check_qubit_ref(&valid_ref).is_ok());
        
        // Invalid index
        let invalid_ref = QubitRef::Indexed {
            name: "q".to_string(),
            index: 5,
        };
        assert!(analyzer.check_qubit_ref(&invalid_ref).is_err());
        
        // Undefined register
        let undefined_ref = QubitRef::Register {
            name: "undefined".to_string(),
        };
        assert!(analyzer.check_qubit_ref(&undefined_ref).is_err());
    }
}

// Made with Bob