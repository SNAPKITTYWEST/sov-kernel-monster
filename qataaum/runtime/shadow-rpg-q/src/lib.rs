//! ShadowRPG-Q: IBM i-style Quantum Job Control Runtime
//!
//! An original control language and runtime inspired by IBM i operational
//! workflows, record-oriented processing, and job queue management.
//!
//! This is NOT an IBM product and does not use proprietary IBM code.

pub mod job;
pub mod queue;
pub mod journal;
pub mod receipt;
pub mod executor;

pub use job::{Job, JobStatus, JobPriority};
pub use queue::JobQueue;
pub use journal::{Journal, JournalEntry, JournalEntryType};
pub use receipt::{ExecutionReceipt, ReceiptChain};
pub use executor::{Executor, ExecutorConfig};

use std::fmt;

/// Result type for ShadowRPG-Q operations
pub type Result<T> = std::result::Result<T, ShadowRpgError>;

/// Error types for ShadowRPG-Q
#[derive(Debug)]
pub enum ShadowRpgError {
    Job(String),
    Queue(String),
    Journal(String),
    Receipt(String),
    Executor(String),
    Io(String),
    Serialization(String),
}

impl fmt::Display for ShadowRpgError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ShadowRpgError::Job(msg) => write!(f, "Job error: {}", msg),
            ShadowRpgError::Queue(msg) => write!(f, "Queue error: {}", msg),
            ShadowRpgError::Journal(msg) => write!(f, "Journal error: {}", msg),
            ShadowRpgError::Receipt(msg) => write!(f, "Receipt error: {}", msg),
            ShadowRpgError::Executor(msg) => write!(f, "Executor error: {}", msg),
            ShadowRpgError::Io(msg) => write!(f, "I/O error: {}", msg),
            ShadowRpgError::Serialization(msg) => write!(f, "Serialization error: {}", msg),
        }
    }
}

impl std::error::Error for ShadowRpgError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_basic_workflow() {
        use tempfile::tempdir;
        
        let dir = tempdir().unwrap();
        let config = ExecutorConfig {
            journal_path: dir.path().join("test.journal"),
            ..Default::default()
        };
        
        let executor = Executor::new(config).unwrap();
        
        // Create and submit a job
        let job = Job::new(
            "test_job".to_string(),
            "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];".to_string(),
            "qasm2".to_string(),
            "simulator".to_string(),
        ).with_priority(JobPriority::High);
        
        let job_id = executor.submit_job(job).unwrap();
        assert_eq!(executor.queue_length().unwrap(), 1);
        
        // Get and execute the job
        let job = executor.get_next_job().unwrap().unwrap();
        assert_eq!(job.job_id, job_id);
        
        let receipt = executor.execute_job(job).unwrap();
        assert!(receipt.verify_seal());
        assert_eq!(receipt.job_id, job_id);
    }
    
    #[test]
    fn test_receipt_chain() {
        let mut chain = ReceiptChain::new();
        
        let job1 = Job::new("j1".to_string(), "c1".to_string(), "qasm2".to_string(), "sim".to_string());
        let receipt1 = ExecutionReceipt::from_job(&job1, Some("result1"));
        
        let job2 = Job::new("j2".to_string(), "c2".to_string(), "qasm2".to_string(), "sim".to_string());
        let receipt2 = ExecutionReceipt::from_job(&job2, Some("result2"));
        
        chain.add(receipt1).unwrap();
        chain.add(receipt2).unwrap();
        
        assert_eq!(chain.len(), 2);
        assert!(chain.verify_all());
    }
}

// Made with Bob
