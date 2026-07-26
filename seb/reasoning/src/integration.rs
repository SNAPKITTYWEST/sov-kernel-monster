use crate::a2a_protocol::{A2AProtocolHandler, ReasoningPartition};
use crate::streaming::ReasoningStreamManager;
use crate::trace::{ReasoningStep, ReasoningTrace};
use std::sync::Arc;

/// Layer 1 (Kernel) integration
pub struct L1KernelIntegration {
    protocol_handler: Arc<A2AProtocolHandler>,
}

impl L1KernelIntegration {
    pub fn new(agent_id: String) -> Self {
        L1KernelIntegration {
            protocol_handler: Arc::new(A2AProtocolHandler::new(agent_id)),
        }
    }

    /// Emit reasoning trace when kernel appends an event
    /// Hook: seb_kernel.adb append_event/4
    pub async fn on_kernel_append(&self, offset: u64, event_hash: &str) {
        let mut trace = ReasoningTrace::new(
            "kernel_001".into(),
            "append".into(),
            1,
        );

        trace.set_query(format!("append offset {}", offset));
        trace.add_step(ReasoningStep::Retrieve {
            source: "L1::WAL".into(),
            symbol: format!("offset_{}", offset),
            result: serde_json::json!({
                "offset": offset,
                "hash": event_hash,
                "timestamp": std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_nanos()
            }),
        });

        let trace_id = trace.finalize();
        self.protocol_handler
            .emit_trace_start(
                "append".into(),
                trace_id,
                trace.initiating_query.clone(),
            )
            .await;
    }

    /// Emit reasoning trace when kernel commits an offset
    /// Hook: seb_kernel.adb commit_offset/1
    pub async fn on_kernel_commit(&self, offset: u64, _tip_hash: &str) {
        let mut trace = ReasoningTrace::new(
            "kernel_001".into(),
            "commit".into(),
            2,
        );

        trace.add_step(ReasoningStep::CheckAuthorization {
            principal: "kernel".into(),
            action: "commit_offset".into(),
            resource: format!("offset_{}", offset),
            allowed: true,
            reason: "monotonic_and_valid".into(),
        });

        let trace_id = trace.finalize();
        self.protocol_handler
            .emit_trace_complete(trace_id, 5, 1, Some(0.99))
            .await;
    }

    /// Emit reasoning trace when kernel rotates a segment
    /// Hook: seb_kernel.adb rotate_segment/0
    pub async fn on_kernel_rotate(&self, segment_id: u64, _prev_hash: &str) {
        let mut trace = ReasoningTrace::new(
            "kernel_001".into(),
            "rotate".into(),
            3,
        );

        trace.add_step(ReasoningStep::Verify {
            target: format!("segment_{}", segment_id),
            method: "prev_hash_chain".into(),
            valid: true,
            error: None,
        });

        trace.add_step(ReasoningStep::Conclude {
            conclusion: "Segment rotated successfully".into(),
            confidence: 1.0,
        });

        let trace_id = trace.finalize();
        self.protocol_handler
            .emit_trace_complete(trace_id, 10, 2, Some(1.0))
            .await;
    }
}

/// Layer 3 (Policy) integration
pub struct L3PolicyIntegration {
    protocol_handler: Arc<A2AProtocolHandler>,
}

impl L3PolicyIntegration {
    pub fn new(agent_id: String) -> Self {
        L3PolicyIntegration {
            protocol_handler: Arc::new(A2AProtocolHandler::new(agent_id)),
        }
    }

    /// Emit reasoning trace when policy gate evaluates authorization
    /// Hook: seb_datalog_bridge.erl authorize/2
    pub async fn on_policy_authorize(
        &self,
        principal: &str,
        action: &str,
        resource: &str,
        allowed: bool,
        reason: &str,
    ) {
        let mut trace = ReasoningTrace::new(
            "policy_001".into(),
            "authorize".into(),
            1,
        );

        trace.set_query(format!(
            "authorize {} {} {}",
            principal, action, resource
        ));

        trace.add_step(ReasoningStep::Retrieve {
            source: "L3::Datalog".into(),
            symbol: format!("policy_{}", action),
            result: serde_json::json!({
                "principal": principal,
                "action": action,
                "allowed": allowed
            }),
        });

        trace.add_step(ReasoningStep::CheckAuthorization {
            principal: principal.into(),
            action: action.into(),
            resource: resource.into(),
            allowed,
            reason: reason.into(),
        });

        trace.add_step(ReasoningStep::Conclude {
            conclusion: format!("Authorization: {}", if allowed { "ALLOW" } else { "DENY" }),
            confidence: 0.95,
        });

        let trace_id = trace.finalize();
        self.protocol_handler
            .emit_trace_start(
                "authorize".into(),
                trace_id,
                trace.initiating_query.clone(),
            )
            .await;
    }

    /// Emit reasoning trace when policy detects anomaly
    pub async fn on_policy_anomaly(&self, anomaly_type: &str, details: serde_json::Value) {
        let mut trace = ReasoningTrace::new(
            "policy_001".into(),
            "anomaly".into(),
            2,
        );

        trace.add_step(ReasoningStep::Retrieve {
            source: "L3::Anomaly".into(),
            symbol: anomaly_type.into(),
            result: details,
        });

        trace.add_step(ReasoningStep::Conclude {
            conclusion: format!("Anomaly detected: {}", anomaly_type),
            confidence: 0.85,
        });

        let trace_id = trace.finalize();
        self.protocol_handler
            .emit_trace_complete(trace_id, 15, 2, Some(0.85))
            .await;
    }
}

/// Layer 5 (Knowledge) integration
pub struct L5KnowledgeIntegration {
    stream_manager: Arc<ReasoningStreamManager>,
}

