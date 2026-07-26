use blake3;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Reasoning step type in the proof chain.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type")]
pub enum ReasoningStep {
    /// Retrieve information from a source (L1 kernel, L3 policy, L5 knowledge)
    Retrieve {
        source: String,
        symbol: String,
        result: serde_json::Value,
    },
    /// Verify a proof or signature
    Verify {
        target: String,
        method: String,
        valid: bool,
        error: Option<String>,
    },
    /// Apply a logical rule or inference
    ApplyRule {
        rule_id: String,
        premises: Vec<String>,
        conclusion: String,
    },
    /// Check authorization policy
    CheckAuthorization {
        principal: String,
        action: String,
        resource: String,
        allowed: bool,
        reason: String,
    },
    /// Challenge a prior conclusion with counter-evidence
    Challenge {
        target_trace_id: String,
        target_step_index: usize,
        counter_evidence: String,
    },
    /// Rebuttal to a challenge
    Rebuttal {
        challenge_trace_id: String,
        response: String,
    },
    /// Conclude reasoning with final result
    Conclude {
        conclusion: String,
        confidence: f64, // 0.0 to 1.0
    },
    /// Compose multiple traces into a higher-order reasoning
    Compose {
        sub_trace_ids: Vec<String>,
        composition_rule: String,
    },
}

impl ReasoningStep {
    /// Return a short human-readable description
    pub fn description(&self) -> String {
        match self {
            ReasoningStep::Retrieve { symbol, .. } => format!("Retrieve({})", symbol),
            ReasoningStep::Verify { method, .. } => format!("Verify({})", method),
            ReasoningStep::ApplyRule { rule_id, .. } => format!("ApplyRule({})", rule_id),
            ReasoningStep::CheckAuthorization { action, .. } => format!("CheckAuth({})", action),
            ReasoningStep::Challenge { target_trace_id, .. } => {
                format!("Challenge({})", &target_trace_id[0..8])
            }
            ReasoningStep::Rebuttal { .. } => "Rebuttal".to_string(),
            ReasoningStep::Conclude { confidence, .. } => {
                format!("Conclude(conf={})", (confidence * 100.0) as i32)
            }
            ReasoningStep::Compose { .. } => "Compose".to_string(),
        }
    }
}

/// A single step in a reasoning trace with content addressing.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TracedStep {
    /// Sequential index in parent trace
    pub index: usize,
    /// Timestamp when step was recorded
    pub timestamp: DateTime<Utc>,
    /// The reasoning step payload
    pub step: ReasoningStep,
    /// Blake3 hash of step content (for verification)
    pub step_hash: String,
}

/// Parent trace relationship
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind")]
pub enum TraceRelation {
    /// This trace extends/continues another trace
    Extends { parent_trace_id: String },
    /// This trace challenges (disputes) another trace
    Challenges { parent_trace_id: String },
    /// This trace rebuts a challenge
    Rebuts { challenge_trace_id: String },
    /// This trace composes multiple traces
    Composes { sub_trace_ids: Vec<String> },
}

/// A reasoning trace: immutable, content-addressed, queryable sequence of reasoning steps.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReasoningTrace {
    /// Unique identifier: SHA256(JSON without trace_id field) = hex-encoded
    #[serde(skip)]
    pub trace_id: String,

    /// Agent that produced this trace
    pub agent_id: String,
    /// Competency/role context for this reasoning
    pub competency: String,

    /// Sequence of reasoning steps
    pub steps: Vec<TracedStep>,

    /// Optional relationship to parent traces
    pub parent_relations: Vec<TraceRelation>,

    /// Metadata: query that initiated this trace (if any)
    pub initiating_query: Option<String>,

    /// Metadata: reasoning mode
    #[serde(default)]
    pub mode: String, // "live", "replay", "summary"

    /// Total duration in milliseconds
    pub duration_ms: u64,

    /// Timestamp when trace was created
    pub created_at: DateTime<Utc>,

    /// Ed25519 signature over the entire trace (without this field)
    pub signature: Option<Vec<u8>>,

    /// Sequence number for ordering traces from same agent
    pub sequence_no: u64,
}

