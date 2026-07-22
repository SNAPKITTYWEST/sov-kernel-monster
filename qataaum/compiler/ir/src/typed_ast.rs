//! Typed AST - IR Level 1
//!
//! Transforms the untyped parser AST into a typed representation
//! with resolved names, types, and semantic information.
//!
//! Clean-room implementation - not derived from Qiskit

use crate::types::{BitId, QubitId, Type};
use qataaum_parser::Span;
use qataaum_semantic::{SemanticError, Symbol, SymbolKind, SymbolTable};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Typed program
#[derive(Debug, Clone)]
pub struct TypedProgram {
    /// OpenQASM version
    pub version: String,
    
    /// Quantum register declarations
    pub qregs: Vec<QRegDecl>,
    
    /// Classical register declarations
    pub cregs: Vec<CRegDecl>,
    
    /// Gate definitions
    pub gates: Vec<GateDecl>,
    
    /// Opaque gate declarations
    pub opaques: Vec<OpaqueDecl>,
    
    /// Main circuit statements
    pub statements: Vec<TypedStatement>,
    
    /// Symbol table
    pub symbols: SymbolTable,
    
    /// Type information
    pub types: HashMap<String, Type>,
}

/// Quantum register declaration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QRegDecl {
    pub name: String,
    pub size: usize,
    pub span: Span,
}

/// Classical register declaration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CRegDecl {
    pub name: String,
    pub size: usize,
    pub span: Span,
}

/// Gate declaration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GateDecl {
    pub name: String,
    pub params: Vec<String>,
    pub qubits: Vec<String>,
    pub body: Vec<TypedStatement>,
    pub span: Span,
}

/// Opaque gate declaration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OpaqueDecl {
    pub name: String,
    pub params: Vec<String>,
    pub qubits: Vec<String>,
    pub span: Span,
}

/// Typed statement
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TypedStatement {
    /// Gate application
    Gate {
        name: String,
        params: Vec<TypedExpr>,
        qubits: Vec<QubitRef>,
        span: Span,
    },
    
    /// Measurement
    Measure {
        qubit: QubitRef,
        bit: BitRef,
        span: Span,
    },
    
    /// Reset
    Reset {
        qubit: QubitRef,
        span: Span,
    },
    
    /// Barrier
    Barrier {
        qubits: Vec<QubitRef>,
        span: Span,
    },
    
    /// Conditional statement
    If {
        register: String,
        value: u64,
        body: Box<TypedStatement>,
        span: Span,
    },
}

/// Typed expression
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TypedExpr {
    /// Real number literal
    Real {
        value: f64,
        ty: Type,
        span: Span,
    },
    
    /// Integer literal
    Integer {
        value: i64,
        ty: Type,
        span: Span,
    },
    
    /// Pi constant
    Pi {
        ty: Type,
        span: Span,
    },
    
    /// Parameter reference
    Parameter {
        name: String,
        ty: Type,
        span: Span,
    },
    
    /// Binary operation
    Binary {
        op: BinaryOp,
        left: Box<TypedExpr>,
        right: Box<TypedExpr>,
        ty: Type,
        span: Span,
    },
    
    /// Unary operation
    Unary {
        op: UnaryOp,
        expr: Box<TypedExpr>,
        ty: Type,
        span: Span,
    },
    
    /// Function call
    Call {
        func: Function,
        arg: Box<TypedExpr>,
        ty: Type,
        span: Span,
    },
}

impl TypedExpr {
    /// Get the type of this expression
    pub fn ty(&self) -> &Type {
        match self {
            TypedExpr::Real { ty, .. }
            | TypedExpr::Integer { ty, .. }
            | TypedExpr::Pi { ty, .. }
            | TypedExpr::Parameter { ty, .. }
            | TypedExpr::Binary { ty, .. }
            | TypedExpr::Unary { ty, .. }
            | TypedExpr::Call { ty, .. } => ty,
        }
    }
    
    /// Get the span of this expression
    pub fn span(&self) -> Span {
        match self {
            TypedExpr::Real { span, .. }
            | TypedExpr::Integer { span, .. }
            | TypedExpr::Pi { span, .. }
            | TypedExpr::Parameter { span, .. }
            | TypedExpr::Binary { span, .. }
            | TypedExpr::Unary { span, .. }
            | TypedExpr::Call { span, .. } => *span,
        }
    }
}

/// Binary operator
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum BinaryOp {
    Add,
    Sub,
    Mul,
    Div,
    Pow,
}

/// Unary operator
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum UnaryOp {
    Neg,
    Pos,
}

/// Mathematical function
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Function {
    Sin,
    Cos,
    Tan,
    Exp,
    Ln,
    Sqrt,
}

/// Qubit reference
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QubitRef {
    pub register: String,
    pub index: Option<usize>,
    pub id: QubitId,
    pub ty: Type,
    pub span: Span,
}

/// Bit reference
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BitRef {
    pub register: String,
    pub index: Option<usize>,
    pub id: BitId,
    pub ty: Type,
    pub span: Span,
}

