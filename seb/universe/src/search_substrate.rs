use crate::manifest::{ArtifactManifest, ArtifactTier};
use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Repository manifest format
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepositoryManifest {
    pub version: String,
    pub created_at: String,
    pub artifacts: HashMap<String, ArtifactManifest>,
}

impl RepositoryManifest {
    /// Create a new empty repository
    pub fn new() -> Self {
        RepositoryManifest {
            version: "1.0.0".into(),
            created_at: chrono::Utc::now().to_rfc3339(),
            artifacts: HashMap::new(),
        }
    }

    /// Add an artifact to the repository
    pub fn add_artifact(mut self, artifact: ArtifactManifest) -> Self {
        self.artifacts.insert(artifact.artifact_id.clone(), artifact);
        self
    }
}

impl Default for RepositoryManifest {
    fn default() -> Self {
        Self::new()
    }
}

/// Searchable universe of artifacts
pub struct Universe {
    artifacts: HashMap<String, ArtifactManifest>,
    /// Index: invariant_name -> artifact_ids
    invariant_index: HashMap<String, Vec<String>>,
    /// Index: tier -> artifact_ids
    tier_index: HashMap<ArtifactTier, Vec<String>>,
    /// Index: language -> artifact_ids
    language_index: HashMap<String, Vec<String>>,
}

impl Universe {
    /// Create an empty universe
    pub fn new() -> Self {
        Universe {
            artifacts: HashMap::new(),
            invariant_index: HashMap::new(),
            tier_index: HashMap::new(),
            language_index: HashMap::new(),
        }
    }

    /// Add an artifact and update indexes
    pub fn add_artifact(&mut self, artifact: ArtifactManifest) {
        let artifact_id = artifact.artifact_id.clone();
        let tier = artifact.tier;
        let language = artifact.language.as_str().to_string();

        // Add to main store
        self.artifacts.insert(artifact_id.clone(), artifact.clone());

        // Update tier index
        self.tier_index
            .entry(tier)
            .or_insert_with(Vec::new)
            .push(artifact_id.clone());

        // Update language index
        self.language_index
            .entry(language)
            .or_insert_with(Vec::new)
            .push(artifact_id.clone());

        // Update invariant index
        for invariant in &artifact.invariants {
            self.invariant_index
                .entry(invariant.name.clone())
                .or_insert_with(Vec::new)
                .push(artifact_id.clone());
        }
    }

    /// Query artifacts by invariant name
    pub fn query_by_invariant(&self, invariant: &str) -> Vec<ArtifactManifest> {
        self.invariant_index
            .get(invariant)
            .map(|ids| {
                ids.iter()
                    .filter_map(|id| self.artifacts.get(id).cloned())
                    .collect()
            })
            .unwrap_or_default()
    }

    /// Query artifacts by tier
    pub fn query_by_tier(&self, tier: ArtifactTier) -> Vec<ArtifactManifest> {
        self.tier_index
            .get(&tier)
            .map(|ids| {
                ids.iter()
                    .filter_map(|id| self.artifacts.get(id).cloned())
                    .collect()
            })
            .unwrap_or_default()
    }

    /// Query artifacts by language
    pub fn query_by_language(&self, language: &str) -> Vec<ArtifactManifest> {
        self.language_index
            .get(language)
            .map(|ids| {
                ids.iter()
                    .filter_map(|id| self.artifacts.get(id).cloned())
                    .collect()
            })
            .unwrap_or_default()
    }

    /// Get a specific artifact by ID
    pub fn get_artifact(&self, artifact_id: &str) -> Option<ArtifactManifest> {
        self.artifacts.get(artifact_id).cloned()
    }

    /// Get all artifacts
    pub fn get_all(&self) -> Vec<ArtifactManifest> {
        self.artifacts.values().cloned().collect()
    }

    /// Get all T0 artifacts (foundational)
    pub fn get_t0(&self) -> Vec<ArtifactManifest> {
        self.query_by_tier(ArtifactTier::T0)
    }

    /// Get all T1 artifacts (core infrastructure)
    pub fn get_t1(&self) -> Vec<ArtifactManifest> {
        self.query_by_tier(ArtifactTier::T1)
    }

    /// Get all T2 artifacts (proposals under verification)
    pub fn get_t2(&self) -> Vec<ArtifactManifest> {
        self.query_by_tier(ArtifactTier::T2)
    }

    /// Get all T3 artifacts (quarantined/external)
    pub fn get_t3(&self) -> Vec<ArtifactManifest> {
        self.query_by_tier(ArtifactTier::T3)
    }

    /// Search artifacts by name (substring match)
    pub fn search_by_name(&self, query: &str) -> Vec<ArtifactManifest> {
        let query_lower = query.to_lowercase();
        self.artifacts
            .values()
            .filter(|a| a.name.to_lowercase().contains(&query_lower))
            .cloned()
            .collect()
    }

