# BIFROST AXIOM PERSONAS

**10 sovereign agents, formally specified in multiple languages**

This directory contains the complete definition of SnapKitty's agent governance system: **10 interchangeable axiom personas** that can be swapped at runtime, each backed by formal mathematics.

---

## The 10 Personas

| # | Name | Emoji | Role |
|----|------|-------|------|
| 1 | Null Architect | 🏗️🕳️ | Validates quantum circuit structure |
| 2 | Bifrost Warden | 🌈🛡️ | Guards capability transfer |
| 3 | Inverted Softmax | 📉🔥 | Probability inversion |
| 4 | Chaos Injector | 🌀💥 | Nondeterministic exploration |
| 5 | Memory Reverser | 🧠⏪ | History inversion and rollback |
| 6 | Worm Seal Guardian | 🐛🔐 | Cryptographic attestation (Blake3+Ed25519) |
| 7 | Spectral Cartographer | 🗺️🌌 | Eigenvalue decomposition |
| 8 | SnapKitty Enforcer | 😺⚡ | Direct execution |
| 9 | Harness Weaver | 🕸️🔧 | Multi-agent composition |
| 10 | Omega Seal | 🔮🌐 | Fixed-point and completion |

---

## Files

### `Personas.lean` (Lean 4)

**Language:** Lean 4  
**Purpose:** Formal verification layer

Each persona is a structure with validity predicates and theorems proving invariants.

Key theorems:
- `nullArchitect_sound`: Valid circuits have positive qubits
- `bifrostWarden_preserves_holder`: Capability holder is preserved in transfers
- `bifrostComplete`: All 10 personas validate together

### `personas.pl` (Prolog)

**Language:** Prolog (ISO + SWI extensions)  
**Purpose:** Logic programming layer

Each persona expressed as logical rules and predicates:
- `null_architect(Circuit)` — validates structure
- `bifrost_warden(Transfer)` — guards authorization
- `bifrost_validate(...)` — orchestrates all 10

Load with: `swipl personas.pl`  
Query: `?- bifrost_validate(circuit, caps, sig, hist, spec).`

---

## Philosophy

Each persona is **defined formally** and **swappable at runtime**. A regulator, auditor, or customer can:

1. **Read the Lean 4 proof** — understand formal guarantees
2. **Switch personas** — different axiom systems for different contexts
3. **Audit the WORM chain** — cryptographically signed decisions
4. **Compose agents** — Harness Weaver enables multi-agent coordination

This is the **human side of harness engineering** — making trust systems that humans can verify.

---

## Integration with Sov-Kernel-Monster

Personas validate in sequence:

```
Circuit → Null Architect ✓ → Bifrost Warden ✓ → Spectral Cartographer ✓
  → SnapKitty Enforcer (execute) → WORM Seal Guardian ✓ (attest)
```

Result: **Verifiable agent fabric** with demonstrable provenance.

---

**Status:** 🟢 Production  
**Completeness:** 100% (10/10 personas defined)  
**Last Updated:** 2026-07-22
