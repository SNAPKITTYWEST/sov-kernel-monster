//! Main Execution Engine
//!
//! Coordinates job execution through the hybrid FSM

use crate::{Job, JobQueue, Journal, ExecutionReceipt, Result, ShadowRpgError, JobStatus};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use uuid::Uuid;

/// Execution engine configuration
#[derive(Debug, Clone)]
pub struct ExecutorConfig {
    pub max_queue_size: usize,
    pub journal_path: PathBuf,
    pub max_concurrent_jobs: usize,
}

impl Default for ExecutorConfig {
    fn default() -> Self {
        Self {
            max_queue_size: 1000,
            journal_path: PathBuf::from("shadow-rpg-q.journal"),
            max_concurrent_jobs: 4,
        }
    }
}

/// Main execution engine
pub struct Executor {
    config: ExecutorConfig,
    queue: Arc<Mutex<JobQueue>>,
    journal: Arc<Mutex<Journal>>,
    active_jobs: Arc<Mutex<Vec<Uuid>>>,
}

impl Executor {
    pub fn new(config: ExecutorConfig) -> Result<Self> {
        let queue = Arc::new(Mutex::new(JobQueue::new(config.max_queue_size)));
        let journal = Arc::new(Mutex::new(Journal::new(&config.journal_path)?));
        let active_jobs = Arc::new(Mutex::new(Vec::new()));
        
        Ok(Self {
            config,
            queue,
            journal,
            active_jobs,
        })
    }
    
    /// Submit a job to the queue
    pub fn submit_job(&self, job: Job) -> Result<Uuid> {
        let job_id = job.job_id;
        
        // Log submission
        {
            let mut journal = self.journal.lock()
                .map_err(|e| ShadowRpgError::Executor(format!("Failed to lock journal: {}", e)))?;
            journal.log_job_submitted(&job)?;
        }
        
        // Add to queue
        {
            let mut queue = self.queue.lock()
                .map_err(|e| ShadowRpgError::Executor(format!("Failed to lock queue: {}", e)))?;
            queue.submit(job)?;
        }
        
        Ok(job_id)
    }
    
    /// Get next job from queue
    pub fn get_next_job(&self) -> Result<Option<Job>> {
        let mut queue = self.queue.lock()
            .map_err(|e| ShadowRpgError::Executor(format!("Failed to lock queue: {}", e)))?;
        
        Ok(queue.pop())
    }
    
    /// Execute a single job (simplified - actual execution would call compiler)
    pub fn execute_job(&self, mut job: Job) -> Result<ExecutionReceipt> {
        // Mark as executing
        job.update_status(JobStatus::Executing);
        
        {
            let mut journal = self.journal.lock()
                .map_err(|e| ShadowRpgError::Executor(format!("Failed to lock journal: {}", e)))?;
            journal.log_status_change(job.job_id, JobStatus::Queued, JobStatus::Executing)?;
        }
        
        {
            let mut active = self.active_jobs.lock()
                .map_err(|e| ShadowRpgError::Executor(format!("Failed to lock active jobs: {}", e)))?;
            active.push(job.job_id);
        }
        
        // Simulate execution (in real implementation, this would call the compiler and backend)
        // For now, just mark as completed
        job.update_status(JobStatus::Completed);
        
        {
            let mut journal = self.journal.lock()
                .map_err(|e| ShadowRpgError::Executor(format!("Failed to lock journal: {}", e)))?;
            journal.log_status_change(job.job_id, JobStatus::Executing, JobStatus::Completed)?;
        }
        
        {
            let mut active = self.active_jobs.lock()
                .map_err(|e| ShadowRpgError::Executor(format!("Failed to lock active jobs: {}", e)))?;
            active.retain(|&id| id != job.job_id);
        }
        
        // Generate receipt
        let receipt = ExecutionReceipt::from_job(&job, Some("simulated_result"));
        
        Ok(receipt)
    }
    
    /// Get queue length
    pub fn queue_length(&self) -> Result<usize> {
        let queue = self.queue.lock()
            .map_err(|e| ShadowRpgError::Executor(format!("Failed to lock queue: {}", e)))?;
        Ok(queue.len())
    }
    
    /// Get active job count
    pub fn active_job_count(&self) -> Result<usize> {
        let active = self.active_jobs.lock()
            .map_err(|e| ShadowRpgError::Executor(format!("Failed to lock active jobs: {}", e)))?;
        Ok(active.len())
    }
    
    /// Replay journal for recovery
    pub fn replay_journal(&self) -> Result<()> {
        let journal = self.journal.lock()
            .map_err(|e| ShadowRpgError::Executor(format!("Failed to lock journal: {}", e)))?;
        
        let entries = journal.replay()?;
        
        // In a real implementation, this would reconstruct state from journal entries
        // For now, just verify all entries
        for entry in entries {
            if !entry.verify_hash() {
                return Err(ShadowRpgError::Journal("Journal entry verification failed during replay".to_string()));
            }
        }
        
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;
    use crate::JobPriority;

    #[test]
    fn test_executor_submit_and_execute() {
        let dir = tempdir().unwrap();
        let config = ExecutorConfig {
            journal_path: dir.path().join("test.journal"),
            ..Default::default()
        };
        
        let executor = Executor::new(config).unwrap();
        
        let job = Job::new("test".to_string(), "code".to_string(), "qasm2".to_string(), "sim".to_string())
            .with_priority(JobPriority::Normal);
        
        let job_id = executor.submit_job(job).unwrap();
        assert_eq!(executor.queue_length().unwrap(), 1);
        
        let job = executor.get_next_job().unwrap().unwrap();
        assert_eq!(job.job_id, job_id);
        
        let receipt = executor.execute_job(job).unwrap();
        assert!(receipt.verify_seal());
    }
    
    #[test]
    fn test_executor_replay() {
        let dir = tempdir().unwrap();
        let config = ExecutorConfig {
            journal_path: dir.path().join("test.journal"),
            ..Default::default()
        };
        
        let executor = Executor::new(config).unwrap();
        
        let job = Job::new("test".to_string(), "code".to_string(), "qasm2".to_string(), "sim".to_string());
        executor.submit_job(job).unwrap();
        
        // Replay should succeed
        executor.replay_journal().unwrap();
    }
}

// Made with Bob
