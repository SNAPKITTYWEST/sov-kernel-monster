use anyhow::Result;
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::fs::OpenOptions;
use std::io::Write;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing::{debug, info};

use crate::review_queue::PendingChange;

/// Audit log entry for a review decision
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditEntry {
    pub timestamp: String,
    pub event_type: String,
    pub change_id: String,
    pub agent_name: String,
    pub reviewer: Option<String>,
    pub decision: String,
    pub reason: Option<String>,
    pub commit_hash: Option<String>,
    pub evidence_url: Option<String>,
}

/// Immutable audit trail using WORM (Write Once, Read Many) principle
#[derive(Clone)]
pub struct AuditLog {
    path: PathBuf,
    /// Ensure atomic writes
    write_lock: Arc<Mutex<()>>,
}

impl AuditLog {
    /// Create or open an audit log
    pub fn new(path: PathBuf) -> Result<Self> {
        info!("📋 Audit log initialized at: {:?}", path);

        // Ensure parent directory exists
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        // Initialize with empty array if doesn't exist
        if !path.exists() {
            let mut file = OpenOptions::new()
                .create(true)
                .write(true)
                .open(&path)?;

            // Write WORM header
            let header = serde_json::json!({
                "version": "1.0.0",
                "type": "WORM_AUDIT_LOG",
                "created_at": Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true),
                "entries": []
            });

            writeln!(file, "{}", header.to_string())?;
            file.sync_all()?;
        }

        Ok(AuditLog {
            path,
            write_lock: Arc::new(Mutex::new(())),
        })
    }

    /// Log a submitted change
    pub async fn log_submitted(&self, change: &PendingChange) -> Result<()> {
        let entry = AuditEntry {
            timestamp: Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true),
            event_type: "CHANGE_SUBMITTED".to_string(),
            change_id: change.id.clone(),
            agent_name: change.agent_name.clone(),
            reviewer: None,
            decision: "AWAITING_REVIEW".to_string(),
            reason: None,
            commit_hash: None,
            evidence_url: Some(change.evidence.clone()),
        };

        self.append_entry(&entry).await?;

        info!(
            "📝 [AUDIT] Change submitted: {} (agent: {})",
            change.id, change.agent_name
        );

        Ok(())
    }

    /// Log an approval decision
    pub async fn log_approval(
        &self,
        change_id: &str,
        reviewer: &str,
        description: &str,
    ) -> Result<()> {
        let entry = AuditEntry {
            timestamp: Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true),
            event_type: "CHANGE_APPROVED".to_string(),
            change_id: change_id.to_string(),
            agent_name: "human-touch".to_string(),
            reviewer: Some(reviewer.to_string()),
            decision: "APPROVED".to_string(),
            reason: Some(format!("Human approval granted: {}", description)),
            commit_hash: None,
            evidence_url: None,
        };

        self.append_entry(&entry).await?;

        info!(
            "✅ [AUDIT] Change approved: {} by {}",
            change_id, reviewer
        );

        Ok(())
    }

    /// Log a rejection decision
    pub async fn log_rejection(
        &self,
        change_id: &str,
        reason: &str,
        reviewer: &str,
    ) -> Result<()> {
        let entry = AuditEntry {
            timestamp: Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true),
            event_type: "CHANGE_REJECTED".to_string(),
            change_id: change_id.to_string(),
            agent_name: "human-touch".to_string(),
            reviewer: Some(reviewer.to_string()),
            decision: "REJECTED".to_string(),
            reason: Some(reason.to_string()),
            commit_hash: None,
            evidence_url: None,
        };

        self.append_entry(&entry).await?;

        info!(
            "❌ [AUDIT] Change rejected: {} — {}",
            change_id, reason
        );

        Ok(())
    }

    /// Log a commit
    pub async fn log_commit(
        &self,
        change_id: &str,
        commit_hash: &str,
        reviewer: &str,
    ) -> Result<()> {
        let entry = AuditEntry {
            timestamp: Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true),
            event_type: "CHANGE_COMMITTED".to_string(),
            change_id: change_id.to_string(),
            agent_name: "human-touch".to_string(),
            reviewer: Some(reviewer.to_string()),
            decision: "COMMITTED".to_string(),
            reason: None,
            commit_hash: Some(commit_hash.to_string()),
            evidence_url: None,
        };

        self.append_entry(&entry).await?;

        info!(
            "📝 [AUDIT] Change committed: {} → {}",
            change_id, commit_hash
        );

        Ok(())
    }

    /// Append an entry to the audit log (atomic WORM write)
    async fn append_entry(&self, entry: &AuditEntry) -> Result<()> {
        let _lock = self.write_lock.lock().await;

        debug!(
            "🔒 [WORM] Appending entry: {}",
            serde_json::to_string(entry)?
        );

        // In a real WORM system, would use append-only storage (e.g., IPFS, blockchain)
        // For now: use file append with fsync
        let mut file = OpenOptions::new()
            .append(true)
            .open(&self.path)?;

        // Write entry as JSON line
        let line = format!("{}\n", serde_json::to_string(entry)?);
        file.write_all(line.as_bytes())?;
        file.sync_all()?;

        Ok(())
    }

    /// Read audit log entries
    pub async fn read_entries(&self) -> Result<Vec<AuditEntry>> {
        let _lock = self.write_lock.lock().await;

        let content = std::fs::read_to_string(&self.path)?;
        let mut entries = Vec::new();

        for line in content.lines() {
            // Skip header
            if line.contains("\"version\"") || line.contains("\"type\"") {
                continue;
            }

            // Skip empty lines
            if line.trim().is_empty() {
                continue;
            }

            if let Ok(entry) = serde_json::from_str::<AuditEntry>(line) {
                entries.push(entry);
            }
        }

        Ok(entries)
    }

    /// Generate audit summary
    pub async fn generate_summary(&self) -> Result<AuditSummary> {
        let entries = self.read_entries().await?;

        let mut summary = AuditSummary::default();

        for entry in entries {
            summary.total_events += 1;

            match entry.event_type.as_str() {
                "CHANGE_SUBMITTED" => summary.changes_submitted += 1,
                "CHANGE_APPROVED" => summary.changes_approved += 1,
                "CHANGE_REJECTED" => summary.changes_rejected += 1,
                "CHANGE_COMMITTED" => summary.changes_committed += 1,
                _ => {}
            }

            if let Some(reviewer) = entry.reviewer {
                *summary.reviewers.entry(reviewer).or_insert(0) += 1;
            }
        }

        Ok(summary)
    }
}

