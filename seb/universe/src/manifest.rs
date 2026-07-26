use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Artifact tier in the universe
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Hash, PartialOrd, Ord)]
#[repr(u8)]
pub enum ArtifactTier {
    /// T0: Foundational (blake3, mmap_arena, u64_arithmetic)
    T0 = 0,
    /// T1: Core infrastructure (segment_rotation, append_only_log)
    T1 = 1,
    /// T2: Proposals (under verification)
    T2 = 2,
    /// T3: Quarantined/external (not trusted)
    T3 = 3,
}

impl ArtifactTier {
    pub fn as_u8(self) -> u8 {
        self as u8
    }

    pub fn from_u8(val: u8) -> Option<Self> {
        match val {
            0 => Some(ArtifactTier::T0),
            1 => Some(ArtifactTier::T1),
            2 => Some(ArtifactTier::T2),
            3 => Some(ArtifactTier::T3),
            _ => None,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            ArtifactTier::T0 => "T0",
            ArtifactTier::T1 => "T1",
            ArtifactTier::T2 => "T2",
            ArtifactTier::T3 => "T3",
        }
    }
}

impl std::fmt::Display for ArtifactTier {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

/// Language tag for artifact
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum Language {
    Rust,
    Lean4,
    Ada,
    PL1,
    Prolog,
    Haskell,
    Other(String),
}

impl Language {
    pub fn as_str(&self) -> &str {
        match self {
            Language::Rust => "rust",
            Language::Lean4 => "lean4",
            Language::Ada => "ada",
            Language::PL1 => "pl1",
            Language::Prolog => "prolog",
            Language::Haskell => "haskell",
            Language::Other(s) => s,
        }
    }

    pub fn from_str(s: &str) -> Self {
        match s {
            "rust" => Language::Rust,
            "lean4" => Language::Lean4,
            "ada" => Language::Ada,
            "pl1" => Language::PL1,
            "prolog" => Language::Prolog,
            "haskell" => Language::Haskell,
            other => Language::Other(other.to_string()),
        }
    }
}

/// Invariant that an artifact must preserve
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct Invariant {
    /// Invariant name
    pub name: String,
    /// Description
    pub description: String,
    /// Reference to Lean proof (if any)
    pub proof_reference: Option<String>,
}

impl Invariant {
    pub fn new(name: String, description: String) -> Self {
        Invariant {
            name,
            description,
            proof_reference: None,
        }
    }

    pub fn with_proof(mut self, proof_reference: String) -> Self {
        self.proof_reference = Some(proof_reference);
        self
    }
}

/// Proof metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProofMetadata {
    /// Proof identifier
    pub id: String,
    /// Language (Lean4, Coq, etc.)
    pub language: String,
    /// Hash of proof file
    pub hash: String,
    /// Timestamp
    pub created_at: DateTime<Utc>,
}

/// Test metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TestMetadata {
    /// Test identifier
    pub id: String,
    /// Test framework
    pub framework: String,
    /// Pass count
    pub pass_count: usize,
    /// Last run timestamp
    pub last_run: DateTime<Utc>,
}

/// Complete artifact manifest
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ArtifactManifest {
    /// Unique artifact identifier
    pub artifact_id: String,

    /// Human-readable name
    pub name: String,

    /// Semantic version
    pub version: String,

    /// Primary language
    pub language: Language,

    /// Artifact tier
    pub tier: ArtifactTier,

    /// Required invariants
    pub invariants: Vec<Invariant>,

    /// Associated proofs
    pub proofs: Vec<ProofMetadata>,

    /// Associated tests
    pub tests: Vec<TestMetadata>,

    /// Source file path (relative to repo root)
    pub source_path: Option<String>,

    /// Documentation URL
    pub doc_url: Option<String>,

    /// Blake3 content hash
    pub content_hash: String,

    /// CVMGate completion status
    #[serde(default)]
    pub cvm_gate_passed: bool,

    /// Metadata
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,

    /// Custom metadata
    #[serde(default)]
    pub metadata: HashMap<String, serde_json::Value>,
}

impl ArtifactManifest {
    /// Create a new artifact manifest
    pub fn new(
        artifact_id: String,
        name: String,
        version: String,
        language: &str,
        tier: u8,
    ) -> Self {
        let tier_enum = ArtifactTier::from_u8(tier).unwrap_or(ArtifactTier::T2);

        ArtifactManifest {
            artifact_id,
            name,
            version,
            language: Language::from_str(language),
            tier: tier_enum,
            invariants: Vec::new(),
            proofs: Vec::new(),
            tests: Vec::new(),
            source_path: None,
            doc_url: None,
            content_hash: String::new(),
            cvm_gate_passed: false,
            created_at: Utc::now(),
            updated_at: Utc::now(),
            metadata: HashMap::new(),
        }
    }