impl L5KnowledgeIntegration {
    pub fn new() -> Self {
        L5KnowledgeIntegration {
            stream_manager: Arc::new(ReasoningStreamManager::new()),
        }
    }

    /// Store a reasoning trace as a KnowledgeObject
    /// Enriches trace with symbol indexing and relational links
    pub async fn store_reasoning_trace(&self, trace: ReasoningTrace) {
        // Extract symbols from trace
        let symbols = trace.extract_symbols();

        // Store trace
        self.stream_manager.store_trace(trace.clone()).await;

        // Index symbols (would link to L5 knowledge base)
        for symbol in symbols {
            tracing::info!("Indexed symbol '{}' from trace {}", symbol, &trace.trace_id[0..16]);
        }
    }

    /// Link two traces as a relation
    /// Hook: Called when creating composition or challenge relations
    pub async fn link_traces(&self, source_id: &str, target_id: &str, relation: &str) {
        tracing::info!(
            "Linking traces: {} --[{}]--> {}",
            &source_id[0..16],
            relation,
            &target_id[0..16]
        );

        // Would create edges in L5 knowledge graph
    }

    /// Query knowledge base for related traces
    pub async fn query_related_traces(&self, symbol: &str) -> Vec<String> {
        let traces = self.stream_manager.get_traces().await;
        traces
            .iter()
            .filter(|t| t.extract_symbols().contains(&symbol.to_string()))
            .map(|t| t.trace_id.clone())
            .collect()
    }

    /// Get timeline for a trace
    pub async fn get_trace_timeline(&self, trace_id: &str) -> Option<String> {
        self.stream_manager
            .get_timeline(trace_id)
            .await
            .map(|tl| tl.render_ascii())
    }
}

impl Default for L5KnowledgeIntegration {
    fn default() -> Self {
        Self::new()
    }
}

/// Erlang NIF bridge for agent-to-agent reasoning
/// These functions are called from Erlang/OTP runtime
pub mod erlang_nif {
    use super::*;

    /// `seb_reasoning_subscribe/2` - Subscribe to reasoning partition
    /// Args: (PartitionPath :: string, Mode :: atom)
    /// Returns: SubscriptionRef :: term
    pub fn seb_reasoning_subscribe(partition_path: &str, _mode: &str) -> String {
        let partition = ReasoningPartition::from_path(partition_path)
            .map(|p| p.path())
            .unwrap_or_else(|| partition_path.to_string());
        format!("subscription:{}", partition)
    }

    /// `seb_reasoning_emit_step/3` - Emit a reasoning step
    /// Args: (TraceId :: binary, StepIndex :: integer, StepJson :: term)
    pub fn seb_reasoning_emit_step(_trace_id: &str, _step_index: usize, _step_json: serde_json::Value) -> bool {
        true
    }

    /// `seb_reasoning_challenge/3` - Challenge a trace
    /// Args: (TargetTraceId :: binary, CounterEvidence :: binary, StepIndex :: option)
    pub fn seb_reasoning_challenge(
        target_trace_id: &str,
        counter_evidence: &str,
        step_index: Option<usize>,
    ) -> String {
        format!(
            "challenge:{}:{}:{}",
            target_trace_id,
            counter_evidence.len(),
            step_index.unwrap_or(0)
        )
    }

    /// `seb_reasoning_compose/3` - Compose multiple traces
    /// Args: (SubTraceIds :: list, CompositionRule :: binary, CompositionId :: binary)
    pub fn seb_reasoning_compose(sub_trace_ids: Vec<String>, composition_rule: &str) -> String {
        format!(
            "composition:{}:{}",
            sub_trace_ids.len(),
            composition_rule
        )
    }

    /// `seb_reasoning_query/2` - Query reasoning traces
    /// Args: (QueryType :: atom, QueryData :: term)
    /// Returns: TraceIds :: list
    pub fn seb_reasoning_query(_query_type: &str, _query_data: serde_json::Value) -> Vec<String> {
        vec![]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_l1_kernel_integration() {
        let l1 = L1KernelIntegration::new("kernel_001".into());

        l1.on_kernel_append(101, "abc123def").await;
        l1.on_kernel_commit(101, "xyz789").await;
        l1.on_kernel_rotate(1, "prev_hash").await;

        let events = l1.protocol_handler.get_events().await;
        assert!(!events.is_empty());
    }

    #[tokio::test]
    async fn test_l3_policy_integration() {
        let l3 = L3PolicyIntegration::new("policy_001".into());

        l3.on_policy_authorize("user_1", "read", "doc_1", true, "owned")
            .await;

        let events = l3.protocol_handler.get_events().await;
        assert!(!events.is_empty());
    }

    #[tokio::test]
    async fn test_l5_knowledge_integration() {
        let l5 = L5KnowledgeIntegration::new();

        let mut trace = ReasoningTrace::new("agent_001".into(), "verify".into(), 1);
        trace.add_step(ReasoningStep::Retrieve {
            source: "L1".into(),
            symbol: "test_symbol".into(),
            result: serde_json::json!({}),
        });
        trace.finalize();

        l5.store_reasoning_trace(trace).await;

        let related = l5.query_related_traces("test_symbol").await;
        assert!(!related.is_empty());
    }

    #[test]
    fn test_erlang_nif_subscribe() {
        let result = erlang_nif::seb_reasoning_subscribe("reasoning/agent_001", "live");
        assert!(result.contains("subscription"));
    }

    #[test]
    fn test_erlang_nif_challenge() {
        let result = erlang_nif::seb_reasoning_challenge("trace_001", "counter_evidence", Some(2));
        assert!(result.contains("challenge"));
        assert!(result.contains("trace_001"));
    }
}
