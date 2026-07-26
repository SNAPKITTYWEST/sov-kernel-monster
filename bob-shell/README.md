# SovereignShell - BOB Command Infrastructure

**Version:** 1.0  
**Trust Deed:** BOB_SOVEREIGN_ENGINEERING_CHARTER_V1  
**Status:** ACTIVE

---

## Overview

SovereignShell is the command-line interface for BOB (Bel Esprit Orchestrator Bot), providing enterprise-grade tools for building, testing, auditing, and deploying verified systems according to the BOB Trust Deed v1.0.

## Core Commands

### bob-build
Compile verified components with optional formal verification.

```bash
bob-build [component] [--verify] [--profile=<profile>]
```

**Options:**
- `--verify`: Run formal verification before build
- `--profile`: Select build profile (dev, prod, audit)

**Examples:**
```bash
bob-build compiler --verify
bob-build runtime --profile=prod
bob-build simulator --verify --profile=audit
```

### bob-test
Execute deterministic test suites with reproducible results.

```bash
bob-test [suite] [--deterministic] [--coverage]
```

**Options:**
- `--deterministic`: Ensure reproducible results (sets seeds, disables parallelism)
- `--coverage`: Generate coverage report

**Examples:**
```bash
bob-test compiler --deterministic
bob-test runtime --coverage
bob-test --deterministic --coverage
```

### bob-audit
Generate cryptographically sealed audit records.

```bash
bob-audit [component] [--format=<json|text>]
```

**Options:**
- `--format`: Output format (json or text)

**Examples:**
```bash
bob-audit compiler
bob-audit runtime --format=text
```

### bob-policy
Query Prolog/Datalog policy rules with optional reasoning traces.

```bash
bob-policy query <rule> [--explain]
```

**Options:**
- `--explain`: Provide reasoning trace

**Examples:**
```bash
bob-policy query "agent_class(oracle, X)"
bob-policy query "route_task(compile, Agent, Priority)" --explain
bob-policy query "verify_deed(deploy_production, Verdict)"
```

### bob-deploy
Deploy only validated and sealed artifacts.

```bash
bob-deploy [target] [--validate] [--seal]
```

**Options:**
- `--validate`: Validate artifacts before deployment (default: true)
- `--no-validate`: Skip validation (NOT RECOMMENDED)
- `--seal`: Generate deployment seal (default: true)
- `--no-seal`: Skip seal generation (NOT RECOMMENDED)

**Examples:**
```bash
bob-deploy production
bob-deploy staging --validate --seal
bob-deploy development
```

### bob-proof
Run formal verification pipeline using multiple proof backends.

```bash
bob-proof [theorem] [--backend=<lean4|ada|coq>]
```

**Options:**
- `--backend`: Proof backend (lean4, ada, or coq)

**Examples:**
```bash
bob-proof optimization_preserves_semantics
bob-proof state_transition_valid --backend=ada
bob-proof compiler_correctness --backend=coq
```

---

## Installation

### Prerequisites

**Required:**
- Bash 4.0+
- sha256sum (coreutils)
- find, grep (standard Unix tools)

**Optional (for specific commands):**
- Rust toolchain (for bob-build, bob-test)
- SWI-Prolog (for bob-policy)
- Lean 4 (for bob-proof --backend=lean4)
- GNAT/SPARK (for bob-proof --backend=ada)
- Coq (for bob-proof --backend=coq)

### Setup

1. **Add to PATH:**
```bash
export PATH="$PATH:/path/to/bobs-control-repo/bob-shell"
```

2. **Make scripts executable:**
```bash
chmod +x bob-shell/*.sh
```

3. **Create aliases (optional):**
```bash
alias bob-build='bash /path/to/bob-shell/bob-build.sh'
alias bob-test='bash /path/to/bob-shell/bob-test.sh'
alias bob-audit='bash /path/to/bob-shell/bob-audit.sh'
alias bob-policy='bash /path/to/bob-shell/bob-policy.sh'
alias bob-deploy='bash /path/to/bob-shell/bob-deploy.sh'
alias bob-proof='bash /path/to/bob-shell/bob-proof.sh'
```

---

## Trust Deed Compliance

All SovereignShell commands enforce BOB Trust Deed v1.0 principles:

### NO_STUBS
- Rejects TODO markers
- Rejects placeholder functions
- Rejects fake implementations
- Rejects empty methods
- Rejects simulated success responses

### SOURCE_INTEGRITY
Every component must document:
- Purpose
- Inputs
- Outputs
- Dependencies
- Verification method

