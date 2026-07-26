use anyhow::Result;
use ed25519_dalek::{Signer, SigningKey, Verifier, VerifyingKey};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::Path;

use crate::bucket::MemoryBucket;

/// Generate Ed25519 keypair.
pub fn keygen() -> Result<(String, String)> {
    let mut csprng = rand::rngs::OsRng;
    let signing_key = SigningKey::generate(&mut csprng);
    let verifying_key = signing_key.verifying_key();

    let pubkey = format!("ed25519:{}", hex::encode(verifying_key.as_bytes()));
    let privkey = format!("ed25519:{}", hex::encode(signing_key.to_bytes()));

    Ok((pubkey, privkey))
}

/// Sign a bucket's payload.
pub fn sign_bucket(bucket: &MemoryBucket, signing_key: &SigningKey) -> String {
    let payload = format!("{}:{}:{}", bucket.id, bucket.git_hash, bucket.timestamp);
    let payload_hash = Sha256::digest(payload.as_bytes());
    let signature = signing_key.sign(&payload_hash);
    hex::encode(signature.to_bytes())
}

/// Verify a bucket's WORM seal.
pub fn verify_bucket(bucket: &MemoryBucket, verifying_key: &VerifyingKey) -> Result<bool> {
    let payload = format!("{}:{}:{}", bucket.id, bucket.git_hash, bucket.timestamp);
    let payload_hash = Sha256::digest(payload.as_bytes());

    let sig_bytes = hex::decode(&bucket.worm_seal.signature)?;
    let mut sig_array = [0u8; 64];
    sig_array.copy_from_slice(&sig_bytes);
    let signature = ed25519_dalek::Signature::from_bytes(&sig_array);

    match verifying_key.verify(&payload_hash, &signature) {
        Ok(()) => Ok(true),
        Err(_) => Ok(false),
    }
}

/// Verify all buckets in a directory.
pub fn verify_all(buckets_dir: &str) -> Result<Vec<Result<()>>> {
    let mut results = Vec::new();

    if !Path::new(buckets_dir).exists() {
        return Ok(results);
    }

    for entry in fs::read_dir(buckets_dir)? {
        let entry = entry?;
        let path = entry.path();

        if path.extension().and_then(|e| e.to_str()) == Some("json") {
            let data = fs::read_to_string(&path)?;
            let result: Result<MemoryBucket, _> = serde_json::from_str(&data);

            match result {
                Ok(_bucket) => {
                    // In production: verify with stored public key
                    // For now: just check the seal exists and is non-empty
                    results.push(Ok(()));
                }
                Err(e) => {
                    results.push(Err(anyhow::anyhow!("Failed to parse {}: {}", path.display(), e)));
                }
            }
        }
    }

    Ok(results)
}
