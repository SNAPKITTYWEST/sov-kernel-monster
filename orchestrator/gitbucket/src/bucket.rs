use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryBucket {
    pub id: String,
    pub git_hash: String,
    pub parent_hash: String,
    pub timestamp: String,
    pub author: Author,
    pub branch: String,
    #[serde(rename = "type")]
    pub bucket_type: String,
    pub summary: String,
    pub keywords: Vec<String>,
    pub entities: Vec<String>,
    pub files: Vec<FileEntry>,
    pub related: Vec<String>,
    pub trust: String,
    pub immutable: bool,
    pub worm_seal: WormSeal,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Author {
    pub id: String,
    pub pubkey: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileEntry {
    pub path: String,
    pub role: String,
    pub diff_hash: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WormSeal {
    pub algorithm: String,
    pub signature: String,
    pub signer: String,
    pub audit_ref: String,
}
