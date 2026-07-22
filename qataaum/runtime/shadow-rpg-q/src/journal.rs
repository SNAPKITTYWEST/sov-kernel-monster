//! Append-Only Journal for Recovery
//!
//! IBM i-style journaling for deterministic replay and recovery

use crate::{Job, JobStatus, Result, ShadowRpgError};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Sha256, Digest};
use std::fs::{File, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use uuid::Uuid;

/// Journal entry types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum JournalEntryType {
    JobSubmitted,
    StatusChanged,
    CompilationStarted,
    CompilationCompleted,
    ExecutionStarted,
    ExecutionCompleted,
    ResultRecorded,
    JobCancelled,
    JobFailed,
}

/// Single journal entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JournalEntry {
    pub sequence: u64,
    pub timestamp: DateTime<Utc>,
    pub job_id: Uuid,
    pub entry_type: JournalEntryType,
    pub old_status: Option<JobStatus>,
    pub new_status: Option<JobStatus>,
    pub metadata: String,
    pub hash: String,
}

impl JournalEntry {
    pub fn new(
        sequence: u64,
        job_id: Uuid,
        entry_type: JournalEntryType,
        old_status: Option<JobStatus>,
        new_status: Option<JobStatus>,
        metadata: String,
    ) -> Self {
        let timestamp = Utc::now();
        let hash = Self::compute_hash(sequence, &timestamp, job_id, &metadata);
        
        Self {
            sequence,
            timestamp,
            job_id,
            entry_type,
            old_status,
            new_status,
            metadata,
            hash,
        }
    }
    
    fn compute_hash(sequence: u64, timestamp: &DateTime<Utc>, job_id: Uuid, metadata: &str) -> String {
        let mut hasher = Sha256::new();
        hasher.update(sequence.to_le_bytes());
        hasher.update(timestamp.to_rfc3339().as_bytes());
        hasher.update(job_id.as_bytes());
        hasher.update(metadata.as_bytes());
        format!("{:x}", hasher.finalize())
    }
    
    pub fn verify_hash(&self) -> bool {
        let computed = Self::compute_hash(self.sequence, &self.timestamp, self.job_id, &self.metadata);
        computed == self.hash
    }
}

/// Journal manager
pub struct Journal {
    path: PathBuf,
    sequence: u64,
}

impl Journal {
    pub fn new<P: AsRef<Path>>(path: P) -> Result<Self> {
        let path = path.as_ref().to_path_buf();
        
        // Create parent directory if needed
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| ShadowRpgError::Io(format!("Failed to create journal directory: {}", e)))?;
        }
        
        // Determine starting sequence
        let sequence = if path.exists() {
            Self::read_last_sequence(&path)?
        } else {
            0
        };
        
        Ok(Self { path, sequence })
    }
    
    fn read_last_sequence(path: &Path) -> Result<u64> {
        let file = File::open(path)
            .map_err(|e| ShadowRpgError::Io(format!("Failed to open journal: {}", e)))?;
        let reader = BufReader::new(file);
        
        let mut last_seq = 0;
        for line in reader.lines() {
            let line = line.map_err(|e| ShadowRpgError::Io(format!("Failed to read journal line: {}", e)))?;
            if let Ok(entry) = serde_json::from_str::<JournalEntry>(&line) {
                last_seq = entry.sequence;
            }
        }
        
        Ok(last_seq)
    }
    
    pub fn append(&mut self, entry: JournalEntry) -> Result<()> {
        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.path)
            .map_err(|e| ShadowRpgError::Io(format!("Failed to open journal for append: {}", e)))?;
        
        let json = serde_json::to_string(&entry)
            .map_err(|e| ShadowRpgError::Serialization(format!("Failed to serialize entry: {}", e)))?;
        
        writeln!(file, "{}", json)
            .map_err(|e| ShadowRpgError::Io(format!("Failed to write journal entry: {}", e)))?;
        
        self.sequence = entry.sequence;
        Ok(())
    }
    
    pub fn log_job_submitted(&mut self, job: &Job) -> Result<()> {
        self.sequence += 1;
        let entry = JournalEntry::new(
            self.sequence,
            job.job_id,
            JournalEntryType::JobSubmitted,
            None,
            Some(job.status.clone()),
            format!("Job {} submitted", job.job_name),
        );
        self.append(entry)
    }
    
    pub fn log_status_change(&mut self, job_id: Uuid, old_status: JobStatus, new_status: JobStatus) -> Result<()> {
        self.sequence += 1;
        let entry = JournalEntry::new(
            self.sequence,
            job_id,
            JournalEntryType::StatusChanged,
            Some(old_status),
            Some(new_status),
            format!("Status changed"),
        );
        self.append(entry)
    }
    
    pub fn replay(&self) -> Result<Vec<JournalEntry>> {
        if !self.path.exists() {
            return Ok(Vec::new());
        }
        
        let file = File::open(&self.path)
            .map_err(|e| ShadowRpgError::Io(format!("Failed to open journal: {}", e)))?;
        let reader = BufReader::new(file);
        
        let mut entries = Vec::new();
        for line in reader.lines() {
            let line = line.map_err(|e| ShadowRpgError::Io(format!("Failed to read journal line: {}", e)))?;
            let entry: JournalEntry = serde_json::from_str(&line)
                .map_err(|e| ShadowRpgError::Serialization(format!("Failed to deserialize entry: {}", e)))?;
            
            if !entry.verify_hash() {
                return Err(ShadowRpgError::Journal("Journal entry hash verification failed".to_string()));
            }
            
            entries.push(entry);
        }
        
        Ok(entries)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_journal_entry_hash() {
        let entry = JournalEntry::new(
            1,
            Uuid::new_v4(),
            JournalEntryType::JobSubmitted,
            None,
            Some(JobStatus::Received),
            "test".to_string(),
        );
        
        assert!(entry.verify_hash());
    }
    
    #[test]
    fn test_journal_append_and_replay() {
        let dir = tempdir().unwrap();
        let journal_path = dir.path().join("test.journal");
        
        let mut journal = Journal::new(&journal_path).unwrap();
        
        let job = Job::new("test".to_string(), "code".to_string(), "lang".to_string(), "backend".to_string());
        journal.log_job_submitted(&job).unwrap();
        
        let entries = journal.replay().unwrap();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].sequence, 1);
    }
}

// Made with Bob