### NO_PYTHON_RUNTIME
- Python prohibited in production execution paths
- Allowed only for build-time tooling
- Enforced by bob-audit and bob-deploy

### DEFENSIVE_ENGINEERING
- Rejects ambiguous requirements
- Asks for missing invariants
- Prefers explicit failure modes
- Documents all assumptions

---

## Workflow Examples

### Complete Build Pipeline

```bash
# 1. Build with verification
bob-build compiler --verify --profile=prod

# 2. Run deterministic tests
bob-test compiler --deterministic --coverage

# 3. Generate audit record
bob-audit compiler --format=json

# 4. Verify policy compliance
bob-policy query "verify_deed(deploy_production, Verdict)"

# 5. Deploy to production
bob-deploy production --validate --seal
```

### Formal Verification Workflow

```bash
# 1. Prove theorem with Lean 4
bob-proof optimization_preserves_semantics --backend=lean4

# 2. Verify contracts with Ada/SPARK
bob-proof state_transition_valid --backend=ada

# 3. Build with verification enabled
bob-build compiler --verify

# 4. Deploy verified artifacts
bob-deploy production
```

### Audit Trail Generation

```bash
# 1. Audit all components
for component in compiler runtime simulator; do
    bob-audit $component --format=json
done

# 2. Generate deployment seal
bob-deploy staging --seal

# 3. Verify policy compliance
bob-policy query "verify_deed(audit_complete, Verdict)" --explain
```

---

## Output Locations

### Build Artifacts
- **Location:** `${REPO_ROOT}/build/`
- **Reports:** `${REPO_ROOT}/build/*-build-report-*.txt`

### Test Results
- **Reports:** `${REPO_ROOT}/test-report-*.txt`
- **Coverage:** `${REPO_ROOT}/coverage/`

### Audit Records
- **Location:** `${REPO_ROOT}/.audit/`
- **Format:** JSON or text
- **Seals:** SHA-256 cryptographic seals

### Deployment Packages
- **Location:** `${REPO_ROOT}/.deploy/`
- **Manifests:** `DEPLOYMENT_MANIFEST.json`
- **Seals:** `DEPLOYMENT_SEAL.txt`

### Proof Certificates
- **Location:** `${REPO_ROOT}/.proofs/`
- **Format:** Text certificates with SHA-256 hashes

---

## Integration with Existing Architecture

### Continuity Integration
SovereignShell respects Continuity protocol:
- Searches `.continuity/decisions.json` before changes
- Logs architectural decisions immediately
- Maintains session state in `.continuity/SESSION_NOTES.md`

### QATAAUM Integration
Compatible with QATAAUM quantum assembly runtime:
- Respects clean-room boundaries
- Uses approved languages only
- Maintains formal verification chain

### Sovereign Stack Integration
Integrates with:
- j-matrix-twin (SUBLEQ attention)
- bob-orchestrator (Lean 4 + Ada + Mamba + Prolog)
- sov-kernel-monster (Fortran quantum simulator)
- sovereign-array (Lean 4 APL algebra)
- Trust Deed governance system
- WORM chain immutability

---

## Troubleshooting

### Command Not Found
```bash
# Ensure scripts are executable
chmod +x bob-shell/*.sh

# Add to PATH
export PATH="$PATH:$(pwd)/bob-shell"
```

### Verification Tools Missing
```bash
# Install Lean 4
curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | sh

# Install SWI-Prolog
sudo apt-get install swi-prolog

# Install GNAT Community
# Download from https://www.adacore.com/community
```

### Permission Denied
```bash
# Make all scripts executable
find bob-shell -name "*.sh" -exec chmod +x {} \;
```

---

## Security Considerations

### Cryptographic Seals
- All audit records sealed with SHA-256
- Deployment packages include tamper-evident seals
- Proof certificates are machine-checkable

### Trust Deed Enforcement
- Automated checks for Python in production
- Stub detection across codebase
- Documentation validation
- Policy compliance verification

### Audit Trail
- Immutable audit records
- Cryptographic chain of custody
- Explainable policy decisions

---

## Version History

### v1.0 (2026-07-25)
- Initial SovereignShell release
- Six core commands implemented
- Trust Deed v1.0 compliance
- Integration with existing architecture

---

## License

Apache License 2.0 - See repository LICENSE file for details.

---

## Contact

- **Issues:** Repository issue tracker
- **Trust Deed:** See `BOB_TRUST_DEED_V1.md`
- **Architecture:** See `ARCHITECTURE_PAPER_45_PAGES.md`

---

**Built with precision. Verified with proofs. Delivered with pride.**

*SovereignShell - Enterprise Command Infrastructure for BOB*