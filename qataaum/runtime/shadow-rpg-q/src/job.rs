//! Quantum Job Definitions
//!
//! Represents quantum compilation and execution jobs in an IBM i-style
//! record-oriented format.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;
use chrono::{DateTime, Utc};

/// Job status following IBM i job lifecycle
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum JobStatus {
    /// Job received but not yet validated
    Received,
    /// Job validated and ready for compilation
    Validated,
    /// Job is being compiled
    Compiling,
    /// Compilation complete, ready for execution
    Compiled,
    /// Job is queued for execution
    Queued,
    /// Job is currently executing
    Executing,
    /// Job completed successfully
    Completed,
    /// Job failed
    Failed,
    /// Job was cancelled
    Cancelled,
}

/// Job priority levels
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum JobPriority {
    Low = 1,
    Normal = 5,
    High = 9,
}

/// Quantum job record
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Job {
    /// Unique job identifier
    pub job_id: Uuid,
    
    /// Job name (user-provided)
    pub job_name: String,
    
    /// Job status
    pub status: JobStatus,
    
    /// Job priority
    pub priority: JobPriority,
    
    /// Source code (OpenQASM or MetaQASM-4)
    pub source_code: String,
    
    /// Source language
    pub source_language: String,
    
    /// Target backend
    pub target_backend: String,
    
    /// Optimization level (0-3)
    pub optimization_level: u8,
    
    /// Number of shots (measurement repetitions)
    pub shots: u32,
    
    /// Job metadata
    pub metadata: HashMap<String, String>,
    
    /// Submission timestamp
    pub submitted_at: DateTime<Utc>,
    
    /// Start timestamp (when execution began)
    pub started_at: Option<DateTime<Utc>>,
    
    /// Completion timestamp
    pub completed_at: Option<DateTime<Utc>>,
    
    /// Error message (if failed)
    pub error_message: Option<String>,
    
    /// Compilation hash (SHA-256 of compiled circuit)
    pub compilation_hash: Option<String>,
    
    /// Result hash (SHA-256 of execution results)
    pub result_hash: Option<String>,
}

impl Job {
    /// Create a new job
    pub fn new(
        job_name: String,
        source_code: String,
        source_language: String,
        target_backend: String,
    ) -> Self {
        Self {
            job_id: Uuid::new_v4(),
            job_name,
            status: JobStatus::Received,
            priority: JobPriority::Normal,
            source_code,
            source_language,
            target_backend,
            optimization_level: 1,
            shots: 1024,
            metadata: HashMap::new(),
            submitted_at: Utc::now(),
            started_at: None,
            completed_at: None,
            error_message: None,
            compilation_hash: None,
            result_hash: None,
        }
    }
    
    /// Set job priority
    pub fn with_priority(mut self, priority: JobPriority) -> Self {
        self.priority = priority;
        self
    }
    
    /// Set optimization level
    pub fn with_optimization(mut self, level: u8) -> Self {
        self.optimization_level = level.min(3);
        self
    }
    
    /// Set number of shots
    pub fn with_shots(mut self, shots: u32) -> Self {
        self.shots = shots;
        self
    }
    
    /// Add metadata
    pub fn with_metadata(mut self, key: String, value: String) -> Self {
        self.metadata.insert(key, value);
        self
    }
    
    /// Update job status
    pub fn update_status(&mut self, new_status: JobStatus) {
        self.status = new_status;
        
        match new_status {
            JobStatus::Executing if self.started_at.is_none() => {
                self.started_at = Some(Utc::now());
            }
            JobStatus::Completed | JobStatus::Failed | JobStatus::Cancelled => {
                if self.completed_at.is_none() {
                    self.completed_at = Some(Utc::now());
                }
            }
            _ => {}
        }
    }
    
    /// Mark job as failed with error message
    pub fn fail(&mut self, error: String) {
        self.status = JobStatus::Failed;
        self.error_message = Some(error);
        self.completed_at = Some(Utc::now());
    }
    
    /// Get job duration in seconds
    pub fn duration_seconds(&self) -> Option<f64> {
        match (self.started_at, self.completed_at) {
            (Some(start), Some(end)) => {
                Some((end - start).num_milliseconds() as f64 / 1000.0)
            }
            _ => None,
        }
    }
    
    /// Check if job is in a terminal state
    pub fn is_terminal(&self) -> bool {
        matches!(
            self.status,
            JobStatus::Completed | JobStatus::Failed | JobStatus::Cancelled
        )
    }
    
    /// Check if job is active (running or queued)
    pub fn is_active(&self) -> bool {
        matches!(
            self.status,
            JobStatus::Queued | JobStatus::Executing | JobStatus::Compiling
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_job_creation() {
        let job = Job::new(
            "test_job".to_string(),
            "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];".to_string(),
            "openqasm2".to_string(),
            "simulator".to_string(),
        );
        
        assert_eq!(job.status, JobStatus::Received);
        assert_eq!(job.priority, JobPriority::Normal);
        assert_eq!(job.optimization_level, 1);
        assert_eq!(job.shots, 1024);
    }
    
    #[test]
    fn test_job_builder() {
        let job = Job::new(
            "test".to_string(),
            "code".to_string(),
            "openqasm2".to_string(),
            "sim".to_string(),
        )
        .with_priority(JobPriority::High)
        .with_optimization(3)
        .with_shots(2048)
        .with_metadata("user".to_string(), "alice".to_string());
        
        assert_eq!(job.priority, JobPriority::High);
        assert_eq!(job.optimization_level, 3);
        assert_eq!(job.shots, 2048);
        assert_eq!(job.metadata.get("user"), Some(&"alice".to_string()));
    }
    
    #[test]
    fn test_status_transitions() {
        let mut job = Job::new(
            "test".to_string(),
            "code".to_string(),
            "openqasm2".to_string(),
            "sim".to_string(),
        );
        
        assert_eq!(job.status, JobStatus::Received);
        assert!(job.started_at.is_none());
        
        job.update_status(JobStatus::Executing);
        assert_eq!(job.status, JobStatus::Executing);
        assert!(job.started_at.is_some());
        
        job.update_status(JobStatus::Completed);
        assert_eq!(job.status, JobStatus::Completed);
        assert!(job.completed_at.is_some());
        assert!(job.is_terminal());
    }
    
    #[test]
    fn test_job_failure() {
        let mut job = Job::new(
            "test".to_string(),
            "code".to_string(),
            "openqasm2".to_string(),
            "sim".to_string(),
        );
        
        job.fail("Compilation error".to_string());
        assert_eq!(job.status, JobStatus::Failed);
        assert_eq!(job.error_message, Some("Compilation error".to_string()));
        assert!(job.is_terminal());
    }
    
    #[test]
    fn test_job_states() {
        let mut job = Job::new(
            "test".to_string(),
            "code".to_string(),
            "openqasm2".to_string(),
            "sim".to_string(),
        );
        
        assert!(!job.is_terminal());
        assert!(!job.is_active());
        
        job.update_status(JobStatus::Queued);
        assert!(job.is_active());
        assert!(!job.is_terminal());
        
        job.update_status(JobStatus::Completed);
        assert!(job.is_terminal());
        assert!(!job.is_active());
    }
}

// Made with Bob