/// Type checker and AST transformer
pub struct TypeChecker {
    pub symbols: SymbolTable,
    pub types: HashMap<String, Type>,
    next_qubit_id: usize,
    next_bit_id: usize,
}

impl TypeChecker {
    /// Create a new type checker
    pub fn new(symbols: SymbolTable) -> Self {
        Self {
            symbols,
            types: HashMap::new(),
            next_qubit_id: 0,
            next_bit_id: 0,
        }
    }
    
    /// Allocate a new qubit ID
    fn alloc_qubit(&mut self) -> QubitId {
        let id = QubitId(self.next_qubit_id);
        self.next_qubit_id += 1;
        id
    }
    
    /// Allocate a new bit ID
    fn alloc_bit(&mut self) -> BitId {
        let id = BitId(self.next_bit_id);
        self.next_bit_id += 1;
        id
    }
    
    /// Type check a qubit argument
    pub fn check_qubit(
        &mut self,
        register: &str,
        index: Option<usize>,
        span: Span,
    ) -> Result<QubitRef, SemanticError> {
        // Verify register exists and is quantum
        let symbol = self.symbols.lookup(register)
            .ok_or_else(|| SemanticError::UndefinedSymbol {
                name: register.to_string(),
                span,
            })?;
        
        let size = match symbol.kind {
            qataaum_semantic::SymbolKind::QReg { size } => size,
            _ => return Err(SemanticError::TypeMismatch {
                expected: "quantum register".to_string(),
                found: "other".to_string(),
                span,
            }),
        };
        
        // Verify index is in bounds
        if let Some(idx) = index {
            if idx >= size {
                return Err(SemanticError::InvalidRegisterIndex {
                    register: register.to_string(),
                    index: idx,
                    size,
                    span,
                });
            }
        }
        
        Ok(QubitRef {
            register: register.to_string(),
            index,
            id: self.alloc_qubit(),
            ty: Type::Qubit,
            span,
        })
    }
    
    /// Type check a bit argument
    pub fn check_bit(
        &mut self,
        register: &str,
        index: Option<usize>,
        span: Span,
    ) -> Result<BitRef, SemanticError> {
        // Verify register exists and is classical
        let symbol = self.symbols.lookup(register)
            .ok_or_else(|| SemanticError::UndefinedSymbol {
                name: register.to_string(),
                span,
            })?;
        
        let size = match symbol.kind {
            qataaum_semantic::SymbolKind::CReg { size } => size,
            _ => return Err(SemanticError::TypeMismatch {
                expected: "classical register".to_string(),
                found: "other".to_string(),
                span,
            }),
        };
        
        // Verify index is in bounds
        if let Some(idx) = index {
            if idx >= size {
                return Err(SemanticError::InvalidRegisterIndex {
                    register: register.to_string(),
                    index: idx,
                    size,
                    span,
                });
            }
        }
        
        Ok(BitRef {
            register: register.to_string(),
            index,
            id: self.alloc_bit(),
            ty: Type::Bit,
            span,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use qataaum_semantic::SymbolKind;

    #[test]
    fn test_typed_expr_type() {
        let expr = TypedExpr::Real {
            value: 3.14,
            ty: Type::Float { bits: 64 },
            span: Span::new(0, 0, 4),
        };
        assert_eq!(*expr.ty(), Type::Float { bits: 64 });
    }

    #[test]
    fn test_type_checker_qubit() {
        let mut symbols = SymbolTable::new();
        let symbol = Symbol {
            name: "q".to_string(),
            kind: SymbolKind::QReg { size: 2 },
            span: Span::new(0, 0, 1),
        };
        symbols.define(symbol).unwrap();
        
        let mut checker = TypeChecker::new(symbols);
        let qref = checker.check_qubit("q", Some(0), Span::new(0, 0, 1)).unwrap();
        
        assert_eq!(qref.register, "q");
        assert_eq!(qref.index, Some(0));
        assert_eq!(qref.ty, Type::Qubit);
    }

    #[test]
    fn test_type_checker_bit() {
        let mut symbols = SymbolTable::new();
        let symbol = Symbol {
            name: "c".to_string(),
            kind: SymbolKind::CReg { size: 2 },
            span: Span::new(0, 0, 1),
        };
        symbols.define(symbol).unwrap();
        
        let mut checker = TypeChecker::new(symbols);
        let bref = checker.check_bit("c", Some(1), Span::new(0, 0, 1)).unwrap();
        
        assert_eq!(bref.register, "c");
        assert_eq!(bref.index, Some(1));
        assert_eq!(bref.ty, Type::Bit);
    }

    #[test]
    fn test_type_checker_invalid_index() {
        let mut symbols = SymbolTable::new();
        let symbol = Symbol {
            name: "q".to_string(),
            kind: SymbolKind::QReg { size: 2 },
            span: Span::new(0, 0, 1),
        };
        symbols.define(symbol).unwrap();
        
        let mut checker = TypeChecker::new(symbols);
        let result = checker.check_qubit("q", Some(5), Span::new(0, 0, 1));
        
        assert!(matches!(result, Err(SemanticError::InvalidRegisterIndex { .. })));
    }
}

// Made with Bob