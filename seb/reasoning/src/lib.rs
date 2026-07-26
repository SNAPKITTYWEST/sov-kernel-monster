//! # SEB L6 Agent-to-Agent Reasoning Protocol
//!
//! This module implements live reasoning traces + A2A protocol over SEB events.
//!
//! ## Components
//!
//! - **trace.rs** - Reasoning trace format (JSON-LD serializable)
//! - **a2a_protocol.rs** - A2A protocol with 7 event types
//! - **streaming.rs** - Live streaming, Mermaid diagrams, timelines
//! - **integration.rs** - Layer integration (L1, L3, L5) + Erlang NIF
//!
//! ## Usage
//!
//! ```ignore
//! use seb_reasoning::{ReasoningTrace, A2AReasoningEvent, ReasoningStreamManager};
//!
//! #[tokio::main]
//! async fn main() {
//!     // Create a reasoning trace
//!     let mut trace = ReasoningTrace::new("agent_001".into(), "verify".into(), 1);
//!     trace.add_step(ReasoningStep::Retrieve {
//!         source: "L1".into(),
//!         symbol: "offset_101".into(),
//!         result: serde_json::json!({"value": 42}),
//!     });
//!     let trace_id = trace.finalize();
//!
//!     // Emit events
//!     let manager = ReasoningStreamManager::new();
//!     manager.store_trace(trace).await;
//!
//!     // Generate visualizations
//!     let timeline = manager.get_timeline(&trace_id).await;
//! }
//! ```

pub mod a2a_protocol;
pub mod integration;
pub mod streaming;
pub mod trace;

pub use a2a_protocol::{A2AProtocolHandler, A2AReasoningEvent, ReasoningEventType, ReasoningPartition};
pub use integration::{L1KernelIntegration, L3PolicyIntegration, L5KnowledgeIntegration};
pub use streaming::{
    generate_sequence_diagram, MermaidSequenceDiagram, ReasoningStreamManager, StreamingMode,
    TraceTimeline,
};
pub use trace::{ReasoningStep, ReasoningTrace, TracedStep, TraceRelation};
