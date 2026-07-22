//! QATAAUM Semantic Analyzer
//!
//! Clean-room implementation of semantic analysis for OpenQASM programs.
//! NOT derived from Qiskit semantic analyzer.
//!
//! Performs:
//! - Name resolution
//! - Type checking
//! - Register size validation
//! - Gate arity checking
//! - Scope management

pub mod error;
pub mod symbol_table;
pub mod analyzer;

pub use error::{SemanticError, SemanticResult};
pub use symbol_table::{SymbolTable, Symbol, SymbolKind};
pub use analyzer::SemanticAnalyzer;

// Made with Bob