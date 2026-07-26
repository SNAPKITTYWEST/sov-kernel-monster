use snapkitty_gitbucket::bucket::{MemoryBucket, WormSeal, Author, FileEntry};
use snapkitty_gitbucket::schema;

fn make_valid_bucket() -> MemoryBucket {
    MemoryBucket {
        id: "mem_000001".to_string(),
        git_hash: "a".repeat(40),
        parent_hash: "b".repeat(40),
        timestamp: "2026-07-02T18:45:00Z".to_string(),
        author: Author {
            id: "SnapKitty".to_string(),
            pubkey: "ed25519:test".to_string(),
        },
        branch: "main".to_string(),
        bucket_type: "implementation".to_string(),
        summary: "add feature".to_string(),
        keywords: vec![],
        entities: vec![],
        files: vec![],
        related: vec![],
        trust: "verified".to_string(),
        immutable: true,
        worm_seal: WormSeal {
            algorithm: "Ed25519".to_string(),
            signature: "a".repeat(128),
            signer: "Plasma_Gate".to_string(),
            audit_ref: "550e8400-e29b-41d4-a716-446655440000".to_string(),
        },
    }
}

#[test]
fn test_valid_bucket_passes() {
    let bucket = make_valid_bucket();
    assert!(schema::validate_bucket(&bucket).is_ok());
}

#[test]
fn test_invalid_id_format() {
    let mut bucket = make_valid_bucket();
    bucket.id = "bad_id".to_string();
    let errors = schema::validate_bucket(&bucket).unwrap_err();
    assert!(errors.iter().any(|e| e.contains("Invalid id format")));
}

#[test]
fn test_invalid_type() {
    let mut bucket = make_valid_bucket();
    bucket.bucket_type = "invalid".to_string();
    let errors = schema::validate_bucket(&bucket).unwrap_err();
    assert!(errors.iter().any(|e| e.contains("Invalid type")));
}

#[test]
fn test_invalid_trust() {
    let mut bucket = make_valid_bucket();
    bucket.trust = "unknown".to_string();
    let errors = schema::validate_bucket(&bucket).unwrap_err();
    assert!(errors.iter().any(|e| e.contains("Invalid trust")));
}

#[test]
fn test_not_immutable() {
    let mut bucket = make_valid_bucket();
    bucket.immutable = false;
    let errors = schema::validate_bucket(&bucket).unwrap_err();
    assert!(errors.iter().any(|e| e.contains("immutable")));
}

#[test]
fn test_schema_constants() {
    assert_eq!(schema::SCHEMA_VERSION, "memory_bucket_v1");
    assert!(schema::VALID_TYPES.contains(&"implementation"));
    assert!(schema::VALID_TRUST.contains(&"verified"));
    assert!(schema::VALID_ROLES.contains(&"core"));
}
