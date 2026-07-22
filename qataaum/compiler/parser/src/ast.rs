//! Abstract Syntax Tree definitions for OpenQASM 2/3 and MetaQASM-4
//!
//! Clean-room implementation based on public OpenQASM specifications.
//! NOT derived from Qiskit AST implementation.
//!
//! Public Sources:
//! - OpenQASM 2.0: https://github.com/Qiskit/openqasm/tree/OpenQASM2.x
//! - OpenQASM 3.x: https://openqasm.com/

use serde::{Deserialize, Serialize};

/// Source location for error reporting
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Span {
    pub line: usize,
    pub column: usize,
    pub length: usize,
}

impl Span {
    pub fn new(line: usize, column: usize, length: usize) -> Self {
        Self { line, column, length }
    }
}

/// OpenQASM 2.0 Program
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Program {
    pub version: Version,
    pub includes: Vec<Include>,
    pub statements: Vec<Statement>,
}

/// Version declaration
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Version {
    pub major: u32,
    pub minor: u32,
    pub span: Span,
}

/// Include statement
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Include {
    pub filename: String,
    pub span: Span,
}

/// Top-level statement
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Statement {
    /// Quantum register declaration: qreg name[size];
    QRegDecl(QRegDecl),
    
    /// Classical register declaration: creg name[size];
    CRegDecl(CRegDecl),
    
    /// Gate definition
    GateDecl(GateDecl),
    
    /// Opaque gate declaration
    OpaqueDecl(OpaqueDecl),
    
    /// Quantum operation
    QuantumOp(QuantumOp),
    
    /// Measurement: measure qubit -> bit;
    Measure(Measure),
    
    /// Reset: reset qubit;
    Reset(Reset),
    
    /// Barrier: barrier qubits;
    Barrier(Barrier),
    
    /// Conditional: if(creg==value) qop;
    If(If),
}

/// Quantum register declaration
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct QRegDecl {
    pub name: String,
    pub size: usize,
    pub span: Span,
}

/// Classical register declaration
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CRegDecl {
    pub name: String,
    pub size: usize,
    pub span: Span,
}

/// Gate declaration
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GateDecl {
    pub name: String,
    pub params: Vec<String>,
    pub qubits: Vec<String>,
    pub body: Vec<GateOp>,
    pub span: Span,
}

/// Opaque gate declaration
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct OpaqueDecl {
    pub name: String,
    pub params: Vec<String>,
    pub qubits: Vec<String>,
    pub span: Span,
}

/// Quantum operation
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct QuantumOp {
    pub gate: String,
    pub params: Vec<Expr>,
    pub qubits: Vec<QubitRef>,
    pub span: Span,
}

/// Gate operation (inside gate body)
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum GateOp {
    /// U gate: U(theta, phi, lambda) qubit;
    U(UGate),
    
    /// CX gate: CX control, target;
    CX(CXGate),
    
    /// Custom gate application
    Apply(QuantumOp),
    
    /// Barrier
    Barrier(Vec<String>),
}

/// U gate (universal single-qubit gate)
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct UGate {
    pub theta: Expr,
    pub phi: Expr,
    pub lambda: Expr,
    pub qubit: String,
    pub span: Span,
}

/// CX gate (CNOT)
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CXGate {
    pub control: String,
    pub target: String,
    pub span: Span,
}

/// Measurement
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Measure {
    pub qubit: QubitRef,
    pub bit: BitRef,
    pub span: Span,
}

/// Reset operation
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Reset {
    pub qubit: QubitRef,
    pub span: Span,
}

/// Barrier operation
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Barrier {
    pub qubits: Vec<QubitRef>,
    pub span: Span,
}

/// Conditional operation
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct If {
    pub creg: String,
    pub value: i64,
    pub op: Box<QuantumOp>,
    pub span: Span,
}

/// Qubit reference
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum QubitRef {
    /// Single qubit: qreg[index]
    Indexed { name: String, index: usize },
    
    /// Entire register: qreg
    Register { name: String },
}

/// Bit reference
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum BitRef {
    /// Single bit: creg[index]
    Indexed { name: String, index: usize },
    
    /// Entire register: creg
    Register { name: String },
}

/// Expression (for gate parameters)
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Expr {
    /// Real number literal
    Real(f64),
    
    /// Integer literal
    Int(i64),
    
    /// Pi constant
    Pi,
    
    /// Parameter reference
    Param(String),
    
    /// Binary operation
    BinOp {
        op: BinOp,
        left: Box<Expr>,
        right: Box<Expr>,
    },
    
    /// Unary operation
    UnaryOp {
        op: UnaryOp,
        expr: Box<Expr>,
    },
    
    /// Function call
    Call {
        func: String,
        args: Vec<Expr>,
    },
}

/// Binary operators
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum BinOp {
    Add,
    Sub,
    Mul,
    Div,
    Pow,
}

/// Unary operators
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum UnaryOp {
    Neg,
    Sin,
    Cos,
    Tan,
    Exp,
    Ln,
    Sqrt,
}

impl Program {
    pub fn new(version: Version) -> Self {
        Self {
            version,
            includes: Vec::new(),
            statements: Vec::new(),
        }
    }
}

impl Version {
    pub fn openqasm2() -> Self {
        Self {
            major: 2,
            minor: 0,
            span: Span::new(0, 0, 0),
        }
    }
    
    pub fn openqasm3() -> Self {
        Self {
            major: 3,
            minor: 0,
            span: Span::new(0, 0, 0),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_version_creation() {
        let v2 = Version::openqasm2();
        assert_eq!(v2.major, 2);
        assert_eq!(v2.minor, 0);
        
        let v3 = Version::openqasm3();
        assert_eq!(v3.major, 3);
        assert_eq!(v3.minor, 0);
    }

    #[test]
    fn test_program_creation() {
        let prog = Program::new(Version::openqasm2());
        assert_eq!(prog.version.major, 2);
        assert!(prog.includes.is_empty());
        assert!(prog.statements.is_empty());
    }
}

// Made with Bob
