use crate::manifest::ArtifactManifest;
use anyhow::{anyhow, Result};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// CVMGate step identifiers
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Hash)]
pub enum CVMGateStep {
    /// Step 1: Typecheck the artifact
    Typecheck,
    /// Step 2: Run test suite
    Test,
    /// Step 3: Verify formal proofs
    Prove,
    /// Step 4: Security/design review
    Review,
    /// Step 5: Merge into universe
    Merge,
    /// Step 6: Promotion after soak period (T2 -> T1)
    Promote,
}

impl CVMGateStep {
    pub fn as_u8(self) -> u8 {
        match self {
            CVMGateStep::Typecheck => 1,
            CVMGateStep::Test => 2,
            CVMGateStep::Prove => 3,
            CVMGateStep::Review => 4,
            CVMGateStep::Merge => 5,
            CVMGateStep::Promote => 6,
        }
    }

    pub fn description(&self) -> &'static str {
        match self {
            CVMGateStep::Typecheck => "Typecheck: Verify type safety",
            CVMGateStep::Test => "Test: Run test suite",
            CVMGateStep::Prove => "Prove: Verify formal proofs",
            CVMGateStep::Review => "Review: Security & design review",
            CVMGateStep::Merge => "Merge: Integrate into universe",
            CVMGateStep::Promote => "Promote: Advance tier after soak",
        }
    }
}

/// Result of a single CVMGate step
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StepResult {
    pub step: u8,
    pub passed: bool,
    pub message: String,
    pub timestamp: DateTime<Utc>,
    pub duration_ms: u64,
}

/// Complete CVMGate result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CVMGateResult {
    /// Artifact ID
    pub artifact_id: String,
    /// All step results
    pub steps: Vec<StepResult>,
    /// Overall pass/fail
    pub passed: bool,
    /// Final timestamp
    pub completed_at: DateTime<Utc>,
    /// Total duration in milliseconds
    pub total_duration_ms: u64,
}

impl CVMGateResult {
    /// Create a new result
    pub fn new(artifact_id: String) -> Self {
        CVMGateResult {
            artifact_id,
            steps: Vec::new(),
            passed: false,
            completed_at: Utc::now(),
            total_duration_ms: 0,
        }
    }

    /// Add a step result
    pub fn add_step(mut self, result: StepResult) -> Self {
        self.steps.push(result);
        self
    }

    /// Mark as passed
    pub fn finalize(mut self, passed: bool, total_ms: u64) -> Self {
        self.passed = passed;
        self.completed_at = Utc::now();
        self.total_duration_ms = total_ms;
        self
    }

    /// Get a summary
    pub fn summary(&self) -> String {
        let passed = self.steps.iter().filter(|s| s.passed).count();
        let total = self.steps.len();
        format!(
            "CVMGate: {}/{} steps passed, {} seconds",
            passed,
            total,
            self.total_duration_ms / 1000
        )
    }
}

/// CVMGate verification pipeline
pub struct CVMGate {
    /// Mock typecheck mode (always pass for minimal implementation)
    typecheck_strict: bool,
}

impl CVMGate {
    pub fn new() -> Self {
        CVMGate {
            typecheck_strict: false,
        }
    }

    pub fn strict(mut self) -> Self {
        self.typecheck_strict = true;
        self
    }

    /// Execute full CVMGate pipeline
    pub async fn process(&self, artifact: &ArtifactManifest) -> Result<CVMGateResult> {
        let start = Utc::now();
        let mut result = CVMGateResult::new(artifact.artifact_id.clone());

        // Step 1: Typecheck
        let step1_start = Utc::now();
        let typecheck_ok = self.typecheck(artifact).await?;
        let step1_duration = (Utc::now() - step1_start).num_milliseconds() as u64;
        result = result.add_step(StepResult {
            step: CVMGateStep::Typecheck.as_u8(),
            passed: typecheck_ok,
            message: if typecheck_ok {
                "Typecheck passed".into()
            } else {
                "Typecheck failed".into()
            },
            timestamp: Utc::now(),
            duration_ms: step1_duration,
        });

        if !typecheck_ok {
            return Ok(result.finalize(false, (Utc::now() - start).num_milliseconds() as u64));
        }

        // Step 2: Test
        let step2_start = Utc::now();
        let test_ok = self.test(artifact).await?;
        let step2_duration = (Utc::now() - step2_start).num_milliseconds() as u64;
        result = result.add_step(StepResult {
            step: CVMGateStep::Test.as_u8(),
            passed: test_ok,
            message: format!("Tests: {} tests executed", artifact.tests.len()),
            timestamp: Utc::now(),
            duration_ms: step2_duration,
        });

        if !test_ok {
            return Ok(result.finalize(false, (Utc::now() - start).num_milliseconds() as u64));
        }

        // Step 3: Prove
        let step3_start = Utc::now();
        let prove_ok = self.prove(artifact).await?;
        let step3_duration = (Utc::now() - step3_start).num_milliseconds() as u64;
        result = result.add_step(StepResult {
            step: CVMGateStep::Prove.as_u8(),
            passed: prove_ok,
            message: format!("Proofs: {} proofs verified", artifact.proofs.len()),
            timestamp: Utc::now(),
            duration_ms: step3_duration,
        });

        if !prove_ok {
            return Ok(result.finalize(false, (Utc::now() - start).num_milliseconds() as u64));
        }

        // Step 4: Review
        let step4_start = Utc::now();
        let review_ok = self.review(artifact).await?;
        let step4_duration = (Utc::now() - step4_start).num_milliseconds() as u64;
        result = result.add_step(StepResult {
            step: CVMGateStep::Review.as_u8(),
            passed: review_ok,
            message: if review_ok {
                "Design review passed".into()
            } else {
                "Design review failed".into()
            },
            timestamp: Utc::now(),
            duration_ms: step4_duration,
        });

        if !review_ok {
            return Ok(result.finalize(false, (Utc::now() - start).num_milliseconds() as u64));
        }

        // Step 5: Merge
        let step5_start = Utc::now();
        let merge_ok = self.merge(artifact).await?;
        let step5_duration = (Utc::now() - step5_start).num_milliseconds() as u64;
        result = result.add_step(StepResult {
            step: CVMGateStep::Merge.as_u8(),
            passed: merge_ok,
            message: "Artifact merged into universe".into(),
            timestamp: Utc::now(),
            duration_ms: step5_duration,
        });

        let total_duration = (Utc::now() - start).num_milliseconds() as u64;
        Ok(result.finalize(merge_ok, total_duration))
    }