impl ReasoningTrace {
    /// Create a new empty reasoning trace
    pub fn new(agent_id: String, competency: String, sequence_no: u64) -> Self {
        ReasoningTrace {
            trace_id: String::new(), // Will be computed on finalize
            agent_id,
            competency,
            steps: Vec::new(),
            parent_relations: Vec::new(),
            initiating_query: None,
            mode: "live".to_string(),
            duration_ms: 0,
            created_at: Utc::now(),
            signature: None,
            sequence_no,
        }
    }

    /// Add a reasoning step
    pub fn add_step(&mut self, step: ReasoningStep) {
        let index = self.steps.len();
        let timestamp = Utc::now();
        let step_json = serde_json::to_string(&step).unwrap_or_default();
        let step_hash = blake3::hash(step_json.as_bytes()).to_hex().to_string();

        self.steps.push(TracedStep {
            index,
            timestamp,
            step,
            step_hash,
        });
    }

    /// Add a parent trace relationship
    pub fn add_parent(&mut self, relation: TraceRelation) {
        self.parent_relations.push(relation);
    }

    /// Set the initiating query
    pub fn set_query(&mut self, query: String) {
        self.initiating_query = Some(query);
    }

    /// Set the reasoning mode
    pub fn set_mode(&mut self, mode: String) {
        self.mode = mode;
    }

    /// Compute and finalize the trace_id (content addressing).
    /// Trace ID = SHA256(JSON without trace_id field)
    pub fn finalize(&mut self) -> String {
        // Temporarily clear fields that shouldn't be part of hash
        let _old_trace_id = self.trace_id.clone();
        let old_signature = self.signature.clone();

        self.trace_id = String::new();
        self.signature = None;

        let json_str = serde_json::to_string(&self).unwrap_or_default();
        self.trace_id = blake3::hash(json_str.as_bytes()).to_hex().to_string();

        // Restore signature if needed (but not for subsequent finalize calls)
        self.signature = old_signature;

        self.trace_id.clone()
    }

    /// Sign the trace with an Ed25519 key (placeholder - full implementation with actual signing)
    pub fn sign(&mut self, _key_bytes: &[u8; 32]) {
        self.signature = None; // Clear before computing hash
        let trace_id = self.finalize();

        // Blake3 hash of trace_id as placeholder signature
        let sig_hash = blake3::hash(trace_id.as_bytes()).to_hex().to_string();
        self.signature = Some(sig_hash.as_bytes().to_vec());
    }

    /// Verify the trace signature (placeholder - simplified verification)
    pub fn verify(&self, _key_bytes: &[u8; 32]) -> bool {
        if self.signature.is_none() {
            return false;
        }

        // Placeholder verification: just check signature exists and is right length
        self.signature
            .as_ref()
            .map(|s| s.len() > 0)
            .unwrap_or(false)
    }

    /// Check for cycles in parent relations
    pub fn has_cycles(&self, all_traces: &[ReasoningTrace]) -> bool {
        self._has_cycles_internal(&self.trace_id, all_traces, &mut std::collections::HashSet::new())
    }

    fn _has_cycles_internal(
        &self,
        current_id: &str,
        all_traces: &[ReasoningTrace],
        visited: &mut std::collections::HashSet<String>,
    ) -> bool {
        if visited.contains(current_id) {
            return true; // Cycle detected
        }
        visited.insert(current_id.to_string());

        // Find the current trace
        let current = match all_traces.iter().find(|t| t.trace_id == current_id) {
            Some(t) => t,
            None => return false,
        };

        // Check all parent relations
        for relation in &current.parent_relations {
            let parent_id = match relation {
                TraceRelation::Extends { parent_trace_id } => parent_trace_id,
                TraceRelation::Challenges { parent_trace_id } => parent_trace_id,
                TraceRelation::Rebuts { challenge_trace_id } => challenge_trace_id,
                TraceRelation::Composes { sub_trace_ids } => {
                    // Check all sub-traces
                    for sub_id in sub_trace_ids {
                        if self._has_cycles_internal(sub_id, all_traces, visited) {
                            return true;
                        }
                    }
                    continue;
                }
            };

            if self._has_cycles_internal(parent_id, all_traces, visited) {
                return true;
            }
        }

        false
    }

