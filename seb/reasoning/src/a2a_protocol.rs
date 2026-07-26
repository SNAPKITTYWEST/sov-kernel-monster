use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

/// Event types for A2A Reasoning protocol over SEB
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Hash)]
#[repr(u16)]
pub enum ReasoningEventType {
    /// Trace has started: agent begins reasoning
    TraceStart = 0x0300,
    /// Single reasoning step emitted
    Step = 0x0301,
    /// Trace has completed
    TraceComplete = 0x0302,
    /// Challenge to a prior trace/step
    Challenge = 0x0303,
    /// Composition of multiple traces
    Composition = 0x0304,
    /// Query for specific reasoning information
    Query = 0x0305,
    /// Response to a query
    Response = 0x0306,
}

impl ReasoningEventType {
    pub fn as_u16(&self) -> u16 {
        *self as u16
    }

    pub fn from_u16(val: u16) -> Option<Self> {
        match val {
            0x0300 => Some(ReasoningEventType::TraceStart),
            0x0301 => Some(ReasoningEventType::Step),
            0x0302 => Some(ReasoningEventType::TraceComplete),
            0x0303 => Some(ReasoningEventType::Challenge),
            0x0304 => Some(ReasoningEventType::Composition),
            0x0305 => Some(ReasoningEventType::Query),
            0x0306 => Some(ReasoningEventType::Response),
            _ => None,
        }
    }
}

/// Partition path for reasoning events
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReasoningPartition {
    /// reasoning/{agent_id} - Personal reasoning trace stream
    AgentTraces(String),
    /// reasoning/challenges - Global challenge stream
    Challenges,
    /// reasoning/compositions - Global composition stream
    Compositions,
    /// reasoning/queries - Query stream
    Queries,
}

impl ReasoningPartition {
    pub fn path(&self) -> String {
        match self {
            ReasoningPartition::AgentTraces(agent_id) => format!("reasoning/{}", agent_id),
            ReasoningPartition::Challenges => "reasoning/challenges".to_string(),
            ReasoningPartition::Compositions => "reasoning/compositions".to_string(),
            ReasoningPartition::Queries => "reasoning/queries".to_string(),
        }
    }

    pub fn from_path(path: &str) -> Option<Self> {
        match path {
            "reasoning/challenges" => Some(ReasoningPartition::Challenges),
            "reasoning/compositions" => Some(ReasoningPartition::Compositions),
            "reasoning/queries" => Some(ReasoningPartition::Queries),
            p if p.starts_with("reasoning/") => {
                let agent_id = p.strip_prefix("reasoning/")?.to_string();
                if !agent_id.is_empty() && agent_id != "challenges" && agent_id != "compositions"
                    && agent_id != "queries"
                {
                    Some(ReasoningPartition::AgentTraces(agent_id))
                } else {
                    None
                }
            }
            _ => None,
        }
    }
}

/// Payload for TRACE_START event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TraceStartPayload {
    pub trace_id: String,
    pub agent_id: String,
    pub competency: String,
    pub query: Option<String>,
}

/// Payload for STEP event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StepPayload {
    pub trace_id: String,
    pub step_index: usize,
    pub step_json: serde_json::Value,
    pub step_hash: String,
}

/// Payload for TRACE_COMPLETE event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TraceCompletePayload {
    pub trace_id: String,
    pub duration_ms: u64,
    pub step_count: usize,
    pub confidence: Option<f64>,
}

/// Payload for CHALLENGE event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChallengePayload {
    pub challenge_trace_id: String,
    pub target_trace_id: String,
    pub target_step_index: Option<usize>,
    pub counter_evidence: String,
}

/// Payload for COMPOSITION event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompositionPayload {
    pub composition_trace_id: String,
    pub sub_trace_ids: Vec<String>,
    pub composition_rule: String,
}

/// Payload for QUERY event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueryPayload {
    pub query_id: String,
    pub agent_id: String,
    pub query_type: String,
    pub query_data: serde_json::Value,
}

