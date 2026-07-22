//! Job Queue Management
//!
//! IBM i-style job queue with priority scheduling

use crate::{Job, JobStatus, Result, ShadowRpgError};
use std::collections::BinaryHeap;
use std::cmp::Ordering;
use uuid::Uuid;

#[derive(Debug)]
pub enum QueueError {
    JobNotFound(Uuid),
    QueueFull,
    InvalidOperation(String),
}

impl std::fmt::Display for QueueError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            QueueError::JobNotFound(id) => write!(f, "Job not found: {}", id),
            QueueError::QueueFull => write!(f, "Queue is full"),
            QueueError::InvalidOperation(msg) => write!(f, "Invalid operation: {}", msg),
        }
    }
}

impl std::error::Error for QueueError {}

/// Wrapper for priority queue ordering
#[derive(Debug)]
struct PriorityJob(Job);

impl PartialEq for PriorityJob {
    fn eq(&self, other: &Self) -> bool {
        self.0.priority == other.0.priority
    }
}

impl Eq for PriorityJob {}

impl PartialOrd for PriorityJob {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for PriorityJob {
    fn cmp(&self, other: &Self) -> Ordering {
        // Higher priority first, then earlier submission
        self.0.priority.cmp(&other.0.priority)
            .then_with(|| other.0.submitted_at.cmp(&self.0.submitted_at))
    }
}

/// Job queue with priority scheduling
pub struct JobQueue {
    queue: BinaryHeap<PriorityJob>,
    max_size: usize,
}

impl JobQueue {
    pub fn new(max_size: usize) -> Self {
        Self {
            queue: BinaryHeap::new(),
            max_size,
        }
    }
    
    pub fn submit(&mut self, mut job: Job) -> Result<()> {
        if self.queue.len() >= self.max_size {
            return Err(ShadowRpgError::Queue("Queue is full".to_string()));
        }
        
        job.update_status(JobStatus::Queued);
        self.queue.push(PriorityJob(job));
        Ok(())
    }
    
    pub fn pop(&mut self) -> Option<Job> {
        self.queue.pop().map(|pj| pj.0)
    }
    
    pub fn len(&self) -> usize {
        self.queue.len()
    }
    
    pub fn is_empty(&self) -> bool {
        self.queue.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::JobPriority;

    #[test]
    fn test_queue_priority() {
        let mut queue = JobQueue::new(10);
        
        let job1 = Job::new("j1".to_string(), "c1".to_string(), "l1".to_string(), "b1".to_string())
            .with_priority(JobPriority::Low);
        let job2 = Job::new("j2".to_string(), "c2".to_string(), "l2".to_string(), "b2".to_string())
            .with_priority(JobPriority::High);
        
        queue.submit(job1).unwrap();
        queue.submit(job2).unwrap();
        
        let first = queue.pop().unwrap();
        assert_eq!(first.job_name, "j2"); // High priority first
    }
}

// Made with Bob