    /// Add an invariant
    pub fn add_invariant(mut self, invariant: Invariant) -> Self {
        self.invariants.push(invariant);
        self
    }

    /// Add a proof
    pub fn add_proof(mut self, proof: ProofMetadata) -> Self {
        self.proofs.push(proof);
        self
    }

    /// Add a test
    pub fn add_test(mut self, test: TestMetadata) -> Self {
        self.tests.push(test);
        self
    }

    /// Set source path
    pub fn with_source_path(mut self, path: String) -> Self {
        self.source_path = Some(path);
        self
    }

    /// Set documentation URL
    pub fn with_doc_url(mut self, url: String) -> Self {
        self.doc_url = Some(url);
        self
    }

    /// Compute content hash (Blake3)
    pub fn compute_hash(&mut self, content: &[u8]) {
        self.content_hash = blake3::hash(content).to_hex().to_string();
        self.updated_at = Utc::now();
    }

    /// Verify that all required invariants have proofs
    pub fn verify_invariants_covered(&self) -> bool {
        self.invariants.iter().all(|inv| inv.proof_reference.is_some())
    }

    /// Get all Lean proof references
    pub fn get_lean_proofs(&self) -> Vec<&str> {
        self.proofs
            .iter()
            .filter(|p| p.language == "lean4")
            .map(|p| p.id.as_str())
            .collect()
    }

    /// Mark CVMGate as passed
    pub fn mark_cvm_passed(mut self) -> Self {
        self.cvm_gate_passed = true;
        self.updated_at = Utc::now();
        self
    }

    /// Convert to JSON-LD format
    pub fn to_json_ld(&self) -> serde_json::Value {
        serde_json::json!({
            "@context": "https://www.w3.org/ns/activitystreams",
            "@id": format!("artifact:{}", self.artifact_id),
            "@type": "Artifact",
            "name": self.name,
            "version": self.version,
            "tier": self.tier.as_str(),
            "language": self.language.as_str(),
            "invariants": self.invariants.iter().map(|i| {
                serde_json::json!({
                    "name": i.name,
                    "description": i.description,
                    "proof": i.proof_reference
                })
            }).collect::<Vec<_>>(),
            "proofs": self.proofs.len(),
            "tests": self.tests.len(),
            "hash": self.content_hash,
            "cvm_gate_passed": self.cvm_gate_passed,
            "created": self.created_at.to_rfc3339(),
            "updated": self.updated_at.to_rfc3339(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_artifact_creation() {
        let artifact = ArtifactManifest::new(
            "blake3_core".into(),
            "Blake3 Hash".into(),
            "1.5.0".into(),
            "rust",
            0,
        );

        assert_eq!(artifact.artifact_id, "blake3_core");
        assert_eq!(artifact.tier, ArtifactTier::T0);
        assert!(!artifact.cvm_gate_passed);
    }

    #[test]
    fn test_invariant_creation() {
        let inv = Invariant::new(
            "collision_resistant".into(),
            "Blake3 must be collision resistant".into(),
        )
        .with_proof("blake3_collision_proof".into());

        assert_eq!(inv.name, "collision_resistant");
        assert_eq!(inv.proof_reference, Some("blake3_collision_proof".into()));
    }

    #[test]
    fn test_tier_serialization() {
        assert_eq!(ArtifactTier::T0.as_u8(), 0);
        assert_eq!(ArtifactTier::from_u8(0), Some(ArtifactTier::T0));
        assert_eq!(ArtifactTier::T2.as_str(), "T2");
    }

    #[test]
    fn test_language_conversion() {
        assert_eq!(Language::Rust.as_str(), "rust");
        assert_eq!(Language::from_str("lean4"), Language::Lean4);
        assert_eq!(Language::from_str("unknown").as_str(), "unknown");
    }

    #[test]
    fn test_invariant_coverage() {
        let artifact = ArtifactManifest::new(
            "test".into(),
            "Test".into(),
            "1.0.0".into(),
            "rust",
            0,
        )
        .add_invariant(Invariant::new("test_inv".into(), "desc".into()));

        assert!(!artifact.verify_invariants_covered());

        let artifact = ArtifactManifest::new(
            "test".into(),
            "Test".into(),
            "1.0.0".into(),
            "rust",
            0,
        )
        .add_invariant(Invariant::new("test_inv".into(), "desc".into())
            .with_proof("test_proof".into()));

        assert!(artifact.verify_invariants_covered());
    }
}
