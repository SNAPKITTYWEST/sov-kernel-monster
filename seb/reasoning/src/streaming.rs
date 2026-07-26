use crate::a2a_protocol::{A2AReasoningEvent, ReasoningPartition};
use crate::trace::ReasoningTrace;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

/// Streaming mode for reasoning trace subscription
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StreamingMode {
    /// Stream events as they happen
    Live,
    /// Replay recorded events
    Replay,
    /// Summarized view (headers only)
    Summary,
}

/// WebSocket subscription to a reasoning partition
#[derive(Debug, Clone)]
pub struct ReasoningSubscription {
    pub partition: String,
    pub mode: StreamingMode,
    pub agent_id: Option<String>,
    pub created_at: DateTime<Utc>,
}

/// Timeline entry for trace visualization
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimelineEntry {
    pub step_index: usize,
    pub timestamp: DateTime<Utc>,
    pub description: String,
    pub duration_ms: u64,
}

/// Mermaid sequence diagram for reasoning traces
pub struct MermaidSequenceDiagram {
    pub title: String,
    pub actors: Vec<String>,
    pub interactions: Vec<String>,
}

impl MermaidSequenceDiagram {
    pub fn new(title: String) -> Self {
        MermaidSequenceDiagram {
            title,
            actors: Vec::new(),
            interactions: Vec::new(),
        }
    }

    pub fn add_actor(&mut self, actor: String) {
        if !self.actors.contains(&actor) {
            self.actors.push(actor);
        }
    }

    pub fn add_interaction(&mut self, from: &str, to: &str, label: &str) {
        self.interactions.push(format!("{}->>{}:{}", from, to, label));
    }

    pub fn render(&self) -> String {
        let mut diagram = format!("sequenceDiagram\n    title {}\n", self.title);

        for actor in &self.actors {
            diagram.push_str(&format!("    participant {}\n", actor));
        }
        diagram.push('\n');

        for interaction in &self.interactions {
            diagram.push_str(&format!("    {}\n", interaction));
        }

        diagram
    }
}

/// Generate a Mermaid sequence diagram from multiple reasoning traces
pub fn generate_sequence_diagram(traces: &[ReasoningTrace]) -> MermaidSequenceDiagram {
    let mut diagram = MermaidSequenceDiagram::new("Multi-Agent Reasoning".to_string());

    for trace in traces {
        diagram.add_actor(trace.agent_id.clone());
    }

    // Add interactions based on trace order and relationships
    for (i, trace) in traces.iter().enumerate() {
        if i > 0 {
            let prev = &traces[i - 1];
            diagram.add_interaction(
                &prev.agent_id,
                &trace.agent_id,
                &format!("reasoning({})", trace.competency),
            );
        }
    }

    diagram
}

/// Timeline visualization for a reasoning trace
pub struct TraceTimeline {
    pub trace_id: String,
    pub entries: Vec<TimelineEntry>,
}

impl TraceTimeline {
    pub fn from_trace(trace: &ReasoningTrace) -> Self {
        let mut entries = Vec::new();
        let mut prev_time = trace.created_at;

        for (i, step) in trace.steps.iter().enumerate() {
            let duration_ms = (step.timestamp - prev_time)
                .num_milliseconds()
                .max(0) as u64;

            entries.push(TimelineEntry {
                step_index: i,
                timestamp: step.timestamp,
                description: step.step.description(),
                duration_ms,
            });

            prev_time = step.timestamp;
        }

        TraceTimeline {
            trace_id: trace.trace_id.clone(),
            entries,
        }
    }