    /// Load from JSON file
    pub async fn load_from_file(path: &str) -> Result<Self> {
        let content = tokio::fs::read_to_string(path).await?;
        let manifest: RepositoryManifest = serde_json::from_str(&content)?;

        let mut universe = Universe::new();
        for artifact in manifest.artifacts.values() {
            universe.add_artifact(artifact.clone());
        }

        Ok(universe)
    }

    /// Save to JSON file
    pub async fn save_to_file(&self, path: &str) -> Result<()> {
        let mut manifest = RepositoryManifest::new();
        for artifact in self.artifacts.values() {
            manifest = manifest.add_artifact(artifact.clone());
        }

        let json = serde_json::to_string_pretty(&manifest)?;
        tokio::fs::write(path, json).await?;
        Ok(())
    }

    /// Get statistics
    pub fn statistics(&self) -> HashMap<String, serde_json::Value> {
        let mut stats = HashMap::new();

        stats.insert(
            "total_artifacts".to_string(),
            serde_json::json!(self.artifacts.len()),
        );

        stats.insert(
            "t0_count".to_string(),
            serde_json::json!(self.get_t0().len()),
        );
        stats.insert(
            "t1_count".to_string(),
            serde_json::json!(self.get_t1().len()),
        );
        stats.insert(
            "t2_count".to_string(),
            serde_json::json!(self.get_t2().len()),
        );
        stats.insert(
            "t3_count".to_string(),
            serde_json::json!(self.get_t3().len()),
        );

        let cvm_passed = self.artifacts.values().filter(|a| a.cvm_gate_passed).count();
        stats.insert(
            "cvm_gate_passed".to_string(),
            serde_json::json!(cvm_passed),
        );

        stats.insert(
            "invariants".to_string(),
            serde_json::json!(self.invariant_index.len()),
        );

        stats.insert(
            "languages".to_string(),
            serde_json::json!(self.language_index.len()),
        );

        stats
    }
}

impl Default for Universe {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::Invariant;

    #[test]
    fn test_universe_creation() {
        let universe = Universe::new();
        assert_eq!(universe.artifacts.len(), 0);
    }

    #[test]
    fn test_add_artifact() {
        let mut universe = Universe::new();
        let artifact = ArtifactManifest::new(
            "blake3".into(),
            "Blake3 Hash".into(),
            "1.5.0".into(),
            "rust",
            0,
        );

        universe.add_artifact(artifact);
        assert_eq!(universe.artifacts.len(), 1);

        let t0 = universe.get_t0();
        assert_eq!(t0.len(), 1);
    }

    #[test]
    fn test_query_by_invariant() {
        let mut universe = Universe::new();
        let invariant = Invariant::new("collision_resistant".into(), "desc".into());
        let artifact = ArtifactManifest::new(
            "blake3".into(),
            "Blake3".into(),
            "1.0.0".into(),
            "rust",
            0,
        )
        .add_invariant(invariant);

        universe.add_artifact(artifact);

        let results = universe.query_by_invariant("collision_resistant");
        assert_eq!(results.len(), 1);
    }

    #[test]
    fn test_search_by_name() {
        let mut universe = Universe::new();
        let a1 = ArtifactManifest::new("blake3".into(), "Blake3 Hash".into(), "1.0.0".into(), "rust", 0);
        let a2 = ArtifactManifest::new("append_log".into(), "Append Only Log".into(), "1.0.0".into(), "rust", 1);

        universe.add_artifact(a1);
        universe.add_artifact(a2);

        let results = universe.search_by_name("blake");
        assert_eq!(results.len(), 1);
    }

    #[test]
    fn test_query_by_language() {
        let mut universe = Universe::new();
        let a1 = ArtifactManifest::new("proof1".into(), "Proof".into(), "1.0.0".into(), "lean4", 2);
        let a2 = ArtifactManifest::new("impl1".into(), "Implementation".into(), "1.0.0".into(), "rust", 0);

        universe.add_artifact(a1);
        universe.add_artifact(a2);

        let lean_artifacts = universe.query_by_language("lean4");
        assert_eq!(lean_artifacts.len(), 1);
        assert_eq!(lean_artifacts[0].artifact_id, "proof1");
    }

    #[test]
    fn test_statistics() {
        let mut universe = Universe::new();
        universe.add_artifact(ArtifactManifest::new("a1".into(), "A1".into(), "1.0.0".into(), "rust", 0));
        universe.add_artifact(ArtifactManifest::new("a2".into(), "A2".into(), "1.0.0".into(), "rust", 1));

        let stats = universe.statistics();
        assert_eq!(stats.get("total_artifacts").unwrap().as_u64().unwrap(), 2);
        assert_eq!(stats.get("t0_count").unwrap().as_u64().unwrap(), 1);
        assert_eq!(stats.get("t1_count").unwrap().as_u64().unwrap(), 1);
    }
}
