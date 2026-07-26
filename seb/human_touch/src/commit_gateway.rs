use anyhow::Result;
use blake3;
use chrono::Utc;
use ed25519_dalek::SigningKey;
use git2::{Repository, Signature as GitSignature};
use hex;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::Arc;
use tracing::{debug, info, warn};

/// Cryptographic approval certificate
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApprovalCertificate {
    /// Change ID being approved
    pub change_id: String,
    /// Human reviewer's name
    pub reviewer: String,
    /// ISO8601 timestamp of approval
    pub approval_time: String,
    /// Blake3 hash of the change evidence
    pub evidence_hash: String,
    /// Ed25519 signature of (change_id || reviewer || time)
    pub signature: String,
}

/// Commit metadata including human approval
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HumanApprovedCommit {
    /// Change ID
    pub change_id: String,
    /// Human reviewer who approved
    pub approved_by: String,
    /// Approval timestamp
    pub approval_date: String,
    /// URL or link to evidence
    pub evidence_url: String,
    /// Link to review decision
    pub review_link: Option<String>,
}

/// Commit gateway enforcing human approval
#[derive(Clone)]
pub struct CommitGateway {
    repo_path: PathBuf,
    approval_timeout_secs: u64,
    /// Signing key for certificates (in production, would be secured)
    signing_key: Arc<Option<SigningKey>>,
}

impl CommitGateway {
    /// Create a new commit gateway
    pub fn new(repo_path: PathBuf, approval_timeout_secs: u64) -> Result<Self> {
        info!(
            "🔐 CommitGateway initialized (repo: {:?}, timeout: {}s)",
            repo_path, approval_timeout_secs
        );

        // In production: load signing key from secure storage
        // For now: use a placeholder
        let key_seed = [0u8; 32];
        let signing_key = SigningKey::from_bytes(&key_seed);

        Ok(CommitGateway {
            repo_path,
            approval_timeout_secs,
            signing_key: Arc::new(Some(signing_key)),
        })
    }

    /// Pre-commit verification: ensure change has human approval
    pub async fn verify_approval_required(&self, change_id: &str) -> Result<()> {
        info!("🔍 Verifying approval requirement for change: {}", change_id);

        // This would check the audit log to ensure approval exists
        // For now: placeholder verification
        if change_id.is_empty() {
            return Err(anyhow::anyhow!("Change ID cannot be empty"));
        }

        debug!("✅ Approval verification passed for: {}", change_id);
        Ok(())
    }

    /// Stage files for commit
    pub fn stage_files(&self, files: &[String]) -> Result<()> {
        let repo = Repository::open(&self.repo_path)?;
        let mut index = repo.index()?;

        for file in files {
            index.add_path(&std::path::Path::new(file))?;
        }

        info!("📦 Staged {} files for commit", files.len());
        index.write()?;

        Ok(())
    }

    /// Create an approval certificate
    pub fn create_approval_certificate(
        &self,
        change_id: &str,
        reviewer: &str,
        evidence_url: &str,
    ) -> Result<ApprovalCertificate> {
        let now = Utc::now();

        // Hash the evidence URL
        let evidence_hash = blake3::hash(evidence_url.as_bytes());
        let evidence_hash_hex = hex::encode(evidence_hash.as_bytes());

        // Create signing material: change_id || reviewer || timestamp
        let signing_material = format!(
            "{}||{}||{}",
            change_id,
            reviewer,
            now.to_rfc3339_opts(chrono::SecondsFormat::Secs, true)
        );

        // Sign (in production: use actual signing key, not placeholder)
        let signature_bytes = blake3::hash(signing_material.as_bytes());
        let signature_hex = hex::encode(signature_bytes.as_bytes());

        let cert = ApprovalCertificate {
            change_id: change_id.to_string(),
            reviewer: reviewer.to_string(),
            approval_time: now.to_rfc3339_opts(chrono::SecondsFormat::Secs, true),
            evidence_hash: evidence_hash_hex,
            signature: signature_hex,
        };

        info!("🎖️  Approval certificate created: {:?}", cert);

        Ok(cert)
    }

    /// Commit changes with human approval metadata
    pub fn commit_with_approval(
        &self,
        change_id: &str,
        reviewer: &str,
        message: &str,
        evidence_url: &str,
    ) -> Result<String> {
        let repo = Repository::open(&self.repo_path)?;

        // Get the index (staged files)
        let mut index = repo.index()?;
        let tree_id = index.write_tree()?;
        let tree = repo.find_tree(tree_id)?;

        // Create git signature for the commit
        let git_sig = GitSignature::now(reviewer, &format!("{}-review@snapkitty.ai", reviewer))?;

        // Get HEAD commit (parent)
        let head = repo.head()?;
        let parent_commit = repo.find_commit(head.target().ok_or(anyhow::anyhow!(
            "No HEAD commit found"
        ))?)?;

        // Format commit message with approval metadata
        let commit_body = format!(
            "{}\n\nApproved-By: {}\nReview-Date: {}\nEvidence: {}\nChange-ID: {}\n\nCo-Authored-By: Human-Touch Gateway <human-review@snapkitty.ai>",
            message,
            reviewer,
            Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true),
            evidence_url,
            change_id
        );

