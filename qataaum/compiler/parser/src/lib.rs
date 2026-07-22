//! QATAAUM Parser - OpenQASM 2/3 and MetaQASM-4 Parser
//!
//! This is a clean-room implementation based solely on public OpenQASM specifications.
//! NOT derived from Qiskit parser implementation.
//!
//! Public Sources:
//! - OpenQASM 2.0: https://github.com/Qiskit/openqasm/tree/OpenQASM2.x
//! - OpenQASM 3.x: https://openqasm.com/
//!
//! See RESEARCH_LEDGER.md for complete source provenance.

pub mod openqasm2;
pub mod openqasm3;
pub mod metaqasm4;
pub mod ast;
pub mod error;

pub use error::{ParseError, ParseResult};
pub use ast::*;

// Made with Bob