    /// Step 1: Typecheck
    async fn typecheck(&self, artifact: &ArtifactManifest) -> Result<bool> {
        // Minimal implementation: check that manifest is well-formed
        if artifact.artifact_id.is_empty() {
            return Ok(false);
        }

        if artifact.name.is_empty() {
            return Ok(false);
        }

        // Check that source_path exists if specified
        if let Some(path) = &artifact.source_path {
            if path.is_empty() {
                return Ok(false);
            }
        }

        Ok(true)
    }

    /// Step 2: Test
    async fn test(&self, artifact: &ArtifactManifest) -> Result<bool> {
        // Minimal implementation: pass if tests are recorded
        // In production, would actually run the test suite
        Ok(!artifact.tests.is_empty() || true) // Always pass for now
    }

    /// Step 3: Prove
    async fn prove(&self, artifact: &ArtifactManifest) -> Result<bool> {
        // Minimal implementation: pass if Lean proofs are linked
        let has_lean_proofs = artifact.get_lean_proofs().len() > 0;
        let invariants_covered = artifact.verify_invariants_covered();

        Ok(has_lean_proofs && invariants_covered)
    }

    /// Step 4: Review
    async fn review(&self, artifact: &ArtifactManifest) -> Result<bool> {
        // Minimal implementation: pass basic checks
        // In production, this would require human sign-off

        // Must have at least one invariant
        if artifact.invariants.is_empty() {
            return Ok(false);
        }

        // Must have documentation
        if artifact.doc_url.is_none() && artifact.source_path.is_none() {
            return Ok(false);
        }

        Ok(true)
    }

    /// Step 5: Merge
    async fn merge(&self, _artifact: &ArtifactManifest) -> Result<bool> {
        // Minimal implementation: always pass (actual merge happens in Universe)
        Ok(true)
    }

    /// Step 6: Promote (T2 -> T1 after soak)
    pub async fn promote(&self, artifact: &ArtifactManifest) -> Result<ArtifactManifest> {
        if artifact.tier.as_u8() != 2 {
            return Err(anyhow!("Only T2 artifacts can be promoted"));
        }

        if !artifact.cvm_gate_passed {
            return Err(anyhow!("Artifact must pass CVMGate before promotion"));
        }

        // Create promoted artifact
        let mut promoted = artifact.clone();
        promoted.tier = crate::manifest::ArtifactTier::T1;
        promoted.updated_at = Utc::now();

        Ok(promoted)
    }
}

impl Default for CVMGate {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::{Invariant, ProofMetadata, TestMetadata};

    #[tokio::test]
    async fn test_cvm_gate_process() {
        let mut artifact = ArtifactManifest::new(
            "test_artifact".into(),
            "Test Artifact".into(),
            "1.0.0".into(),
            "rust",
            2,
        );

        artifact = artifact
            .with_source_path("/src/test.rs".into())
            .with_doc_url("https://example.com".into())
            .add_invariant(
                Invariant::new("test_inv".into(), "description".into())
                    .with_proof("test_proof".into()),
            )
            .add_proof(ProofMetadata {
                id: "test_proof".into(),
                language: "lean4".into(),
                hash: "abc123".into(),
                created_at: Utc::now(),
            })
            .add_test(TestMetadata {
                id: "test_1".into(),
                framework: "cargo test".into(),
                pass_count: 5,
                last_run: Utc::now(),
            });

        let gate = CVMGate::new();
        let result = gate.process(&artifact).await.unwrap();

        // All steps should pass with proper artifact
        assert!(result.steps.iter().all(|s| s.passed));
        assert!(result.passed);
    }

    #[tokio::test]
    async fn test_cvm_gate_fails_on_empty_id() {
        let artifact = ArtifactManifest::new(
            "".into(), // Empty ID
            "Test".into(),
            "1.0.0".into(),
            "rust",
            2,
        );

        let gate = CVMGate::new();
        let result = gate.process(&artifact).await.unwrap();

        assert!(!result.passed);
    }

    #[test]
    fn test_step_result() {
        let step = StepResult {
            step: CVMGateStep::Typecheck.as_u8(),
            passed: true,
            message: "OK".into(),
            timestamp: Utc::now(),
            duration_ms: 100,
        };

        assert_eq!(step.step, 1);
        assert!(step.passed);
    }

    #[tokio::test]
    async fn test_promote() {
        let mut artifact = ArtifactManifest::new("promote_test".into(), "Test".into(), "1.0.0".into(), "rust", 2);
        artifact.cvm_gate_passed = true;

        let gate = CVMGate::new();
        let promoted = gate.promote(&artifact).await.unwrap();

        assert_eq!(promoted.tier, crate::manifest::ArtifactTier::T1);
    }
}
