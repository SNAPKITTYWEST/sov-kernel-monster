# ADR-010: Execution Receipt and Provenance System

**Status**: ACCEPTED  
**Date**: 2026-07-21  
**Deciders**: Bob (ROLE-SYSTEM-ARCHITECT), ROLE-INTEGRATOR  
**Related**: ADR-000, ADR-008

---

## Context

Quantum computation requires **verifiable provenance**:
- What circuit was executed?
- On what hardware?
- With what compilation?
- What were the results?
- Can we reproduce it?

Traditional systems lack:
1. **Immutability**: Results can be modified
2. **Traceability**: Compilation steps unclear
3. **Reproducibility**: Cannot replay execution
4. **Auditability**: No cryptographic proof

QATAAUM must provide **cryptographically verifiable execution receipts**.

## Decision

We implement a **Merkle-Tree-Based Receipt System** with:

### 1. Immutable Execution Chain
Every execution produces a receipt linking:
- Source code hash
- Compilation artifacts
- Target configuration
- Execution parameters
- Results
- Timestamps
- Previous receipt (chain)

### 2. Cryptographic Verification
Each receipt contains:
- SHA-256 hashes of all inputs
- Merkle root of execution trace
- Digital signature (optional)
- Verification metadata

### 3. Deterministic Replay
Receipts enable:
- Exact reproduction of compilation
- Verification of results
- Audit trail reconstruction
- Dispute resolution

## Receipt Structure

### Core Receipt

```rust
pub struct ExecutionReceipt {
    /// Unique receipt identifier
    pub receipt_id: ReceiptId,
    
    /// Receipt version
    pub version: u32,
    
    /// Timestamp (UTC)
    pub timestamp: Timestamp,
    
    /// Previous receipt in chain (if any)
    pub previous_receipt: Option<ReceiptId>,
    
    /// Source code
    pub source: SourceArtifact,
    
    /// Compilation
    pub compilation: CompilationArtifact,
    
    /// Execution
    pub execution: ExecutionArtifact,
    
    /// Results
    pub results: ResultsArtifact,
    
    /// Merkle root of entire receipt
    pub merkle_root: Hash,
    
    /// Optional signature
    pub signature: Option<Signature>,
}

pub struct SourceArtifact {
    pub language: String,           // "OpenQASM 2", "MetaQASM-4"
    pub source_code: String,
    pub source_hash: Hash,
    pub line_count: usize,
}

pub struct CompilationArtifact {
    pub compiler_version: String,
    pub optimization_level: u8,
    pub target_profile: ProcessorProfile,
    pub compilation_time: Duration,
    pub ir_hashes: Vec<(String, Hash)>,  // (IR level, hash)
    pub final_circuit_hash: Hash,
    pub gate_count: usize,
    pub depth: usize,
    pub swap_count: usize,
}

pub struct ExecutionArtifact {
    pub execution_mode: ExecutionMode,  // Simulator, Hardware
    pub backend: String,
    pub shots: usize,
    pub execution_time: Duration,
    pub execution_hash: Hash,
}

pub struct ResultsArtifact {
    pub measurements: HashMap<String, Vec<u8>>,
    pub counts: HashMap<String, usize>,
    pub metadata: HashMap<String, String>,
    pub results_hash: Hash,
}
```

### Merkle Tree Construction

```
                    Merkle Root
                   /            \
            Branch A              Branch B
           /        \            /        \
      Source    Compilation  Execution  Results
        |           |            |          |
    source_hash  ir_hashes  exec_hash  results_hash
```

**Algorithm**:
```rust
pub fn compute_merkle_root(receipt: &ExecutionReceipt) -> Hash {
    let source_leaf = hash(&receipt.source);
    let compilation_leaf = hash(&receipt.compilation);
    let execution_leaf = hash(&receipt.execution);
    let results_leaf = hash(&receipt.results);
    
    let branch_a = hash(&[source_leaf, compilation_leaf]);
    let branch_b = hash(&[execution_leaf, results_leaf]);
    
    hash(&[branch_a, branch_b])
}
```

