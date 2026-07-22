//! MetaQASM-4 Parser Module
//!
//! MetaQASM-4 is an ORIGINAL EXPERIMENTAL LANGUAGE designed by the QATAAUM project.
//! It is NOT OpenQASM 4 (which does not exist as a public standard).
//!
//! This module provides lexing and parsing for MetaQASM-4, which extends OpenQASM 3 with:
//! - Typed effects (CircuitM, MeasureM, DynamicM, PulseM, BackendM, ProofM, ReceiptM)
//! - Linear ownership (owned, borrowed, released)
//! - Refinement types ({x: Type | predicate})
//! - Capability indexing (backend<Capability>)
//! - Proof obligations (requires, ensures, invariant)

pub mod lexer;
pub mod ast;
pub mod parser;

pub use lexer::Token;
pub use ast::*;
pub use parser::{Parser, ParseError, ParseResult};

// Made with Bob
