//! Execution Receipt Generation and Verification
//!
//! Cryptographically sealed execution receipts for provenance

use crate::{Job, Result, ShadowRpgError};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Sha256, Digest};
use uuid::Uuid;

/// Execution receipt with cryptographic seal
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecutionReceipt {
    pub receipt_id: Uuid,
    pub job_id: Uuid,
    pub job_name: String,
    pub source_hash: String,
    pub compilation_hash: String,
    pub target_backend: String,
    pub submitted_at: DateTime<Utc>,
    pub started_at: Option<DateTime<Utc>>,
    pub completed_at: Option<DateTime<Utc>>,
    pub status: String,
    pub result_hash: Option<String>,
    pub metadata: serde_json::Value,
    pub seal: String,
}

impl ExecutionReceipt {
    pub fn from_job(job: &Job, result_data: Option<&str>) -> Self {
        let receipt_id = Uuid::new_v4();
        let result_hash = result_data.map(|data| Self::hash_data(data));
        let source_hash = Self::hash_data(&job.source_code);
        
        let metadata = serde_json::json!({
            "priority": format!("{:?}", job.priority),
            "language": job.source_language,
            "shots": job.shots,
        });
        
        let seal = Self::compute_seal(
            receipt_id,
            job.job_id,
            &source_hash,
            job.compilation_hash.as_deref().unwrap_or(""),
            &job.target_backend,
            result_hash.as_deref(),
        );
        
        Self {
            receipt_id,
            job_id: job.job_id,
            job_name: job.job_name.clone(),
            source_hash,
            compilation_hash: job.compilation_hash.clone().unwrap_or_default(),
            target_backend: job.target_backend.clone(),
            submitted_at: job.submitted_at,
            started_at: job.started_at,
            completed_at: job.completed_at,
            status: format!("{:?}", job.status),
            result_hash,
            metadata,
            seal,
        }
    }
    
    fn hash_data(data: &str) -> String {
        let mut hasher = Sha256::new();
        hasher.update(data.as_bytes());
        format!("{:x}", hasher.finalize())
    }
    
    fn compute_seal(
        receipt_id: Uuid,
        job_id: Uuid,
        source_hash: &str,
        compilation_hash: &str,
        target_backend: &str,
        result_hash: Option<&str>,
    ) -> String {
        let mut hasher = Sha256::new();
        hasher.update(receipt_id.as_bytes());
        hasher.update(job_id.as_bytes());
        hasher.update(source_hash.as_bytes());
        hasher.update(compilation_hash.as_bytes());
        hasher.update(target_backend.as_bytes());
        if let Some(rh) = result_hash {
            hasher.update(rh.as_bytes());
        }
        format!("{:x}", hasher.finalize())
    }
    
    pub fn verify_seal(&self) -> bool {
        let computed = Self::compute_seal(
            self.receipt_id,
            self.job_id,
            &self.source_hash,
            &self.compilation_hash,
            &self.target_backend,
            self.result_hash.as_deref(),
        );
        computed == self.seal
    }
    
    pub fn to_json(&self) -> Result<String> {
        serde_json::to_string_pretty(self)
            .map_err(|e| ShadowRpgError::Serialization(format!("Failed to serialize receipt: {}", e)))
    }
    
    pub fn from_json(json: &str) -> Result<Self> {
        serde_json::from_str(json)
            .map_err(|e| ShadowRpgError::Serialization(format!("Failed to deserialize receipt: {}", e)))
    }
}

/// Receipt chain for audit trail
#[derive(Debug)]
pub struct ReceiptChain {
    receipts: Vec<ExecutionReceipt>,
}

impl ReceiptChain {
    pub fn new() -> Self {
        Self {
            receipts: Vec::new(),
        }
    }
    
    pub fn add(&mut self, receipt: ExecutionReceipt) -> Result<()> {
        if !receipt.verify_seal() {
            return Err(ShadowRpgError::Receipt("Receipt seal verification failed".to_string()));
        }
        self.receipts.push(receipt);
        Ok(())
    }
    
    pub fn verify_all(&self) -> bool {
        self.receipts.iter().all(|r| r.verify_seal())
    }
    
    pub fn len(&self) -> usize {
        self.receipts.len()
    }
    
    pub fn is_empty(&self) -> bool {
        self.receipts.is_empty()
    }
    
    pub fn get(&self, index: usize) -> Option<&ExecutionReceipt> {
        self.receipts.get(index)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::JobPriority;

    #[test]
    fn test_receipt_seal() {
        let job = Job::new("test".to_string(), "code".to_string(), "qasm2".to_string(), "sim".to_string())
            .with_priority(JobPriority::Normal);
        
        let receipt = ExecutionReceipt::from_job(&job, Some("result_data"));
        assert!(receipt.verify_seal());
    }
    
    #[test]
    fn test_receipt_json_roundtrip() {
        let job = Job::new("test".to_string(), "code".to_string(), "qasm2".to_string(), "sim".to_string());
        let receipt = ExecutionReceipt::from_job(&job, None);
        
        let json = receipt.to_json().unwrap();
        let restored = ExecutionReceipt::from_json(&json).unwrap();
        
        assert_eq!(receipt.receipt_id, restored.receipt_id);
        assert!(restored.verify_seal());
    }
    
    #[test]
    fn test_receipt_chain() {
        let mut chain = ReceiptChain::new();
        
        let job1 = Job::new("j1".to_string(), "c1".to_string(), "qasm2".to_string(), "sim".to_string());
        let receipt1 = ExecutionReceipt::from_job(&job1, None);
        
        chain.add(receipt1).unwrap();
        assert_eq!(chain.len(), 1);
        assert!(chain.verify_all());
    }
}

// Made with Bob
