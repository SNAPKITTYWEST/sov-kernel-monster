/// Schema version for memory buckets.
pub const SCHEMA_VERSION: &str = "memory_bucket_v1";

/// Schema URL.
pub const SCHEMA_URL: &str = "https://snapkitty.os/schema/memory-bucket-v1.json";

/// Valid bucket types.
pub const VALID_TYPES: &[&str] = &[
    "architecture",
    "implementation",
    "decision",
    "repair",
    "audit",
    "fiscal_decision",
];

/// Valid trust levels.
pub const VALID_TRUST: &[&str] = &["verified", "pending", "disputed"];

/// Valid file roles.
pub const VALID_ROLES: &[&str] = &[
    "core",
    "new",
    "modified",
    "deleted",
    "config",
    "test",
    "doc",
];

/// Validate a bucket against the schema.
pub fn validate_bucket(bucket: &crate::bucket::MemoryBucket) -> Result<(), Vec<String>> {
    let mut errors = Vec::new();

    // Validate ID format
    if !bucket.id.starts_with("mem_") || bucket.id.len() != 10 {
        errors.push(format!("Invalid id format: {}", bucket.id));
    }

    // Validate git hash
    if bucket.git_hash.len() != 40 || !bucket.git_hash.chars().all(|c| c.is_ascii_hexdigit()) {
        errors.push(format!("Invalid git_hash: {}", bucket.git_hash));
    }

    // Validate type
    if !VALID_TYPES.contains(&bucket.bucket_type.as_str()) {
        errors.push(format!("Invalid type: {}", bucket.bucket_type));
    }

    // Validate trust
    if !VALID_TRUST.contains(&bucket.trust.as_str()) {
        errors.push(format!("Invalid trust: {}", bucket.trust));
    }

    // Validate worm seal
    if bucket.worm_seal.algorithm != "Ed25519" {
        errors.push(format!("Invalid worm_seal algorithm: {}", bucket.worm_seal.algorithm));
    }

    // Validate immutable
    if !bucket.immutable {
        errors.push("Buckets must be immutable".to_string());
    }

    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}
