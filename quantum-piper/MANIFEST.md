# QUANTUM PIPER — Sovereign Quantum Civilization

Inverted Piper architecture. Local-first. WORM-anchored. Capability-gated.
Formal law: `LiquidLean.QuantumPiper` (8-phase pipeline).

## Structure

```
quantum-piper/
├── orchestrator/     BOB sovereign compliance agent — WORM, NATS, Ada gate, Lean 4, Prolog
├── kernels/
│   ├── fortran/      BOB quantum civilization engine (15 modules: QFT/Grover/Shor/WORM ABI)
│   └── cuda/         RTX 4090 inference — PagedAttention PTX, scheduler C--, GGUF loader
├── bindings/
│   ├── rust/         bob-quantum-sys — Rust FFI over Fortran engine
│   ├── elixir/janet/julia/odin/r/racket/zig/
├── reasoning/        BOB reasoning engine — SSM pipeline + Lean 4 Goldilocks proof
├── qec/              Quantum error correction — stabilizer search (Rust + Fortran)
├── resonance/        quantum.mjs / entropy.mjs — superposition monad, Born rule, KL divergence
├── formal/
│   ├── axioms/       quantum.axiom — base axioms
│   └── lean/         SovereignGate.lean — capability gate theorems
├── wasm/             Compiled WASM frontend
├── demos/            BOB vortex civilization ASCII renderer
├── tools/            build_quantum.py, nemotron.py — automated build + Nemotron agent
│
├── infra/            SOV-KERNEL-MONSTER sovereign Docker + registry stack (Haiku swarm infra)
│   ├── docker-compose.sov.yml    gitea + sov-registry-proxy + haiku-fn-ops (internal net only)
│   ├── Dockerfile.gitea          hardened Gitea from source, FROM scratch, no telemetry
│   ├── Dockerfile.hauki          Haiku fn-ops runner (Rust, musl static)
│   ├── sov-base.Dockerfile       base template for all sovereign agent images (FROM scratch)
│   ├── sov-registry.yaml         standalone local registry, 127.0.0.1:5000
│   ├── sov-attest.sh             Blake3 hash → Ed25519 sign → .worm sidecar → push
│   └── hooks/
│       ├── pre-receive           ASP enforcer — rejects unsigned/unauthorized git pushes
│       └── verify_asp.pl         Prolog deterministic heart — architect_key/engineer_key rules
│
├── provision/        Ansible bootstrap for sovereign infrastructure
│   ├── sov-bootstrap.yml         6-phase playbook: WORM vol + Ed25519 keys + hooks + deed
│   ├── inventory/sov-local.yml   7 identities: architect, 5 engineers, hauki-bot
│   └── templates/sov-worm.mount.j2  systemd unit for persistent loop mount across reboots
│
├── .sov/             Sovereign kernel config (gitignored locally, tracked in WORM)
│   └── personas/
│       └── SnapKitty_Sovereign_Transformer.xml   Haiku swarm identity + constraint set
│
└── TRUST_DEED.xml    Signed sovereign trust deed — ASP_MAXIMAL/STRICT/POLITE_CODING rules
```

## Sovereign Infra — How It Works

The `infra/` module implements a **Bifrost WORM-Chain** attestation pipeline for the Haiku swarm:

```
Haiku agent builds image
        ↓
sov-attest.sh: Blake3(image tar) → Ed25519 sign → write .worm sidecar
        ↓
git push → sov-git-server (localhost:3000)
        ↓
pre-receive hook: verify all commits signed, run verify_asp.pl (Prolog)
        ↓  fail → push rejected
Gitea mirrors to GitHub (--mirror, read-only facade)
        ↓
haiku-fn-ops: pulls image, checks .worm sidecar, verifies hash + sig
        ↓  fail → quarantine + alert
VALID → push to GHCR with semver tag. Chain sealed.
```

**Mock mode (current):** `verify_asp.pl` uses deterministic mock fingerprints. `sov-attest.sh`
falls back to `MOCK_SIG` when `BIFROST_KEY` env var is not set. Safe to run and test without
real keys.

**To activate real keys:** run `provision/sov-bootstrap.yml`, copy the Ed25519 fingerprints
from its audit output into `infra/hooks/verify_asp.pl`, set `BIFROST_KEY=/path/to/ed25519.priv`.

## Absorbed from (now archivable)
- `bob-orchestrator` (.newrepos)
- `tmp_bob/`
- `sov-kernel-monster/rust/bob-quantum-sys/`
- `sov-kernel-monster/` multi-lang bindings
- `tmp/main-repo/bob-reasoning-engine/`
- `qec-discovery/`
- `bobs-games/`
- `build_quantum.py`

## Formal law
`liquidlean/src/LiquidLean/QuantumPiper.hs` — 8-phase kernel pipeline governs all artifacts.
All kernels must pass: Parse → TypeCheck → Entangle → Optimize → AliveCheck → Compile → Attest → Deploy.