/// Summary statistics
#[derive(Debug, Default, Serialize, Deserialize)]
pub struct AuditSummary {
    pub total_events: usize,
    pub changes_submitted: usize,
    pub changes_approved: usize,
    pub changes_rejected: usize,
    pub changes_committed: usize,
    pub reviewers: std::collections::HashMap<String, usize>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::NamedTempFile;

    #[tokio::test]
    async fn test_audit_log_creation() {
        let tmp = NamedTempFile::new().unwrap();
        let log = AuditLog::new(tmp.path().to_path_buf()).unwrap();

        let change = PendingChange {
            id: "test-123".to_string(),
            description: "Test change".to_string(),
            evidence: "https://example.com".to_string(),
            agent_name: "test-agent".to_string(),
            created_at: Utc::now(),
            files: vec![],
            diff: "".to_string(),
        };

        assert!(log.log_submitted(&change).await.is_ok());
    }

    #[tokio::test]
    async fn test_audit_entries() {
        let tmp = NamedTempFile::new().unwrap();
        let log = AuditLog::new(tmp.path().to_path_buf()).unwrap();

        let change = PendingChange {
            id: "test-456".to_string(),
            description: "Test change".to_string(),
            evidence: "https://example.com".to_string(),
            agent_name: "test-agent".to_string(),
            created_at: Utc::now(),
            files: vec![],
            diff: "".to_string(),
        };

        log.log_submitted(&change).await.unwrap();
        log.log_approval("test-456", "reviewer@example.com", "Looks good")
            .await
            .unwrap();

        let entries = log.read_entries().await.unwrap();
        assert!(entries.len() >= 2);

        let submitted = entries.iter().find(|e| e.event_type == "CHANGE_SUBMITTED");
        assert!(submitted.is_some());

        let approved = entries.iter().find(|e| e.event_type == "CHANGE_APPROVED");
        assert!(approved.is_some());
    }
}
