//! # SEB L7 Universe Substrate
//!
//! Artifact manifest system, searchable repository, and CVMGate verification pipeline.
//!
//! ## Components
//!
//! - **manifest.rs** - Artifact manifest format (tier, invariants, proofs, tests)
//! - **search_substrate.rs** - Searchable repository (query by invariant/tier)
//! - **compile_verify_merge.rs** - CVMGate pipeline (5-step verification + promotion)
//! - **repository.json** - Initial T0/T1/T2/T3 artifact catalog
//!
//! ## Usage
//!
//! ```ignore
//! use seb_universe::{ArtifactManifest, CVMGate, Universe};
//!
//! #[tokio::main]
//! async fn main() {
//!     // Load repository
//!     let mut universe = Universe::load_from_file("repository.json").await.unwrap();
//!
//!     // Propose new artifact (T2)
//!     let artifact = ArtifactManifest::new(
//!         "my_artifact".into(),
//!         "segment_rotation".into(),
//!         "1.0.0".into(),
//!         "rust".into(),
//!         2, // T2
//!     );
//!
//!     // Run through CVMGate
//!     let gate = CVMGate::new();
//!     match gate.process(&artifact).await {
//!         Ok(result) => println!("CVMGate passed: {:?}", result),
//!         Err(e) => println!("CVMGate failed: {}", e),
//!     }
//! }
//! ```

pub mod compile_verify_merge;
pub mod manifest;
pub mod search_substrate;

pub use compile_verify_merge::{CVMGate, CVMGateResult, CVMGateStep};
pub use manifest::{ArtifactManifest, ArtifactTier};
pub use search_substrate::Universe;

// Re-export common types
pub use anyhow::{anyhow, Result};
