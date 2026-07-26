use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::Path;

use crate::index::Index;

#[derive(Debug, Serialize, Deserialize)]
pub struct ContextBundle {
    pub context: Context,
    pub audit: AuditTrail,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Context {
    pub buckets: Vec<ContextPiece>,
    pub total_tokens: usize,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ContextPiece {
    pub id: String,
    pub summary: String,
    #[serde(rename = "type")]
    pub piece_type: String,
    pub timestamp: String,
    pub files: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AuditTrail {
    pub query: QuerySpec,
    pub buckets: Vec<String>,
    pub verifier: String,
    pub timestamp: f64,
    pub count: usize,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct QuerySpec {
    pub field: String,
    pub value: String,
    pub budget: usize,
}

/// Query the index and build a context bundle.
pub fn query(field: &str, value: &str, budget: usize) -> Result<ContextBundle> {
    let buckets_dir = ".gitbucket/buckets";
    let index = if Path::new(buckets_dir).exists() {
        Index::from_dir(buckets_dir)?
    } else {
        Index {
            by_id: std::collections::HashMap::new(),
            by_file: std::collections::HashMap::new(),
            by_entity: std::collections::HashMap::new(),
            by_topic: std::collections::HashMap::new(),
            by_type: std::collections::HashMap::new(),
            by_agent: std::collections::HashMap::new(),
        }
    };

    let buckets = index.query(field, value);
    let bucket_ids: Vec<String> = buckets.iter().map(|b| b.id.clone()).collect();

    // Build context pieces within budget
    let mut pieces = Vec::new();
    let mut total_tokens = 0;

    for bucket in &buckets {
        let piece_tokens = estimate_tokens(bucket);
        if total_tokens + piece_tokens > budget {
            break;
        }

        pieces.push(ContextPiece {
            id: bucket.id.clone(),
            summary: bucket.summary.clone(),
            piece_type: bucket.bucket_type.clone(),
            timestamp: bucket.timestamp.clone(),
            files: bucket.files.iter().map(|f| f.path.clone()).collect(),
        });

        total_tokens += piece_tokens;
    }

    Ok(ContextBundle {
        context: Context {
            buckets: pieces,
            total_tokens,
        },
        audit: AuditTrail {
            query: QuerySpec {
                field: field.to_string(),
                value: value.to_string(),
                budget,
            },
            buckets: bucket_ids,
            verifier: "Plasma_Gate".to_string(),
            timestamp: chrono::Utc::now().timestamp() as f64,
            count: buckets.len(),
        },
    })
}

fn estimate_tokens(bucket: &crate::bucket::MemoryBucket) -> usize {
    bucket.summary.len() + bucket.files.len() * 50
}