/// Payload for RESPONSE event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResponsePayload {
    pub query_id: String,
    pub responding_agent: String,
    pub trace_ids: Vec<String>,
    pub results: Vec<serde_json::Value>,
}

/// A2A Reasoning Event - wrapper for all reasoning event types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct A2AReasoningEvent {
    pub event_type: u16, // ReasoningEventType code
    pub timestamp: DateTime<Utc>,
    pub partition: String,
    pub payload: serde_json::Value,
}

impl A2AReasoningEvent {
    pub fn new(event_type: ReasoningEventType, partition: ReasoningPartition) -> Self {
        A2AReasoningEvent {
            event_type: event_type.as_u16(),
            timestamp: Utc::now(),
            partition: partition.path(),
            payload: serde_json::json!({}),
        }
    }

    pub fn with_trace_start(
        agent_id: String,
        competency: String,
        trace_id: String,
        query: Option<String>,
    ) -> Self {
        let partition = ReasoningPartition::AgentTraces(agent_id.clone());
        let mut event = Self::new(ReasoningEventType::TraceStart, partition);

        let payload = TraceStartPayload {
            trace_id,
            agent_id,
            competency,
            query,
        };

        event.payload = serde_json::to_value(payload).unwrap_or_default();
        event
    }

    pub fn with_step(trace_id: String, step_index: usize, step_json: serde_json::Value) -> Self {
        let step_hash = blake3::hash(
            serde_json::to_string(&step_json)
                .unwrap_or_default()
                .as_bytes(),
        )
        .to_hex()
        .to_string();

        let partition = ReasoningPartition::Queries; // Use queries partition for broadcast
        let mut event = Self::new(ReasoningEventType::Step, partition);

        let payload = StepPayload {
            trace_id,
            step_index,
            step_json,
            step_hash,
        };

        event.payload = serde_json::to_value(payload).unwrap_or_default();
        event
    }

    pub fn with_challenge(
        target_trace_id: String,
        counter_evidence: String,
        target_step_index: Option<usize>,
    ) -> Self {
        let challenge_trace_id = uuid::Uuid::new_v4().to_string();
        let partition = ReasoningPartition::Challenges;
        let mut event = Self::new(ReasoningEventType::Challenge, partition);

        let payload = ChallengePayload {
            challenge_trace_id,
            target_trace_id,
            target_step_index,
            counter_evidence,
        };

        event.payload = serde_json::to_value(payload).unwrap_or_default();
        event
    }

    pub fn with_composition(
        composition_trace_id: String,
        sub_trace_ids: Vec<String>,
        composition_rule: String,
    ) -> Self {
        let partition = ReasoningPartition::Compositions;
        let mut event = Self::new(ReasoningEventType::Composition, partition);

        let payload = CompositionPayload {
            composition_trace_id,
            sub_trace_ids,
            composition_rule,
        };

        event.payload = serde_json::to_value(payload).unwrap_or_default();
        event
    }

    pub fn as_json_line(&self) -> String {
        serde_json::to_string(self).unwrap_or_default()
    }
}

/// A2A Protocol handler for emitting and receiving reasoning events
pub struct A2AProtocolHandler {
    agent_id: String,
    event_log: Arc<tokio::sync::Mutex<Vec<A2AReasoningEvent>>>,
}

impl A2AProtocolHandler {
    pub fn new(agent_id: String) -> Self {
        A2AProtocolHandler {
            agent_id,
            event_log: Arc::new(tokio::sync::Mutex::new(Vec::new())),
        }
    }

    /// Emit a reasoning trace start event
    pub async fn emit_trace_start(
        &self,
        competency: String,
        trace_id: String,
        query: Option<String>,
    ) {
        let event = A2AReasoningEvent::with_trace_start(
            self.agent_id.clone(),
            competency,
            trace_id,
            query,
        );
        let mut log = self.event_log.lock().await;
        log.push(event);
    }

