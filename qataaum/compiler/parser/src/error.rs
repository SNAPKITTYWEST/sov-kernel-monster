//! Parser error types
//!
//! Clean-room implementation - not derived from Qiskit

use std::fmt;

/// Result type for parser operations
pub type ParseResult<T> = Result<T, ParseError>;

/// Parser error types
#[derive(Debug, Clone, PartialEq)]
pub enum ParseError {
    /// Lexical error - invalid token
    LexError {
        message: String,
        line: usize,
        column: usize,
    },
    
    /// Syntax error - unexpected token
    SyntaxError {
        expected: String,
        found: String,
        line: usize,
        column: usize,
    },
    
    /// Semantic error - valid syntax but invalid meaning
    SemanticError {
        message: String,
        line: usize,
        column: usize,
    },
    
    /// Version mismatch
    VersionError {
        expected: String,
        found: String,
    },
    
    /// Unsupported feature
    UnsupportedFeature {
        feature: String,
        line: usize,
        column: usize,
    },
    
    /// End of file reached unexpectedly
    UnexpectedEof {
        expected: String,
    },
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ParseError::LexError { message, line, column } => {
                write!(f, "Lexical error at {}:{}: {}", line, column, message)
            }
            ParseError::SyntaxError { expected, found, line, column } => {
                write!(
                    f,
                    "Syntax error at {}:{}: expected {}, found {}",
                    line, column, expected, found
                )
            }
            ParseError::SemanticError { message, line, column } => {
                write!(f, "Semantic error at {}:{}: {}", line, column, message)
            }
            ParseError::VersionError { expected, found } => {
                write!(f, "Version error: expected {}, found {}", expected, found)
            }
            ParseError::UnsupportedFeature { feature, line, column } => {
                write!(
                    f,
                    "Unsupported feature at {}:{}: {}",
                    line, column, feature
                )
            }
            ParseError::UnexpectedEof { expected } => {
                write!(f, "Unexpected end of file: expected {}", expected)
            }
        }
    }
}

impl std::error::Error for ParseError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_display() {
        let err = ParseError::LexError {
            message: "invalid character".to_string(),
            line: 1,
            column: 5,
        };
        assert_eq!(
            err.to_string(),
            "Lexical error at 1:5: invalid character"
        );
    }
}

// Made with Bob