## Receipt Chain

### Chain Structure

```
Receipt 0 (Genesis)
    ↓
Receipt 1 (previous: 0)
    ↓
Receipt 2 (previous: 1)
    ↓
Receipt 3 (previous: 2)
```

### Chain Verification

```rust
pub fn verify_chain(receipts: &[ExecutionReceipt]) -> Result<(), ChainError> {
    // Verify genesis
    if receipts[0].previous_receipt.is_some() {
        return Err(ChainError::InvalidGenesis);
    }
    
    // Verify links
    for i in 1..receipts.len() {
        let prev_id = receipts[i].previous_receipt
            .ok_or(ChainError::BrokenChain)?;
        
        if prev_id != receipts[i-1].receipt_id {
            return Err(ChainError::InvalidLink);
        }
    }
    
    // Verify hashes
    for receipt in receipts {
        let computed = compute_merkle_root(receipt);
        if computed != receipt.merkle_root {
            return Err(ChainError::InvalidHash);
        }
    }
    
    Ok(())
}
```

## Deterministic Replay

### Replay Protocol

**Input**: Execution receipt

**Process**:
1. **Verify Receipt**: Check merkle root and signature
2. **Extract Source**: Retrieve source code
3. **Recompile**: Use same compiler version and settings
4. **Verify IR**: Compare IR hashes at each level
5. **Re-execute**: Run with same parameters
6. **Compare Results**: Verify results match (within statistical bounds)

**Output**: Verification status

### Example

```rust
pub fn replay_execution(receipt: &ExecutionReceipt) -> Result<VerificationStatus, ReplayError> {
    // 1. Verify receipt
    verify_receipt(receipt)?;
    
    // 2. Parse source
    let source = &receipt.source.source_code;
    let ast = parse(source, &receipt.source.language)?;
    
    // 3. Recompile
    let compiler = Compiler::new(&receipt.compilation.compiler_version)?;
    let compiled = compiler.compile(
        ast,
        &receipt.compilation.target_profile,
        receipt.compilation.optimization_level,
    )?;
    
    // 4. Verify IR hashes
    for (level, expected_hash) in &receipt.compilation.ir_hashes {
        let actual_hash = hash(&compiled.get_ir(level)?);
        if actual_hash != *expected_hash {
            return Ok(VerificationStatus::CompilationMismatch {
                level: level.clone(),
                expected: *expected_hash,
                actual: actual_hash,
            });
        }
    }
    
    // 5. Re-execute
    let executor = Executor::new(&receipt.execution.backend)?;
    let results = executor.execute(
        &compiled,
        receipt.execution.shots,
    )?;
    
    // 6. Compare results
    let results_match = compare_results(
        &receipt.results,
        &results,
        receipt.execution.shots,
    )?;
    
    if results_match {
        Ok(VerificationStatus::Verified)
    } else {
        Ok(VerificationStatus::ResultsMismatch)
    }
}
```

## Receipt Storage

### Storage Formats

**JSON** (Human-readable):
```json
{
  "receipt_id": "0x1234...",
  "version": 1,
  "timestamp": "2026-07-21T21:48:00Z",
  "source": {
    "language": "OpenQASM 2",
    "source_hash": "0xabcd...",
    "line_count": 10
  },
  "merkle_root": "0x5678..."
}
```

**Binary** (Compact):
- CBOR encoding
- Protobuf encoding
- Custom binary format

### Storage Backends

1. **Local Filesystem**: `.qataaum/receipts/`
2. **Database**: SQLite, PostgreSQL
3. **Distributed**: IPFS, Arweave (future)
4. **IBM i Journal**: Native journaling

## Signature Support

### Optional Signing

