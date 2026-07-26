use anyhow::Result;
use chrono::{DateTime, Utc};
use dashmap::DashMap;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::mpsc;
use tracing::{debug, info, warn};

use crate::audit_log::AuditLog;
use crate::commit_gateway::CommitGateway;

/// A change pending human review
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PendingChange {
    pub id: String,
    pub description: String,
    pub evidence: String,
    pub agent_name: String,
    pub created_at: DateTime<Utc>,
    pub files: Vec<String>,
    pub diff: String,
}

/// Status of a change in the review pipeline
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ChangeStatus {
    /// Awaiting human review
    Pending,
    /// Human is actively reviewing
    UnderReview,
    /// Change has been approved
    Approved,
    /// Change has been rejected
    Rejected,
    /// Approved and committed
    Committed,
}

/// Change with metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
struct ChangeRecord {
    change: PendingChange,
    status: ChangeStatus,
    reviewed_by: Option<String>,
    review_timestamp: Option<DateTime<Utc>>,
    rejection_reason: Option<String>,
    commit_hash: Option<String>,
}

/// Human review pipeline queue
pub struct ReviewQueue {
    rx: mpsc::Receiver<PendingChange>,
    repo_path: PathBuf,
    audit_log: PathBuf,
    max_pending: usize,
    /// In-flight changes indexed by ID
    changes: Arc<DashMap<String, ChangeRecord>>,
    /// Order of pending changes (for FIFO processing)
    pending_queue: Arc<Vec<String>>,
}

impl ReviewQueue {
    /// Create a new review queue
    pub fn new(
        rx: mpsc::Receiver<PendingChange>,
        repo_path: PathBuf,
        audit_log: PathBuf,
        max_pending: usize,
    ) -> Result<Self> {
        info!(
            "📋 ReviewQueue initialized (max_pending: {}, repo: {:?})",
            max_pending, repo_path
        );

        Ok(ReviewQueue {
            rx,
            repo_path,
            audit_log,
            max_pending,
            changes: Arc::new(DashMap::new()),
            pending_queue: Arc::new(Vec::new()),
        })
    }

    /// Process changes from the queue
    pub async fn process_queue(
        &mut self,
        gateway: CommitGateway,
        audit_log: AuditLog,
    ) -> Result<()> {
        info!("🔄 Review queue processor started");

        loop {
            tokio::select! {
                Some(change) = self.rx.recv() => {
                    self.handle_incoming_change(change, &gateway, &audit_log).await?;
                }
                _ = tokio::time::sleep(tokio::time::Duration::from_secs(5)) => {
                    self.check_pending_reviews(&audit_log).await?;
                }
            }
        }
    }

    /// Handle a newly incoming change
    async fn handle_incoming_change(
        &self,
        change: PendingChange,
        _gateway: &CommitGateway,
        audit_log: &AuditLog,
    ) -> Result<()> {
        let change_id = change.id.clone();
        let agent = change.agent_name.clone();

        info!(
            "📥 New change received (id: {}, agent: {}, files: {})",
            change_id,
            agent,
            change.files.len()
        );

        // Check queue capacity
        if self.changes.len() >= self.max_pending {
            warn!(
                "⚠️  Review queue full ({}). Rejecting new change: {}",
                self.max_pending, change_id
            );
            audit_log
                .log_rejection(&change_id, "Queue capacity exceeded", &agent)
                .await?;
            return Ok(());
        }

        // Format the change for human review
        let review_request = self.format_review_request(&change);

        // Store in queue
        let record = ChangeRecord {
            change: change.clone(),
            status: ChangeStatus::Pending,
            reviewed_by: None,
            review_timestamp: None,
            rejection_reason: None,
            commit_hash: None,
        };
        self.changes.insert(change_id.clone(), record);

        // Log to audit trail
        audit_log.log_submitted(&change).await?;

        // Display review prompt
        println!("{}", review_request);
        println!();
        println!("🤔 Awaiting human review. Enter 'approve <id>' or 'reject <id> <reason>'");
        println!();

        Ok(())
    }

    /// Format a change for human review
    fn format_review_request(&self, change: &PendingChange) -> String {
        format!(
            r#"
┌─────────────────────────────────────────────────────────────┐
│                   HUMAN REVIEW REQUEST                       │
├─────────────────────────────────────────────────────────────┤
│ ID:       {}
│ Agent:    {}
│ Time:     {}
│ Status:   ⏳ AWAITING REVIEW
├─────────────────────────────────────────────────────────────┤
│ DESCRIPTION:
│ {}
├─────────────────────────────────────────────────────────────┤
│ EVIDENCE:
│ {}
├─────────────────────────────────────────────────────────────┤
│ FILES MODIFIED: {}
├─────────────────────────────────────────────────────────────┤
│ DECISION:
│   ✅ approve {}  - Approve and commit
│   ❌ reject {}   - Reject with reason
│   📝 inspect    - Show full diff
└─────────────────────────────────────────────────────────────┘
"#,
            change.id,
            change.agent_name,
            change.created_at.format("%Y-%m-%d %H:%M:%S UTC"),
            self.indent_text(&change.description, 2),
            self.indent_text(&change.evidence, 2),
            change.files.len(),
            change.id,
            change.id,
        )
    }

    /// Helper to indent text for display
    fn indent_text(&self, text: &str, spaces: usize) -> String {
        let indent = " ".repeat(spaces);
        text.lines()
            .map(|line| format!("{}{}", indent, line))
            .collect::<Vec<_>>()
            .join("\n")
    }