    /// Render timeline as ASCII chart
    pub fn render_ascii(&self) -> String {
        let trace_id_short = if self.trace_id.len() >= 16 {
            &self.trace_id[0..16]
        } else {
            &self.trace_id
        };
        let mut output = format!("Trace: {}\n", trace_id_short);
        output.push_str("─────────────────────────────\n");

        let max_duration = self.entries.iter().map(|e| e.duration_ms).max().unwrap_or(1);

        for entry in &self.entries {
            let bar_width = if max_duration > 0 {
                ((entry.duration_ms as f64 / max_duration as f64) * 40.0) as usize
            } else {
                1
            };

            output.push_str(&format!(
                "[{:02}] {:50} {} ms {}ms\n",
                entry.step_index,
                &entry.description,
                "█".repeat(bar_width),
                entry.duration_ms
            ));
        }

        output
    }
}

/// Stream manager for reasoning events
pub struct ReasoningStreamManager {
    subscriptions: Arc<RwLock<Vec<ReasoningSubscription>>>,
    event_buffer: Arc<RwLock<HashMap<String, Vec<A2AReasoningEvent>>>>, // partition -> events
    traces: Arc<RwLock<HashMap<String, ReasoningTrace>>>, // trace_id -> trace
}

impl ReasoningStreamManager {
    pub fn new() -> Self {
        ReasoningStreamManager {
            subscriptions: Arc::new(RwLock::new(Vec::new())),
            event_buffer: Arc::new(RwLock::new(HashMap::new())),
            traces: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Subscribe to a partition in live mode
    pub async fn subscribe_live(&self, partition: String) -> ReasoningSubscription {
        let agent_id = ReasoningPartition::from_path(&partition)
            .and_then(|p| match p {
                ReasoningPartition::AgentTraces(id) => Some(id),
                _ => None,
            });

        let sub = ReasoningSubscription {
            partition: partition.clone(),
            mode: StreamingMode::Live,
            agent_id,
            created_at: Utc::now(),
        };

        let mut subs = self.subscriptions.write().await;
        subs.push(sub.clone());
        sub
    }

    /// Add an event to the stream
    pub async fn emit_event(&self, event: A2AReasoningEvent) {
        let mut buffer = self.event_buffer.write().await;
        buffer
            .entry(event.partition.clone())
            .or_insert_with(Vec::new)
            .push(event);
    }

    /// Store a trace for later retrieval
    pub async fn store_trace(&self, trace: ReasoningTrace) {
        let mut traces = self.traces.write().await;
        traces.insert(trace.trace_id.clone(), trace);
    }

    /// Get all events for a partition
    pub async fn get_partition_events(&self, partition: &str) -> Vec<A2AReasoningEvent> {
        let buffer = self.event_buffer.read().await;
        buffer
            .get(partition)
            .cloned()
            .unwrap_or_default()
    }

    /// Get all traces
    pub async fn get_traces(&self) -> Vec<ReasoningTrace> {
        let traces = self.traces.read().await;
        traces.values().cloned().collect()
    }

    /// Get a specific trace
    pub async fn get_trace(&self, trace_id: &str) -> Option<ReasoningTrace> {
        let traces = self.traces.read().await;
        traces.get(trace_id).cloned()
    }

    /// Generate timeline for a trace
    pub async fn get_timeline(&self, trace_id: &str) -> Option<TraceTimeline> {
        let trace = self.get_trace(trace_id).await?;
        Some(TraceTimeline::from_trace(&trace))
    }

    /// Get all subscriptions
    pub async fn get_subscriptions(&self) -> Vec<ReasoningSubscription> {
        let subs = self.subscriptions.read().await;
        subs.clone()
    }

    /// Generate Mermaid diagrams for all traces
    pub async fn generate_diagrams(&self) -> Vec<MermaidSequenceDiagram> {
        let traces = self.get_traces().await;

        // Group by competency
        let mut by_competency: HashMap<String, Vec<ReasoningTrace>> = HashMap::new();
        for trace in traces {
            by_competency
                .entry(trace.competency.clone())
                .or_insert_with(Vec::new)
                .push(trace);
        }

        by_competency
            .into_iter()
            .map(|(_competency, traces)| generate_sequence_diagram(&traces))
            .collect()
    }

    /// Get summary statistics
    pub async fn get_summary(&self) -> HashMap<String, serde_json::Value> {
        let traces = self.get_traces().await;
        let buffer = self.event_buffer.read().await;

        let mut summary = HashMap::new();

        summary.insert(
            "total_traces".to_string(),
            serde_json::json!(traces.len()),
        );

        summary.insert(
            "total_events".to_string(),
            serde_json::json!(buffer.values().map(|v| v.len()).sum::<usize>()),
        );

        let total_steps = traces.iter().map(|t| t.steps.len()).sum::<usize>();
        summary.insert(
            "total_steps".to_string(),
            serde_json::json!(total_steps),
        );

        let agents: std::collections::HashSet<_> = traces.iter().map(|t| t.agent_id.clone()).collect();
        summary.insert(
            "unique_agents".to_string(),
            serde_json::json!(agents.len()),
        );

        let competencies: std::collections::HashSet<_> = traces.iter().map(|t| t.competency.clone()).collect();
        summary.insert(
            "competencies".to_string(),
            serde_json::json!(Vec::from_iter(competencies)),
        );

        summary
    }
}

impl Default for ReasoningStreamManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::trace::ReasoningStep;

    #[test]
    fn test_mermaid_diagram_generation() {
        let mut t1 = ReasoningTrace::new("kernel_001".into(), "verify".into(), 1);
        t1.finalize();

        let mut t2 = ReasoningTrace::new("policy_001".into(), "authorize".into(), 1);
        t2.add_parent(crate::trace::TraceRelation::Extends {
            parent_trace_id: t1.trace_id.clone(),
        });
        t2.finalize();

        let diagram = generate_sequence_diagram(&[t1, t2]);
        let rendered = diagram.render();

        assert!(rendered.contains("sequenceDiagram"));
        assert!(rendered.contains("kernel_001"));
        assert!(rendered.contains("policy_001"));
    }

    #[test]
    fn test_timeline_rendering() {
        let mut trace = ReasoningTrace::new("agent_001".into(), "verify".into(), 1);
        trace.add_step(ReasoningStep::Retrieve {
            source: "L1".into(),
            symbol: "test".into(),
            result: serde_json::json!({}),
        });
        trace.add_step(ReasoningStep::Verify {
            target: "sig".into(),
            method: "ed25519".into(),
            valid: true,
            error: None,
        });

        let timeline = TraceTimeline::from_trace(&trace);
        let ascii = timeline.render_ascii();

        assert!(ascii.contains("Trace:"));
        assert!(ascii.contains("Retrieve"));
        assert!(ascii.contains("Verify"));
    }

    #[tokio::test]
    async fn test_stream_manager() {
        let manager = ReasoningStreamManager::new();

        let sub = manager.subscribe_live("reasoning/agent_001".into()).await;
        assert_eq!(sub.partition, "reasoning/agent_001");

        let subs = manager.get_subscriptions().await;
        assert_eq!(subs.len(), 1);
    }

    #[tokio::test]
    async fn test_emit_and_retrieve_events() {
        let manager = ReasoningStreamManager::new();

        let event =
            A2AReasoningEvent::with_trace_start("agent_001".into(), "verify".into(), "trace_001".into(), None);
        manager.emit_event(event.clone()).await;

        let events = manager.get_partition_events(&event.partition).await;
        assert_eq!(events.len(), 1);
    }

    #[tokio::test]
    async fn test_store_and_retrieve_trace() {
        let manager = ReasoningStreamManager::new();

        let mut trace = ReasoningTrace::new("agent_001".into(), "verify".into(), 1);
        trace.finalize();
        let trace_id = trace.trace_id.clone();

        manager.store_trace(trace).await;

        let retrieved = manager.get_trace(&trace_id).await;
        assert!(retrieved.is_some());
    }
}
