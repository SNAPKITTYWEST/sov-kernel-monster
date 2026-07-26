//! Multi-agent reasoning conversation demo
//!
//! Demonstrates:
//! 1. kernel_001 reasons about offset 101 commit
//! 2. policy_001 extends kernel trace with authorization check
//! 3. auditor_001 challenges policy decision with counter-evidence
//! 4. All traces immutable, queryable, visualized as sequence diagram

use seb_reasoning::{
    L1KernelIntegration, L3PolicyIntegration, L5KnowledgeIntegration, ReasoningEventType,
    ReasoningPartition, ReasoningStreamManager, ReasoningStep, ReasoningTrace, TraceRelation,
};

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();

    println!("=== SEB L6 Reasoning Protocol Demo ===\n");

    // Initialize layer integrations
    let l1 = L1KernelIntegration::new("kernel_001".into());
    let l3 = L3PolicyIntegration::new("policy_001".into());
    let l5 = L5KnowledgeIntegration::new();

    // Initialize stream manager
    let manager = ReasoningStreamManager::new();

    println!("--- Phase 1: Kernel reasons about offset 101 ---");
    // Kernel appends and commits event at offset 101
    l1.on_kernel_append(101, "abc123def456789").await;
    l1.on_kernel_commit(101, "hash_101_xyz").await;

    // Retrieve kernel trace
    let kernel_events = l1.protocol_handler.get_events().await;
    println!("Kernel emitted {} events", kernel_events.len());

    // Create kernel reasoning trace
    let mut kernel_trace = ReasoningTrace::new("kernel_001".into(), "append".into(), 1);
    kernel_trace.set_query(Some("Append offset 101".into()));
    kernel_trace.add_step(ReasoningStep::Retrieve {
        source: "L1::WAL".into(),
        symbol: "offset_101".into(),
        result: serde_json::json!({
            "offset": 101,
            "hash": "abc123def456789",
        }),
    });
    kernel_trace.add_step(ReasoningStep::Verify {
        target: "offset_101".into(),
        method: "prev_hash_chain".into(),
        valid: true,
        error: None,
    });
    let kernel_trace_id = kernel_trace.finalize();
    manager.store_trace(kernel_trace.clone()).await;
    l5.store_reasoning_trace(kernel_trace).await;

    println!("Kernel trace ID: {}", &kernel_trace_id[0..16]);

    println!("\n--- Phase 2: Policy extends kernel trace with authorization ---");
    // Policy gate checks authorization
    l3.on_policy_authorize("kernel_001", "commit_offset", "offset_101", true, "L0_invariant_satisfied")
        .await;

    let policy_events = l3.protocol_handler.get_events().await;
    println!("Policy emitted {} events", policy_events.len());

    // Create policy reasoning trace that extends kernel trace
    let mut policy_trace = ReasoningTrace::new("policy_001".into(), "authorize".into(), 1);
    policy_trace.set_query(Some("Authorize kernel_001 commit_offset".into()));
    policy_trace.add_parent(TraceRelation::Extends {
        parent_trace_id: kernel_trace_id.clone(),
    });

    policy_trace.add_step(ReasoningStep::Retrieve {
        source: "L3::Datalog".into(),
        symbol: "policy_commit_offset".into(),
        result: serde_json::json!({
            "principal": "kernel_001",
            "action": "commit_offset",
            "allowed": true,
        }),
    });

    policy_trace.add_step(ReasoningStep::CheckAuthorization {
        principal: "kernel_001".into(),
        action: "commit_offset".into(),
        resource: "offset_101".into(),
        allowed: true,
        reason: "L0_invariant_satisfied".into(),
    });

    policy_trace.add_step(ReasoningStep::Conclude {
        conclusion: "Authorization: ALLOW - offset monotonic and signature valid".into(),
        confidence: 0.99,
    });

    let policy_trace_id = policy_trace.finalize();
    manager.store_trace(policy_trace.clone()).await;
    l5.store_reasoning_trace(policy_trace).await;

    println!("Policy trace ID: {}", &policy_trace_id[0..16]);

    println!("\n--- Phase 3: Auditor challenges policy decision ---");
    // Auditor challenges with counter-evidence
    let mut auditor_trace = ReasoningTrace::new("auditor_001".into(), "challenge".into(), 1);
    auditor_trace.set_query(Some("Challenge policy authorization".into()));
    auditor_trace.add_parent(TraceRelation::Challenges {
        parent_trace_id: policy_trace_id.clone(),
    });

    auditor_trace.add_step(ReasoningStep::Retrieve {
        source: "L5::Audit".into(),
        symbol: "audit_log_101".into(),
        result: serde_json::json!({
            "offset": 101,
            "anomaly": "offset_not_monotonic",
        }),
    });

    auditor_trace.add_step(ReasoningStep::Challenge {
        target_trace_id: policy_trace_id.clone(),
        target_step_index: 2,
        counter_evidence: "Audit log shows offset 101 violates monotonicity constraint vs offset 100".into(),
    });

    let auditor_trace_id = auditor_trace.finalize();
    manager.store_trace(auditor_trace.clone()).await;
    l5.store_reasoning_trace(auditor_trace).await;

    println!("Auditor trace ID: {}", &auditor_trace_id[0..16]);

    println!("\n--- Phase 4: Query and visualize ---");
    // Query all traces
    let all_traces = manager.get_traces().await;
    println!("\nTotal traces: {}", all_traces.len());

    for trace in &all_traces {
        println!(
            "  - Agent: {}, Competency: {}, Steps: {}, ID: {}",
            trace.agent_id,
            trace.competency,
            trace.steps.len(),
            &trace.trace_id[0..16]
        );
    }

    // Get summary
    let summary = manager.get_summary().await;
    println!("\nSummary:");
    for (key, value) in summary {
        println!("  {}: {}", key, value);
    }

    // Generate Mermaid diagrams
    println!("\n--- Mermaid Sequence Diagram ---");
    let diagrams = manager.generate_diagrams().await;
    for diagram in diagrams {
        println!("{}", diagram.render());
    }

    // Generate timelines
    println!("\n--- Timeline for Each Trace ---");
    for trace in &all_traces {
        if let Some(timeline) = manager.get_timeline(&trace.trace_id).await {
            println!("{}", timeline.render_ascii());
        }
    }

    // Emit A2A protocol events
    println!("\n--- A2A Protocol Events ---");
    let partition = ReasoningPartition::AgentTraces("auditor_001".into());

    let challenge_event = seb_reasoning::a2a_protocol::A2AReasoningEvent::with_challenge(
        policy_trace_id.clone(),
        "Offset not monotonic".into(),
        Some(2),
    );

    println!("Challenge event: {}", challenge_event.as_json_line());

    let composition_event = seb_reasoning::a2a_protocol::A2AReasoningEvent::with_composition(
        uuid::Uuid::new_v4().to_string(),
        vec![kernel_trace_id, policy_trace_id, auditor_trace_id],
        "multi_agent_reasoning".into(),
    );

    println!("Composition event: {}", composition_event.as_json_line());

    println!("\n--- Cycle Detection ---");
    let has_cycles = all_traces[0].has_cycles(&all_traces);
    println!("Traces have cycles: {}", has_cycles);

    println!("\n--- Symbol Indexing ---");
    for trace in &all_traces {
        let symbols = trace.extract_symbols();
        if !symbols.is_empty() {
            println!("Trace {} symbols: {:?}", &trace.trace_id[0..16], symbols);
        }
    }

    println!("\n=== Demo Complete ===");
}
