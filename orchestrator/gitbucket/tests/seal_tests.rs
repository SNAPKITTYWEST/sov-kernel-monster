use snapkitty_gitbucket::bucket::{MemoryBucket, WormSeal, Author, FileEntry};
use snapkitty_gitbucket::seal;

fn make_test_bucket() -> MemoryBucket {
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
        summary: "add Ed25519 verification".to_string(),
        keywords: vec!["ed25519".to_string(), "verification".to_string()],
        entities: vec!["seal".to_string()],
        files: vec![FileEntry {
            path: "src/seal.rs".to_string(),
            role: "core".to_string(),
            diff_hash: "c".repeat(64),
        }],
        related: vec![],
        trust: "pending".to_string(),
        immutable: true,
        worm_seal: WormSeal {
            algorithm: "Ed25519".to_string(),
            signature: String::new(),
            signer: "Plasma_Gate".to_string(),
            audit_ref: "test-uuid".to_string(),
        },
    }
}

#[test]
fn test_keygen() {
    let (pubkey, privkey) = seal::keygen().unwrap();
    assert!(pubkey.starts_with("ed25519:"));
    assert!(privkey.starts_with("ed25519:"));
    assert_ne!(pubkey, privkey);
}

#[test]
fn test_sign_bucket() {
    let bucket = make_test_bucket();
    let (_, privkey_hex) = seal::keygen().unwrap();
    let privkey_bytes = hex::decode(privkey_hex.strip_prefix("ed25519:").unwrap()).unwrap();
    let mut key_bytes = [0u8; 32];
    key_bytes.copy_from_slice(&privkey_bytes);
    let signing_key = ed25519_dalek::SigningKey::from_bytes(&key_bytes);
    let sig = seal::sign_bucket(&bucket, &signing_key);
    assert_eq!(sig.len(), 128); // 64 bytes hex
}

#[test]
fn test_verify_bucket() {
    let bucket = make_test_bucket();
    let (pubkey_hex, privkey_hex) = seal::keygen().unwrap();
    let privkey_bytes = hex::decode(privkey_hex.strip_prefix("ed25519:").unwrap()).unwrap();
    let mut key_bytes = [0u8; 32];
    key_bytes.copy_from_slice(&privkey_bytes);
    let signing_key = ed25519_dalek::SigningKey::from_bytes(&key_bytes);
    let sig = seal::sign_bucket(&bucket, &signing_key);

    let mut sealed = bucket.clone();
    sealed.worm_seal.signature = sig;

    let pubkey_bytes = hex::decode(pubkey_hex.strip_prefix("ed25519:").unwrap()).unwrap();
    let mut vk_bytes = [0u8; 32];
    vk_bytes.copy_from_slice(&pubkey_bytes);
    let verifying_key = ed25519_dalek::VerifyingKey::from_bytes(&vk_bytes).unwrap();

    let valid = seal::verify_bucket(&sealed, &verifying_key).unwrap();
    assert!(valid);
}

#[test]
fn test_verify_rejects_tampered() {
    let bucket = make_test_bucket();
    let sig = "00".repeat(64);
    let mut sealed = bucket.clone();
    sealed.worm_seal.signature = sig;

    let (_, privkey_hex) = seal::keygen().unwrap();
    let privkey_bytes = hex::decode(privkey_hex.strip_prefix("ed25519:").unwrap()).unwrap();
    let mut key_bytes = [0u8; 32];
    key_bytes.copy_from_slice(&privkey_bytes);
    let signing_key = ed25519_dalek::SigningKey::from_bytes(&key_bytes);
    let verifying_key = signing_key.verifying_key();

    let valid = seal::verify_bucket(&sealed, &verifying_key).unwrap();
    assert!(!valid);
}
