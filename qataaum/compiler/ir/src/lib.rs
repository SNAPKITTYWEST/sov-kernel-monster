//! QATAAUM Intermediate Representation
//!
//! IR Level 0: Source AST (from parser)
//! IR Level 1: Typed AST (this crate)
//! IR Level 2: CFG (control-flow graph)
//! IR Level 3: SSA (static single assignment)
//! IR Level 4: GATE (hardware-independent gates)
//! IR Level 5: TOPO (target-coupled placement and routing)
//! IR Level 6: SCHEDULE (time-aware scheduling)
//! IR Level 7: PULSE (provider-neutral pulse representation)
//! IR Level 8: EXEC (executable package with metadata and verification)
//!
//! Clean-room implementation - not derived from Qiskit

pub mod types;
pub mod typed_ast;
pub mod builder;
pub mod cfg;
pub mod cfg_builder;
pub mod ssa;
pub mod gate;
pub mod topo;
pub mod schedule;
pub mod pulse;
pub mod exec;

pub use types::*;
pub use typed_ast::*;
pub use builder::*;
pub use cfg::*;
pub use cfg_builder::*;
pub use ssa::*;
pub use gate::*;
pub use topo::*;
pub use schedule::*;
pub use pulse::*;
pub use exec::*;

// Made with Bob