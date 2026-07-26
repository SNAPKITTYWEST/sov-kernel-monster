// Example: Using SEB Universe L7
//
// Run with: cargo run --example universe_demo

use seb_universe::{
    ArtifactManifest, ArtifactTier, CVMGate, CVMGateStep, Invariant, ProofMetadata, TestMetadata,
    Universe,
};
use chrono::Utc;

#[tokio::main]
async fn main() {
    println!("=== SEB L7 Universe Substrate Demo ===\n");

    // 1. Load repository
    println!("1. Loading repository...");
    let mut universe = Universe::new();

    // Add T0 artifacts (foundational)
    let blake3 = ArtifactManifest::new(
        "blake3_core".into(),
        "Blake3 Hash".into(),
        "1.5.0".into(),
        "rust",
        0,
    )
    .with_source_path("seb/kernel/blake3.rs".into())
    .add_invariant(
        Invariant::new(
            "collision_resistant".into(),
            "Must resist collisions".into(),
        )
        .with_proof("blake3_proof".into()),
    );

    let mmap = ArtifactManifest::new(
        "mmap_arena".into(),
        "Memory-Mapped Arena".into(),
        "1.0.0".into(),
        "rust",
        0,
    )
    .add_invariant(
        Invariant::new(
            "memory_safety".into(),
            "Must prevent use-after-free".into(),
        )
        .with_proof("mmap_proof".into()),
    );

    universe.add_artifact(blake3.clone());
    universe.add_artifact(mmap.clone());

    // Add T1 artifact (core infrastructure)
    let append_log = ArtifactManifest::new(
        "append_only_log".into(),
        "Append-Only Log".into(),
        "1.0.0".into(),
        "rust",
        1,
    )
    .add_invariant(
        Invariant::new("immutability".into(), "Cannot modify entries".into())
            .with_proof("worm_immutability".into()),
    );

    universe.add_artifact(append_log.clone());

    println!("Loaded {} artifacts\n", universe.get_all().len());

    // 2. Query by tier
    println!("2. Querying by tier:");
    let t0 = universe.get_t0();
    let t1 = universe.get_t1();
    println!("   T0 artifacts: {}", t0.len());
    println!("   T1 artifacts: {}\n", t1.len());

    // 3. Query by invariant
    println!("3. Querying by invariant:");
    let collision_resistant = universe.query_by_invariant("collision_resistant");
    println!("   Artifacts with 'collision_resistant': {}\n", collision_resistant.len());

    // 4. Search by name
    println!("4. Searching by name:");
    let hash_artifacts = universe.search_by_name("hash");
    println!("   Found {} artifacts matching 'hash'\n", hash_artifacts.len());

    // 5. Query by language
    println!("5. Querying by language:");
    let rust_artifacts = universe.query_by_language("rust");
    println!("   Rust artifacts: {}\n", rust_artifacts.len());

    // 6. Get statistics
    println!("6. Repository statistics:");
    let stats = universe.statistics();
    println!("   Total artifacts: {}", stats.get("total_artifacts").unwrap());
    println!("   T0 count: {}", stats.get("t0_count").unwrap());
    println!("   T1 count: {}", stats.get("t1_count").unwrap());
    println!("   Languages: {}\n", stats.get("languages").unwrap());

    // 7. Create and process new artifact through CVMGate
    println!("7. Processing new artifact through CVMGate:");
    let mut new_artifact = ArtifactManifest::new(
        "segment_rotation".into(),
        "Log Segment Rotation".into(),
        "1.0.0".into(),
        "rust",
        2, // T2 = proposal
    )
    .with_source_path("seb/kernel/segment_rotation.rs".into())
    .with_doc_url("https://example.com/docs".into())
    .add_invariant(
        Invariant::new(
            "rotation_atomicity".into(),
            "Rotation must be atomic".into(),
        )
        .with_proof("rotation_proof".into()),
    )
    .add_proof(ProofMetadata {
        id: "rotation_proof".into(),
        language: "lean4".into(),
        hash: "abc123def456".into(),
        created_at: Utc::now(),
    })
    .add_test(TestMetadata {
        id: "rotation_test".into(),
        framework: "cargo test".into(),
        pass_count: 42,
        last_run: Utc::now(),
    });

    let gate = CVMGate::new();
    match gate.process(&new_artifact).await {
        Ok(result) => {
            println!("   CVMGate result: {}", result.summary());
            println!("   Steps completed:");
            for step in &result.steps {
                println!(
                    "     - Step {}: {} ({}ms)",
                    step.step,
                    if step.passed { "PASS" } else { "FAIL" },
                    step.duration_ms
                );
            }

            if result.passed {
                println!("   All steps passed! ✓\n");

                // Mark as passed and add to universe
                new_artifact = new_artifact.mark_cvm_passed();
                universe.add_artifact(new_artifact);

                // Now we can promote T2 -> T1
                println!("8. Promoting artifact T2 -> T1:");
                let t2_artifacts = universe.get_t2();
                println!("   T2 artifacts: {}", t2_artifacts.len());

                if let Some(promotable) = t2_artifacts.first() {
                    match gate.promote(promotable).await {
                        Ok(promoted) => {
                            println!(
                                "   Promoted '{}' from {} to {}",
                                promoted.artifact_id, promotable.tier, promoted.tier
                            );
                        }
                        Err(e) => println!("   Promotion failed: {}", e),
                    }
                }
            }
        }
        Err(e) => println!("   CVMGate error: {}", e),
    }

    // 9. Final statistics
    println!("\n9. Final repository statistics:");
    let final_stats = universe.statistics();
    println!("   Total artifacts: {}", final_stats.get("total_artifacts").unwrap());
    println!("   T0 count: {}", final_stats.get("t0_count").unwrap());
    println!("   T1 count: {}", final_stats.get("t1_count").unwrap());
    println!("   T2 count: {}", final_stats.get("t2_count").unwrap());
    println!("   CVMGate passed: {}", final_stats.get("cvm_gate_passed").unwrap());

    println!("\n=== Demo Complete ===");
}