    /// Check for pending reviews (timeout, ready for commit)
    async fn check_pending_reviews(&self, _audit_log: &AuditLog) -> Result<()> {
        debug!("🔍 Checking pending reviews...");

        let now = Utc::now();
        let timeout_secs = 3600; // 1 hour

        for entry in self.changes.iter() {
            let record = entry.value();

            if record.status == ChangeStatus::Approved {
                let elapsed = (now - record.review_timestamp.unwrap_or(now)).num_seconds();

                if elapsed > 0 {
                    debug!(
                        "✅ Change {} approved by {}, ready for commit",
                        entry.key(),
                        record.reviewed_by.as_ref().unwrap_or(&"unknown".to_string())
                    );
                }
            }

            // Warn if pending too long
            if record.status == ChangeStatus::Pending {
                let elapsed = (now - record.change.created_at).num_seconds();

                if elapsed > timeout_secs {
                    warn!(
                        "⏰ Change {} pending review for {}s (timeout: {}s)",
                        entry.key(),
                        elapsed,
                        timeout_secs
                    );
                }
            }
        }

        Ok(())
    }

    /// Approve a change
    pub async fn approve_change(
        &self,
        change_id: &str,
        reviewer: &str,
        audit_log: &AuditLog,
    ) -> Result<()> {
        info!("✅ Approving change: {} (reviewer: {})", change_id, reviewer);

        if let Some(mut entry) = self.changes.get_mut(change_id) {
            entry.status = ChangeStatus::Approved;
            entry.reviewed_by = Some(reviewer.to_string());
            entry.review_timestamp = Some(Utc::now());

            audit_log
                .log_approval(change_id, reviewer, &entry.change.description)
                .await?;

            info!("✅ Change {} approved and ready for commit", change_id);
        } else {
            return Err(anyhow::anyhow!("Change not found: {}", change_id));
        }

        Ok(())
    }

    /// Reject a change
    pub async fn reject_change(
        &self,
        change_id: &str,
        reviewer: &str,
        reason: &str,
        audit_log: &AuditLog,
    ) -> Result<()> {
        info!(
            "❌ Rejecting change: {} (reviewer: {}, reason: {})",
            change_id, reviewer, reason
        );

        if let Some(mut entry) = self.changes.get_mut(change_id) {
            entry.status = ChangeStatus::Rejected;
            entry.reviewed_by = Some(reviewer.to_string());
            entry.review_timestamp = Some(Utc::now());
            entry.rejection_reason = Some(reason.to_string());

            audit_log
                .log_rejection(change_id, reason, reviewer)
                .await?;

            info!("❌ Change {} rejected. Reason: {}", change_id, reason);
        } else {
            return Err(anyhow::anyhow!("Change not found: {}", change_id));
        }

        Ok(())
    }

    /// Mark change as committed
    pub async fn mark_committed(
        &self,
        change_id: &str,
        commit_hash: &str,
        audit_log: &AuditLog,
    ) -> Result<()> {
        info!("📝 Marking change {} as committed: {}", change_id, commit_hash);

        if let Some(mut entry) = self.changes.get_mut(change_id) {
            entry.status = ChangeStatus::Committed;
            entry.commit_hash = Some(commit_hash.to_string());

            audit_log
                .log_commit(change_id, commit_hash, entry.reviewed_by.as_deref().unwrap_or("unknown"))
                .await?;

            info!("✅ Change {} committed with hash: {}", change_id, commit_hash);
        } else {
            return Err(anyhow::anyhow!("Change not found: {}", change_id));
        }

        Ok(())
    }

    /// Get current status
    pub fn status(&self) -> QueueStatus {
        let mut pending = 0;
        let mut approved = 0;
        let mut rejected = 0;
        let mut committed = 0;

        for entry in self.changes.iter() {
            match entry.value().status {
                ChangeStatus::Pending | ChangeStatus::UnderReview => pending += 1,
                ChangeStatus::Approved => approved += 1,
                ChangeStatus::Rejected => rejected += 1,
                ChangeStatus::Committed => committed += 1,
            }
        }

        QueueStatus {
            total: self.changes.len(),
            pending,
            approved,
            rejected,
            committed,
            capacity: self.max_pending,
        }
    }
}

/// Status snapshot of the review queue
#[derive(Debug, Serialize, Deserialize)]
pub struct QueueStatus {
    pub total: usize,
    pub pending: usize,
    pub approved: usize,
    pub rejected: usize,
    pub committed: usize,
    pub capacity: usize,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_review_request() {
        let queue = ReviewQueue::new(
            mpsc::channel(100).1,
            PathBuf::from("."),
            PathBuf::from("audit.json"),
            100,
        )
        .unwrap();

        let change = PendingChange {
            id: "test-123".to_string(),
            description: "Add new feature".to_string(),
            evidence: "https://example.com/evidence".to_string(),
            agent_name: "test-agent".to_string(),
            created_at: Utc::now(),
            files: vec!["src/main.rs".to_string()],
            diff: "some diff".to_string(),
        };

        let formatted = queue.format_review_request(&change);
        assert!(formatted.contains("test-123"));
        assert!(formatted.contains("Add new feature"));
    }

    #[test]
    fn test_indent_text() {
        let queue = ReviewQueue::new(
            mpsc::channel(100).1,
            PathBuf::from("."),
            PathBuf::from("audit.json"),
            100,
        )
        .unwrap();

        let text = "line1\nline2";
        let indented = queue.indent_text(text, 2);
        assert!(indented.starts_with("  line1"));
    }
}