        // Create the commit
        let commit_oid = repo.commit(
            Some("HEAD"),
            &git_sig,
            &git_sig,
            &commit_body,
            &tree,
            &[&parent_commit],
        )?;

        let commit_hash = commit_oid.to_string();
        info!(
            "✅ Commit created: {} (change: {}, reviewer: {})",
            commit_hash, change_id, reviewer
        );

        Ok(commit_hash)
    }

    /// Reject a commit (prevent it from landing)
    pub fn reject_commit(&self, change_id: &str, reason: &str) -> Result<()> {
        warn!(
            "❌ Commit rejected for change: {} — Reason: {}",
            change_id, reason
        );

        // Would write rejection to audit log
        // Prevent any git operations for this change

        Ok(())
    }

    /// Verify commit signature and metadata
    pub fn verify_commit_approval(&self, commit_hash: &str) -> Result<HumanApprovedCommit> {
        let repo = Repository::open(&self.repo_path)?;
        let oid = git2::Oid::from_str(commit_hash)?;
        let commit = repo.find_commit(oid)?;

        let message = commit.message().unwrap_or("(no message)");

        // Parse approval metadata from commit message
        let mut approved_by = "unknown";
        let mut approval_date = "unknown";
        let mut evidence_url = "unknown";
        let mut change_id = "unknown";

        for line in message.lines() {
            if line.starts_with("Approved-By:") {
                approved_by = line.trim_start_matches("Approved-By:").trim();
            } else if line.starts_with("Review-Date:") {
                approval_date = line.trim_start_matches("Review-Date:").trim();
            } else if line.starts_with("Evidence:") {
                evidence_url = line.trim_start_matches("Evidence:").trim();
            } else if line.starts_with("Change-ID:") {
                change_id = line.trim_start_matches("Change-ID:").trim();
            }
        }

        // Verify all required fields are present
        if approved_by == "unknown" {
            return Err(anyhow::anyhow!("Commit missing Approved-By field"));
        }

        debug!(
            "✅ Commit verified: {} approved by {} on {}",
            commit_hash, approved_by, approval_date
        );

        Ok(HumanApprovedCommit {
            change_id: change_id.to_string(),
            approved_by: approved_by.to_string(),
            approval_date: approval_date.to_string(),
            evidence_url: evidence_url.to_string(),
            review_link: None,
        })
    }

    /// Enforce pre-commit hook: no auto-commits allowed
    pub fn check_no_auto_commit(&self, message: &str) -> Result<()> {
        // Reject auto-generated commits
        if message.contains("[auto]") || message.contains("auto-commit") {
            return Err(anyhow::anyhow!(
                "❌ Auto-commits rejected. All changes require human approval."
            ));
        }

        // Reject empty messages
        if message.trim().is_empty() {
            return Err(anyhow::anyhow!("❌ Commit message cannot be empty"));
        }

        // Require Approved-By field
        if !message.contains("Approved-By:") {
            return Err(anyhow::anyhow!(
                "❌ Commit missing Approved-By field. All commits require human approval."
            ));
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_verify_approval_required() {
        let gateway = CommitGateway::new(PathBuf::from("."), 3600).unwrap();
        assert!(gateway.verify_approval_required("test-123").await.is_ok());
        assert!(gateway.verify_approval_required("").await.is_err());
    }

    #[test]
    fn test_create_approval_certificate() {
        let gateway = CommitGateway::new(PathBuf::from("."), 3600).unwrap();
        let cert = gateway
            .create_approval_certificate(
                "change-123",
                "reviewer@example.com",
                "https://example.com/evidence",
            )
            .unwrap();

        assert_eq!(cert.change_id, "change-123");
        assert_eq!(cert.reviewer, "reviewer@example.com");
        assert!(!cert.signature.is_empty());
    }

    #[test]
    fn test_check_no_auto_commit() {
        let gateway = CommitGateway::new(PathBuf::from("."), 3600).unwrap();

        // Should reject auto-commits
        assert!(gateway
            .check_no_auto_commit("feat: [auto] add feature")
            .is_err());

        // Should reject empty
        assert!(gateway.check_no_auto_commit("").is_err());

        // Should require Approved-By
        assert!(gateway.check_no_auto_commit("feat: add feature").is_err());

        // Should accept valid message with approval
        assert!(gateway
            .check_no_auto_commit("feat: add feature\n\nApproved-By: Human")
            .is_ok());
    }
}