    /// Convert trace to S-Expr representation
    pub fn to_s_expr(&self) -> String {
        let mut parts = vec![
            format!("(trace-id \"{}\")", self.trace_id),
            format!("(agent \"{}\")", self.agent_id),
            format!("(competency \"{}\")", self.competency),
        ];

        for step in &self.steps {
            parts.push(format!(
                "(step {} \"{}\" {})",
                step.index,
                step.step.description(),
                step.step_hash
            ));
        }

        format!("(reasoning {})", parts.join(" "))
    }

    /// Convert trace to JSON-LD representation
    pub fn to_json_ld(&self) -> serde_json::Value {
        serde_json::json!({
            "@context": "https://www.w3.org/ns/activitystreams",
            "@id": format!("trace:{}", self.trace_id),
            "@type": "ReasoningTrace",
            "agent": self.agent_id,
            "competency": self.competency,
            "steps": self.steps.iter().map(|s| {
                serde_json::json!({
                    "@type": "ReasoningStep",
                    "index": s.index,
                    "timestamp": s.timestamp.to_rfc3339(),
                    "description": s.step.description(),
                    "hash": s.step_hash,
                })
            }).collect::<Vec<_>>(),
            "duration": format!("PT{}MS", self.duration_ms),
            "created": self.created_at.to_rfc3339(),
        })
    }

    /// Get all symbols mentioned in this trace (for indexing)
    pub fn extract_symbols(&self) -> Vec<String> {
        let mut symbols = Vec::new();

        for step in &self.steps {
            match &step.step {
                ReasoningStep::Retrieve { symbol, .. } => symbols.push(symbol.clone()),
                ReasoningStep::CheckAuthorization { principal, action, resource, .. } => {
                    symbols.push(principal.clone());
                    symbols.push(action.clone());
                    symbols.push(resource.clone());
                }
                _ => {}
            }
        }

        symbols.sort();
        symbols.dedup();
        symbols
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_trace_creation() {
        let mut trace = ReasoningTrace::new("agent_001".into(), "verify".into(), 1);
        trace.add_step(ReasoningStep::Retrieve {
            source: "L1".into(),
            symbol: "offset_101".into(),
            result: serde_json::json!({"value": 42}),
        });

        assert_eq!(trace.steps.len(), 1);
    }

    #[test]
    fn test_trace_id_generation() {
        let mut trace = ReasoningTrace::new("agent_001".into(), "verify".into(), 1);
        trace.add_step(ReasoningStep::Retrieve {
            source: "L1".into(),
            symbol: "test".into(),
            result: serde_json::json!({}),
        });

        let id1 = trace.finalize();
        assert!(!id1.is_empty());
        assert_eq!(id1.len(), 64); // blake3 hex = 64 chars

        // Finalize again should give same ID
        let id2 = trace.finalize();
        assert_eq!(id1, id2);
    }

    #[test]
    fn test_cycle_detection() {
        let mut t1 = ReasoningTrace::new("agent_001".into(), "verify".into(), 1);
        let mut t2 = ReasoningTrace::new("agent_002".into(), "verify".into(), 1);

        t1.finalize();
        t2.finalize();

        // t1 extends t2, t2 extends t1 (cycle)
        t1.add_parent(TraceRelation::Extends {
            parent_trace_id: t2.trace_id.clone(),
        });
        t2.add_parent(TraceRelation::Extends {
            parent_trace_id: t1.trace_id.clone(),
        });

        assert!(t1.has_cycles(&[t1.clone(), t2.clone()]));
    }

    #[test]
    fn test_symbol_extraction() {
        let mut trace = ReasoningTrace::new("agent_001".into(), "verify".into(), 1);
        trace.add_step(ReasoningStep::Retrieve {
            source: "L1".into(),
            symbol: "symbol_a".into(),
            result: serde_json::json!({}),
        });
        trace.add_step(ReasoningStep::CheckAuthorization {
            principal: "user_1".into(),
            action: "read".into(),
            resource: "doc_1".into(),
            allowed: true,
            reason: "owned".into(),
        });

        let symbols = trace.extract_symbols();
        assert!(symbols.contains(&"symbol_a".to_string()));
        assert!(symbols.contains(&"user_1".to_string()));
        assert!(symbols.contains(&"read".to_string()));
    }
}