    /// Emit a reasoning step event
    pub async fn emit_step(&self, trace_id: String, step_index: usize, step_json: serde_json::Value) {
        let event = A2AReasoningEvent::with_step(trace_id, step_index, step_json);
        let mut log = self.event_log.lock().await;
        log.push(event);
    }

    /// Emit a trace complete event
    pub async fn emit_trace_complete(
        &self,
        trace_id: String,
        duration_ms: u64,
        step_count: usize,
        confidence: Option<f64>,
    ) {
        let partition = ReasoningPartition::AgentTraces(self.agent_id.clone());
        let mut event = A2AReasoningEvent::new(ReasoningEventType::TraceComplete, partition);

        let payload = TraceCompletePayload {
            trace_id,
            duration_ms,
            step_count,
            confidence,
        };

        event.payload = serde_json::to_value(payload).unwrap_or_default();
        let mut log = self.event_log.lock().await;
        log.push(event);
    }

    /// Emit a challenge event
    pub async fn emit_challenge(
        &self,
        target_trace_id: String,
        counter_evidence: String,
        target_step_index: Option<usize>,
    ) {
        let event =
            A2AReasoningEvent::with_challenge(target_trace_id, counter_evidence, target_step_index);
        let mut log = self.event_log.lock().await;
        log.push(event);
    }

    /// Emit a composition event
    pub async fn emit_composition(
        &self,
        composition_trace_id: String,
        sub_trace_ids: Vec<String>,
        composition_rule: String,
    ) {
        let event = A2AReasoningEvent::with_composition(composition_trace_id, sub_trace_ids, composition_rule);
        let mut log = self.event_log.lock().await;
        log.push(event);
    }

    /// Get all emitted events
    pub async fn get_events(&self) -> Vec<A2AReasoningEvent> {
        let log = self.event_log.lock().await;
        log.clone()
    }

    /// Get events by partition
    pub async fn get_events_by_partition(&self, partition: &ReasoningPartition) -> Vec<A2AReasoningEvent> {
        let log = self.event_log.lock().await;
        let partition_path = partition.path();
        log.iter()
            .filter(|e| e.partition == partition_path)
            .cloned()
            .collect()
    }

    /// Get events by type
    pub async fn get_events_by_type(&self, event_type: ReasoningEventType) -> Vec<A2AReasoningEvent> {
        let log = self.event_log.lock().await;
        let type_code = event_type.as_u16();
        log.iter()
            .filter(|e| e.event_type == type_code)
            .cloned()
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_event_type_codes() {
        assert_eq!(ReasoningEventType::TraceStart.as_u16(), 0x0300);
        assert_eq!(ReasoningEventType::Challenge.as_u16(), 0x0303);
        assert_eq!(ReasoningEventType::from_u16(0x0300), Some(ReasoningEventType::TraceStart));
        assert_eq!(ReasoningEventType::from_u16(0xFFFF), None);
    }

    #[test]
    fn test_partition_paths() {
        let p1 = ReasoningPartition::AgentTraces("agent_001".into());
        assert_eq!(p1.path(), "reasoning/agent_001");

        let p2 = ReasoningPartition::Challenges;
        assert_eq!(p2.path(), "reasoning/challenges");

        assert_eq!(ReasoningPartition::from_path("reasoning/agent_001"), Some(p1));
        assert_eq!(ReasoningPartition::from_path("reasoning/challenges"), Some(p2));
    }

    #[tokio::test]
    async fn test_protocol_handler() {
        let handler = A2AProtocolHandler::new("agent_001".into());

        handler
            .emit_trace_start("verify".into(), "trace_001".into(), None)
            .await;

        let events = handler.get_events().await;
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].event_type, 0x0300);
    }

    #[test]
    fn test_event_creation() {
        let event = A2AReasoningEvent::with_trace_start(
            "agent_001".into(),
            "verify".into(),
            "trace_001".into(),
            Some("query".into()),
        );

        assert_eq!(event.event_type, 0x0300);
        assert!(event.partition.contains("agent_001"));
    }
}