```rust
pub struct Signature {
    pub algorithm: String,      // "Ed25519", "ECDSA"
    pub public_key: Vec<u8>,
    pub signature: Vec<u8>,
}

pub fn sign_receipt(
    receipt: &ExecutionReceipt,
    private_key: &PrivateKey,
) -> Signature {
    let message = receipt.merkle_root.as_bytes();
    let signature = private_key.sign(message);
    
    Signature {
        algorithm: "Ed25519".to_string(),
        public_key: private_key.public_key().to_bytes(),
        signature: signature.to_bytes(),
    }
}

pub fn verify_signature(
    receipt: &ExecutionReceipt,
) -> Result<bool, SignatureError> {
    let sig = receipt.signature.as_ref()
        .ok_or(SignatureError::NoSignature)?;
    
    let public_key = PublicKey::from_bytes(&sig.public_key)?;
    let message = receipt.merkle_root.as_bytes();
    
    Ok(public_key.verify(message, &sig.signature))
}
```

## Rationale

### Why Merkle Trees?

1. **Efficient Verification**: O(log n) proof size
2. **Tamper-Evident**: Any change invalidates root
3. **Partial Disclosure**: Can prove subset without revealing all
4. **Standard**: Well-understood cryptographic primitive

### Why Receipt Chains?

1. **Auditability**: Complete execution history
2. **Reproducibility**: Can replay any execution
3. **Traceability**: Track evolution of experiments
4. **Accountability**: Cryptographic proof of execution

### Why Optional Signatures?

1. **Flexibility**: Not all executions need signing
2. **Performance**: Signing adds overhead
3. **Use Cases**: Required for production, optional for research

## Consequences

### Positive

1. **Verifiable**: Cryptographic proof of execution
2. **Reproducible**: Can replay any execution
3. **Auditable**: Complete execution history
4. **Tamper-Evident**: Cannot modify without detection

### Negative

1. **Storage**: Receipts consume disk space
2. **Overhead**: Hashing and signing add latency
3. **Complexity**: Receipt management requires infrastructure

### Mitigation

- **Compression**: Compress receipts for storage
- **Pruning**: Archive old receipts
- **Optimization**: Efficient hashing algorithms

## Implementation Plan

**Phase 1** (PENDING):
- ⏳ Define receipt data structures
- ⏳ Implement Merkle tree construction
- ⏳ Create receipt serialization

**Phase 2** (PENDING):
- ⏳ Implement receipt generation
- ⏳ Create receipt storage backends
- ⏳ Add receipt verification

**Phase 3** (PENDING):
- ⏳ Implement deterministic replay
- ⏳ Add signature support
- ⏳ Create receipt chain verification

**Phase 4** (PENDING):
- ⏳ Receipt query interface
- ⏳ Receipt export/import
- ⏳ Receipt visualization

## Security Considerations

### Threat Model

**Threats**:
1. **Receipt Tampering**: Attacker modifies receipt
2. **Replay Attacks**: Attacker replays old receipt
3. **Forgery**: Attacker creates fake receipt
4. **Denial of Service**: Attacker floods with receipts

**Mitigations**:
1. **Merkle Root**: Detects tampering
2. **Timestamps**: Detects replay
3. **Signatures**: Prevents forgery
4. **Rate Limiting**: Prevents DoS

### Privacy Considerations

**Sensitive Data**:
- Source code may be proprietary
- Results may be confidential
- Execution parameters may reveal strategy

**Solutions**:
- **Selective Disclosure**: Share only necessary fields
- **Encryption**: Encrypt sensitive fields
- **Access Control**: Restrict receipt access

## Alternatives Considered

### Alternative 1: No Receipts
**Rejected**: Cannot verify or reproduce executions

### Alternative 2: Simple Hashing
**Rejected**: No tamper-evidence or chain verification

### Alternative 3: Blockchain
**Rejected**: Overkill for single-user system, can add later

## Related Decisions

- **ADR-000**: Architecture Foundation
- **ADR-008**: IBM i Integration (journaling)

---

**Decision**: ACCEPTED  
**Architect**: Bob (ROLE-SYSTEM-ARCHITECT)  
**Date**: 2026-07-21

// Made with Bob