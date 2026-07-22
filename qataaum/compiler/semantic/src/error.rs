//! Semantic analysis error types
//!
//! Clean-room implementation - not derived from Qiskit

use std::fmt;
use qataaum_parser::Span;

/// Result type for semantic analysis
pub type SemanticResult<T> = Result<T, SemanticError>;

/// Semantic analysis errors
#[derive(Debug, Clone, PartialEq)]
pub enum SemanticError {
    /// Undefined symbol
    UndefinedSymbol {
        name: String,
        span: Span,
    },
    
    /// Symbol already defined
    DuplicateSymbol {
        name: String,
        original_span: Span,
        duplicate_span: Span,
    },
    
    /// Type mismatch
    TypeMismatch {
        expected: String,
        found: String,
        span: Span,
    },
    
    /// Invalid register size
    InvalidRegisterSize {
        name: String,
        size: usize,
        span: Span,
    },
    
    /// Invalid register index
    InvalidRegisterIndex {
        register: String,
        index: usize,
        size: usize,
        span: Span,
    },
    
    /// Gate arity mismatch
    ArityMismatch {
        gate: String,
        expected: usize,
        found: usize,
        span: Span,
    },
    
    /// Parameter count mismatch
    ParameterMismatch {
        gate: String,
        expected: usize,
        found: usize,
        span: Span,
    },
    
    /// Invalid gate definition
    InvalidGateDefinition {
        message: String,
        span: Span,
    },
    
    /// Circular gate dependency
    CircularDependency {
        gate: String,
        span: Span,
    },
    
    /// Invalid measurement target
    InvalidMeasurementTarget {
        message: String,
        span: Span,
    },
    
    /// Invalid conditional
    InvalidConditional {
        message: String,
        span: Span,
    },
}

impl fmt::Display for SemanticError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SemanticError::UndefinedSymbol { name, span } => {
                write!(
                    f,
                    "Undefined symbol '{}' at line {}, column {}",
                    name, span.line, span.column
                )
            }
            SemanticError::DuplicateSymbol { name, original_span, duplicate_span } => {
                write!(
                    f,
                    "Symbol '{}' already defined at line {}, column {}; duplicate at line {}, column {}",
                    name, original_span.line, original_span.column,
                    duplicate_span.line, duplicate_span.column
                )
            }
            SemanticError::TypeMismatch { expected, found, span } => {
                write!(
                    f,
                    "Type mismatch at line {}, column {}: expected {}, found {}",
                    span.line, span.column, expected, found
                )
            }
            SemanticError::InvalidRegisterSize { name, size, span } => {
                write!(
                    f,
                    "Invalid register size for '{}' at line {}, column {}: size must be positive, got {}",
                    name, span.line, span.column, size
                )
            }
            SemanticError::InvalidRegisterIndex { register, index, size, span } => {
                write!(
                    f,
                    "Invalid index {} for register '{}' (size {}) at line {}, column {}",
                    index, register, size, span.line, span.column
                )
            }
            SemanticError::ArityMismatch { gate, expected, found, span } => {
                write!(
                    f,
                    "Gate '{}' expects {} qubits, got {} at line {}, column {}",
                    gate, expected, found, span.line, span.column
                )
            }
            SemanticError::ParameterMismatch { gate, expected, found, span } => {
                write!(
                    f,
                    "Gate '{}' expects {} parameters, got {} at line {}, column {}",
                    gate, expected, found, span.line, span.column
                )
            }
            SemanticError::InvalidGateDefinition { message, span } => {
                write!(
                    f,
                    "Invalid gate definition at line {}, column {}: {}",
                    span.line, span.column, message
                )
            }
            SemanticError::CircularDependency { gate, span } => {
                write!(
                    f,
                    "Circular dependency detected in gate '{}' at line {}, column {}",
                    gate, span.line, span.column
                )
            }
            SemanticError::InvalidMeasurementTarget { message, span } => {
                write!(
                    f,
                    "Invalid measurement target at line {}, column {}: {}",
                    span.line, span.column, message
                )
            }
            SemanticError::InvalidConditional { message, span } => {
                write!(
                    f,
                    "Invalid conditional at line {}, column {}: {}",
                    span.line, span.column, message
                )
            }
        }
    }
}

impl std::error::Error for SemanticError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_undefined_symbol_display() {
        let err = SemanticError::UndefinedSymbol {
            name: "q".to_string(),
            span: Span::new(1, 5, 1),
        };
        assert!(err.to_string().contains("Undefined symbol 'q'"));
    }

    #[test]
    fn test_duplicate_symbol_display() {
        let err = SemanticError::DuplicateSymbol {
            name: "q".to_string(),
            original_span: Span::new(1, 5, 1),
            duplicate_span: Span::new(2, 5, 1),
        };
        assert!(err.to_string().contains("already defined"));
    }
}

// Made with Bob