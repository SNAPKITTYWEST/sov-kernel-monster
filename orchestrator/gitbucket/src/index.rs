use anyhow::Result;
use std::collections::HashMap;
use std::fs;
use std::path::Path;

use crate::bucket::MemoryBucket;

/// In-memory index of all buckets.
pub struct Index {
    pub by_id: HashMap<String, MemoryBucket>,
    pub by_file: HashMap<String, Vec<String>>,
    pub by_entity: HashMap<String, Vec<String>>,
    pub by_topic: HashMap<String, Vec<String>>,
    pub by_type: HashMap<String, Vec<String>>,
    pub by_agent: HashMap<String, Vec<String>>,
}

impl Index {
    /// Build index from bucket directory.
    pub fn from_dir(buckets_dir: &str) -> Result<Self> {
        let mut index = Index {
            by_id: HashMap::new(),
            by_file: HashMap::new(),
            by_entity: HashMap::new(),
            by_topic: HashMap::new(),
            by_type: HashMap::new(),
            by_agent: HashMap::new(),
        };

        if !Path::new(buckets_dir).exists() {
            return Ok(index);
        }

        for entry in fs::read_dir(buckets_dir)? {
            let entry = entry?;
            let path = entry.path();

            if path.extension().and_then(|e| e.to_str()) == Some("json") {
                let data = fs::read_to_string(&path)?;
                if let Ok(bucket) = serde_json::from_str::<MemoryBucket>(&data) {
                    index.insert(bucket.clone());
                }
            }
        }

        Ok(index)
    }

    /// Insert a bucket into the index.
    pub fn insert(&mut self, bucket: MemoryBucket) {
        let id = bucket.id.clone();

        // Index by file
        for file in &bucket.files {
            self.by_file
                .entry(file.path.clone())
                .or_default()
                .push(id.clone());
        }

        // Index by entity
        for entity in &bucket.entities {
            self.by_entity
                .entry(entity.clone())
                .or_default()
                .push(id.clone());
        }

        // Index by topic (keywords)
        for keyword in &bucket.keywords {
            self.by_topic
                .entry(keyword.clone())
                .or_default()
                .push(id.clone());
        }

        // Index by type
        self.by_type
            .entry(bucket.bucket_type.clone())
            .or_default()
            .push(id.clone());

        // Index by agent
        self.by_agent
            .entry(bucket.author.id.clone())
            .or_default()
            .push(id.clone());

        self.by_id.insert(id, bucket);
    }

    /// Query by field name and value.
    pub fn query(&self, field: &str, value: &str) -> Vec<&MemoryBucket> {
        let ids = match field {
            "topic" | "keyword" => self.by_topic.get(value),
            "file" => self.by_file.get(value),
            "entity" => self.by_entity.get(value),
            "type" => self.by_type.get(value),
            "agent" => self.by_agent.get(value),
            _ => return Vec::new(),
        };

        match ids {
            Some(id_list) => id_list
                .iter()
                .filter_map(|id| self.by_id.get(id))
                .collect(),
            None => Vec::new(),
        }
    }
}
