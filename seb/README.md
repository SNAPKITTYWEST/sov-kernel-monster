# Sovereign Event Bus (SEB)

**Version:** 1.0.0  
**Status:** Scaffold Complete  
**Date:** 2026-07-25

## Overview

The Sovereign Event Bus (SEB) is a proof-carrying event coordination system that provides deterministic, verifiable event routing with cryptographic sealing and WORM chain integration. SEB replaces traditional message brokers with a fail-closed, evidence-based architecture.

## Core Principles

1. **Deterministic Routing** - All event routing is deterministic and reproducible
2. **Cryptographic Sealing** - Every event transition produces a Blake3 + Ed25519 seal
3. **WORM Integration** - Significant events are committed to immutable evidence chain
4. **Bounded Execution** - All handlers execute within strict time/memory/network limits
5. **Fail-Closed** - Deny by default, allow only with explicit proof

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Event Envelope                            │
│  (Intent + Context + Authority + Evidence + Seal)           │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                   Policy Gate                                │
│  (Pre-execution verification, MIRROR KITTY governance)      │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                  Routing Engine                              │
│  (Deterministic dispatch to adapters)                       │
└─────────────────────┬───────────────────────────────────────┘
                      │
        ┌─────────────┼─────────────┬─────────────┐
        ▼             ▼             ▼             ▼
   ┌────────┐   ┌────────┐   ┌────────┐   ┌────────┐
   │ HolyC  │   │ Shell  │   │Browser │   │ Chain  │
   │Adapter │   │Adapter │   │Adapter │   │Adapter │
   └────┬───┘   └────┬───┘   └────┬───┘   └────┬───┘
        │            │            │            │
        └────────────┴────────────┴────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                   WORM Sealer                                │
│  (Blake3 hash + Ed25519 signature + evidence chain)         │
└─────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
seb/
├── contracts/              # Contract templates for codegen
│   ├── rust.template
│   ├── typescript.template
│   ├── python.template
│   ├── lean4.template
│   └── openapi.template
├── scripts/
│   └── codegen/           # Code generation scripts
│       ├── generate_all.sh
│       ├── generate_rust.sh
│       ├── generate_typescript.sh
│       ├── generate_python.sh
│       ├── generate_lean4.sh
│       └── generate_openapi.sh
├── kernel/                # Rust kernel implementation (placeholder)
├── runtime/               # Runtime components (placeholder)
├── adapters/              # Execution adapters (placeholder)
├── clients/
│   ├── typescript/        # TypeScript client library
│   └── python/            # Python client library
├── verification/
│   └── lean4/             # Lean 4 formal verification
├── docs/
│   ├── spec/              # Specifications
│   ├── adr/               # Architecture Decision Records
│   └── api/               # API documentation
├── GenesisConfig.toml     # Genesis configuration with manifest hash
├── Makefile               # Build automation
└── README.md              # This file
```

## Quick Start

### 1. Verify Scaffold

```bash
cd seb
make scaffold-verify
```

This checks:
- Directory structure is complete
- All 5 contract templates are present
- All codegen scripts are executable
- Documentation exists
- Manifest hash is recorded

### 2. Generate Code

```bash
make codegen-all
```

This generates:
- `kernel/event_envelope.rs` - Rust types and traits
- `clients/typescript/index.ts` - TypeScript client
- `clients/python/seb_client.py` - Python client
- `verification/lean4/SEB.lean` - Lean 4 proofs
- `docs/api/openapi.yaml` - OpenAPI spec

### 3. Compute Manifest Hash

```bash
make hash-manifest
```

Computes SHA-256 hash of all contract templates for integrity verification.

## Contract Templates

### 1. Rust (`contracts/rust.template`)
- Core event envelope types
- Policy gate trait
- Routing engine trait
- Execution adapter trait
- Blake3 hashing and Ed25519 signing

### 2. TypeScript (`contracts/typescript.template`)
- Zod schemas for runtime validation
- Branded types for type safety
- Result type pattern
- SEBClient for API interaction

### 3. Python (`contracts/python.template`)
- Pydantic models with validation
- Async/await support
- Type hints throughout
- SEBClient for API interaction

### 4. Lean 4 (`contracts/lean4.template`)
- Formal specifications
- Safety properties (fail-closed, bounded execution)
- Cryptographic properties (seal validity)
- MIRROR KITTY governance properties
- Performance bounds

### 5. OpenAPI (`contracts/openapi.template`)
- REST API specification
- Event submission endpoint
- Status query endpoint
- Health check endpoint
- Complete schema definitions

## Architecture Decision Records

- [ADR-100: SEB Architecture Foundation](../ADRs/ADR-100-SEB-Architecture-Foundation.md)
- [ADR-101: Event Schema Design](../ADRs/ADR-101-SEB-Event-Schema-Design.md)
- [ADR-102: Routing Strategy](../ADRs/ADR-102-SEB-Routing-Strategy.md)
- [ADR-103: Cryptographic Sealing](../ADRs/ADR-103-SEB-Cryptographic-Sealing.md)
- [ADR-104: WORM Integration](../ADRs/ADR-104-SEB-WORM-Integration.md)

## Specifications

- [SEB Event V1 Specification](docs/spec/SEB_EVENT_V1.md)
- [Envelope Schema](docs/spec/ENVELOPE_SCHEMA.md)
- [Routing Rules](docs/spec/ROUTING_RULES.md)
- [Security Model](docs/spec/SECURITY_MODEL.md)

## Governance

SEB follows the **MIRROR KITTY Phase Mirror Governance** model:

1. **Be Impeccable with Your Word** - All outputs cryptographically sealed
2. **Don't Take Anything Personally** - Verification is agent-agnostic
3. **Don't Make Assumptions** - Evidence-based reasoning only
4. **Always Do Your Best** - Phi-decay bounded effort (φ⁻²)

See: [MIRROR KITTY Governance](../DEVFLOW-FINANCE/GOVERNANCE_FRAMEWORK.md)

## Performance Targets

| Metric | Target | Percentile |
|--------|--------|------------|
| Event Latency | <10ms | p99 |
| Throughput | >10,000 events/sec | single-node |
| Seal Latency | <5ms | p99 |
| Memory per Event | <1KB | envelope-only |

## Security

### Threat Model

- **Authority Spoofing** - Mitigated by Ed25519 signature verification
- **Replay Attacks** - Mitigated by nonce tracking and timestamp validation
- **Resource Exhaustion** - Mitigated by rate limiting and bounded execution
- **Injection Attacks** - Mitigated by schema validation and input sanitization

### Cryptography

- **Hash Function:** Blake3 (256-bit)
- **Signature Scheme:** Ed25519
- **Key Derivation:** HKDF-SHA256
- **Random Source:** Quantum entropy (when available) or OS CSPRNG

## Development

### Prerequisites

- Rust 1.70+ (for kernel development)
- Node.js 18+ (for TypeScript client)
- Python 3.10+ (for Python client)
- Lean 4 (for formal verification)
- Make (for build automation)

### Testing

```bash
# Test contract templates
make test-contracts

# Run scaffold verification
make scaffold-verify
```

### Cleaning

```bash
# Remove generated files
make scaffold-clean
```

## Handoff to Implementation Agents

This scaffold is ready for handoff when:

- [x] All contract templates created and validated
- [x] All codegen scripts executable
- [x] Makefile targets functional
- [x] GenesisConfig with manifest hash
- [ ] ADRs written and linked
- [ ] CI/CD workflows configured
- [ ] Documentation complete
- [ ] `make scaffold-verify` passes

**Next Steps:**

1. **Kernel Agent** - Implement `seb/kernel/` (Rust runtime)
2. **Runtime Agent** - Implement `seb/runtime/` (execution engine)
3. **Adapter Agent** - Implement `seb/adapters/` (execution adapters)
4. **Verification Agent** - Complete Lean 4 proofs (zero `sorry`)

## References

- [SEB Master Specification](../SEB_SOVEREIGN_EVENT_BUS_MASTER_SPECIFICATION.xml)
- [Architecture Paper](../ARCHITECTURE_PAPER_45_PAGES.md)
- [Execution Stack](../DEVFLOW-FINANCE/EXECUTION_STACK.md)
- [Governance Framework](../DEVFLOW-FINANCE/GOVERNANCE_FRAMEWORK.md)

## License

Proprietary - SnapKitty/Bob Sovereign AI Stack

---

**Scaffold Agent:** Bob  
**Generated:** 2026-07-25  
**Manifest Hash:** `5168C5EBDFE574AE24E5B4FC14B36A79FACAC136D823911725094BF849CD0138`