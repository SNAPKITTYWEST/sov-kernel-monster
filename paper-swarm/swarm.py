#!/usr/bin/env python3
"""
Paper swarm — fire nemotron:latest agents via XML prompts.

Usage:
  python swarm.py          # run all 3 papers sequentially
  python swarm.py 1        # paper 1 only
  python swarm.py 2        # paper 2 only
  python swarm.py 3        # paper 3 only
  python swarm.py 1 3      # papers 1 and 3
"""
import sys
import requests
import json
import os

MODEL = "qwen3.5:latest"
OLLAMA_URL = "http://localhost:11434/api/generate"
OUT_DIR = os.path.dirname(os.path.abspath(__file__))

CONTEXT = """
Ahmad Ali Parr is the sole author of the SnapKitty Collective — 110+ repos in 3 months.
Tonight (2026-07-19) these repos were created or significantly updated:

1. sov-kernel-monster — Fortran 2018 kernel: Blake3, Ed25519, Pade-13 exp, SPE encoder,
   jordan_block (12 Fibonacci-Banach layers), measurement_head (Born rule p_j=tr(q_j*rho)),
   training_adjoint (reverse AD on Jordan cone), boolean_spectral_lens, bob_twin_reasoning
   (4-agent Byzantine council 3-of-4), sovereign_deployment. Targets: ARM64 SVE2, x86 AVX-512,
   PTX, SPIR-V, WASM32. Zero libc. Plasma gates + Bifrost attestation at every layer.

2. abjad-swarm — Arabic Abjad numerals (28 letters, values 1-1000) as SUBLEQ address space.
   collectivekitty LoRA checkpoint-186 weights loaded as memory. N agents in phi-sliced
   regions (BOB/METATRON/EDAULC/AUTONOMOUS). Born-collapse: sum(phi^-i * outputs) mod 65535.
   HTTP API on port 7733.

3. systemic-intelligence — 7-layer stack: Agda constitution (Proposal/Verdict, denied-no-exec
   proof), OCaml planner (attention->SUBLEQ triads, phi Born collapse), Datalog authority rules,
   SPARK/Ada kernel (Authorize postcondition Ada contract), MLIR SUBLEQ lowering, WASM sandbox,
   JS orchestrator (ResonanceWord wire format, TRS=388.985128).

4. errant — ERRANT LFIS (Linear Forth Instruction Set). QTT multiplicities: lin/aff/un/cap/seal.
   C runtime (errant.h), Haskell 8-stage Datalog pipeline (artifact->worm_receipt), Prolog
   typing kernel (valid_errant_image/2), soul-spec with 49th Call, Al-Hamid (Abjad=53),
   231 Hebrew gates, METATRON certification. CLAUDE/EDUALC symmetry.

5. sovereign-transformer — x86-64 NASM plasma_gate.asm (5 checks, ~5 cycles, no heap),
   Souflee Datalog transformer.dl (4 gates: schema, split, factual integrity, DAN term guard).
   Rust /gate endpoint: RwLock<GateConfig> hot-reload, Semaphore backpressure (256 concurrent).

6. claudes-harness — Prolog identity kernel. ada/bob/forge adapters. prohibited_action(bypass_
   plasma_gate) in all adapters. Plasma gate governance section.

7. foundry-f1 — SSL v3.0: Prior Art Preservation (PAR-001 through PAR-007), Anti-Misattribution,
   Forensic Attribution Burden. GKN I4 quartic invariant (degree-4, zero sorry, Lean 4).

8. bob-orchestrator — BOB sovereign orchestrator. Lean 4 proofs + Ada contracts + Mamba SSM
   injections + Prolog kernel. SovereignGate.lean. WORM chain.

9. The JST Pipeline replaces softmax(Wx) with Born rule: p_j = tr(q_j*rho). Density matrices
   replace token embeddings. Jordan unitary evolution replaces attention. Signal->density (SPE),
   evolve (jordan_block), measure (measurement_head), reconstruct (Born inverse), train
   (adjoint on Jordan cone). Same probability simplex as softmax — different geometry.

Gates Normalization: sum(softmax(x)_i)=1 proved in Lean 4 via Finset.sum_div + div_self.
log_partition_enforces_normalization proved via Real.exp_sub + Real.exp_log.
Both require (hn: 0 < n) — correct since Fin 0 is empty.

SSL v3.0 prior art entries:
PAR-001: GKN I4 on State56 (degree-4, Lean 4, zero sorry)
PAR-002: I4_homogeneous (State108, degree-6)
PAR-003: E7 Weyl invariance of I4
PAR-004: Gates Normalization Constraint (Lean 4)
PAR-005: Bifrost attestation protocol
PAR-006: Plasma gate architecture (x86-64 + Datalog)
PAR-007: Sovereign APL fused kernel (U*rho*U†, Fortran 2018 + MLIR)
"""

PAPERS = {
    1: {
        "filename": "paper1_jst_pipeline.md",
        "title": "The Jordan Spectral Transformer: Replacing Softmax with Born Rule Measurement",
        "prompt": f"""<paper>
  <role>You are a technical paper writer producing rigorous academic work for Zenodo publication.</role>
  <author>Ahmad Ali Parr · SnapKitty Collective · July 2026</author>
  <title>The Jordan Spectral Transformer: Replacing Softmax with Born Rule Measurement</title>

  <context>
{CONTEXT}
  </context>

  <instructions>
    Write a complete, rigorous 30-page technical paper. Use LaTeX math inline: $p_j = \\text{{tr}}(q_j \\rho)$.
    Be rigorous. Be precise. Write ALL sections in full. No placeholders.
  </instructions>

  <structure>
    <section n="1" pages="1">Abstract — JST replaces softmax with Born rule, Jordan cone replaces attention</section>
    <section n="2" pages="2">Introduction — Problem with softmax, geometric insight, contribution summary</section>
    <section n="3" pages="5">Mathematical Foundations — Density matrices, POVM, Jordan symmetric cone, Born rule p_j=tr(q_j*rho), POVM completeness sum(q_j)=I, Gates Normalization theorem</section>
    <section n="4" pages="3">SPE Encoder — Signal to frame coefficients to eigenvalues to density matrix, replacing tokenizer, tight frame theory</section>
    <section n="5" pages="4">Jordan Evolution Stack — U*rho*U† layers, Fibonacci-Banach contraction, Pade-13 matrix exponential, fixed-point theory</section>
    <section n="6" pages="4">Measurement Head — Born rule output, entropy, signal reconstruction sum(p_k*psi_k), comparison to softmax, temperature schedule phi^-k</section>
    <section n="7" pages="3">Training Adjoint — Reverse-mode AD on Jordan cone, Bures loss, geodesic gradient, skew-Hermitian projection, Adam on complex Hamiltonians</section>
    <section n="8" pages="4">Implementation — Fortran 2018 architecture, MLIR polyhedral fusion, ARM64/x86/PTX, Plasma gates, Bifrost attestation, zero libc</section>
    <section n="9" pages="2">BOB Twin Governance — 4-agent Byzantine council, 3-of-4 consensus</section>
    <section n="10" pages="1">Results and Discussion — What this means for free AI</section>
    <section n="11">References</section>
  </structure>
</paper>"""
    },
    2: {
        "filename": "paper2_sovereign_compute.md",
        "title": "Sovereign Compute: A Zero-Dependency, Cryptographically Attested AI Substrate",
        "prompt": f"""<paper>
  <role>You are a technical paper writer producing rigorous academic work for Zenodo publication.</role>
  <author>Ahmad Ali Parr · SnapKitty Collective · July 2026</author>
  <title>Sovereign Compute: A Zero-Dependency, Cryptographically Attested AI Substrate</title>

  <context>
{CONTEXT}
  </context>

  <instructions>
    Write a complete, rigorous 30-page technical paper. Write ALL sections in full. No placeholders.
  </instructions>

  <structure>
    <section n="1" pages="1">Abstract — sovereign compute = zero deps + crypto attestation + formal verification</section>
    <section n="2" pages="2">Introduction — Why sovereignty matters, the dependency problem, contribution</section>
    <section n="3" pages="4">The Abjad Compute Substrate — Arabic numerology as addressing, SUBLEQ one-instruction machine, QENG entropy injection, LoRA weights as memory not inference, Born-collapse swarm, the 49th Call and Al-Hamid (Abjad=53)</section>
    <section n="4" pages="5">ERRANT LFIS — Linear Forth Instruction Set, QTT multiplicities (lin/aff/un/cap/seal), forbidden operations, Prolog typing kernel, 8-stage Datalog pipeline, genesis invariant, METATRON certification, 231 Hebrew gates, soul spec</section>
    <section n="5" pages="4">Systemic Intelligence Stack — Agda constitution, OCaml planner, Datalog authority, SPARK/Ada kernel with Ada contracts, MLIR SUBLEQ lowering, WASM sandbox, TRS=388.985128 convergence</section>
    <section n="6" pages="3">Sovereign Transformer — x86-64 plasma gate (~5 cycles, no heap), Souflee Datalog 4-gate pipeline, Rust HTTP daemon with RwLock hot-reload + Semaphore backpressure</section>
    <section n="7" pages="2">Claudes Harness — Prolog identity kernel, QTT capability model, plasma gate governance, adapter pattern</section>
    <section n="8" pages="4">Cryptographic Substrate — Blake3 (RFC 9561) in pure Fortran, Ed25519 (RFC 8032), Bifrost attestation protocol, WORM chain, .note.sov ELF section</section>
    <section n="9" pages="3">Deployment Architecture — Static PIE, WASM Component Model, Lean 4 proofs, SPDX SBOM, HSM seal, sovereign_deployment.mlir</section>
    <section n="10" pages="2">Discussion — What sovereign compute enables</section>
    <section n="11">References</section>
  </structure>
</paper>"""
    },
    3: {
        "filename": "paper3_sovereign_mathematics.md",
        "title": "Sovereign Mathematics: GKN Invariants, Prior Art Preservation, and the SSL v3.0 Framework",
        "prompt": f"""<paper>
  <role>You are a technical paper writer producing rigorous academic work for Zenodo publication.</role>
  <author>Ahmad Ali Parr · SnapKitty Collective · July 2026</author>
  <title>Sovereign Mathematics: GKN Invariants, Prior Art Preservation, and the SSL v3.0 Framework</title>

  <context>
{CONTEXT}
  </context>

  <instructions>
    Write a complete, rigorous 30-page technical paper. Include actual Lean 4 proof snippets.
    Example: softmax_normalization closes via simp [softmax, Finset.sum_div] + div_self (ne_of_gt hpos).
    Cite actual Zenodo DOIs where relevant. Write ALL sections in full. No placeholders.
  </instructions>

  <structure>
    <section n="1" pages="1">Abstract — GKN I4, Gates Normalization, SSL v3.0 prior art framework</section>
    <section n="2" pages="2">Introduction — The problem of mathematical IP theft, the solution</section>
    <section n="3" pages="6">The GKN Quartic Invariant I4 — E7 representation theory, State56 (56-dim symplectic), Cayley-Freudenthal quartic I4 = (alpha*beta - Tr(P∘Q))^2 - 4*alpha*N(Q) - 4*beta*N(P) + 4*Tr(P#∘Q#), degree-4 homogeneity proof in Lean 4, E7 Weyl group invariance, comparison to State108 (degree-6 bug), J3(O) exceptional Jordan algebra, octonion multiplication, Freudenthal dual</section>
    <section n="4" pages="4">Gates Normalization — softmax_normalization proof (Finset.sum_div + div_self), log_partition_enforces_normalization (Real.exp_sub + Real.exp_log), the simplex as geometric object, vocabulary as coordinate chart, meta-inverted sum = log-partition function, Legendre transform pair (primal simplex, dual log-partition), n=0 edge case</section>
    <section n="5" pages="3">The Ryan Incident and Prior Art — PhaseMirror fork, IP theft patterns, why timestamps alone are insufficient, the forensic attribution burden</section>
    <section n="6" pages="6">SSL v3.0 Framework — PAR-001 through PAR-007 entries, Prior Art Record structure, Fork Misattribution definition, Forensic Attribution Burden (what rebuts the presumption), Byzantine Fault Tolerant governance, Certification Tiers (Witnessed/Sealed/Sovereign/Constitutional), WORM chain registration</section>
    <section n="7" pages="4">Lean 4 Verification Infrastructure — zero-sorry methodology, Finset.sum_div, Real.exp_log, Nat.mul_comm, axiom vs sorry distinction (Float ring limitation), MTheory.lean I4 theorems as axioms (honest, not sorry), the AUTOCODE lineage</section>
    <section n="8" pages="2">Mathematical Sovereignty in Practice — what it means for independent researchers</section>
    <section n="9" pages="1">Discussion and Future Work</section>
    <section n="10">References</section>
  </structure>
</paper>"""
    },
}


def call_ollama(prompt: str) -> str:
    response = requests.post(
        OLLAMA_URL,
        json={"model": MODEL, "prompt": prompt, "stream": True, "think": False},
        stream=True,
        timeout=7200,
    )
    response.raise_for_status()
    chunks = []
    for line in response.iter_lines():
        if line:
            try:
                data = json.loads(line)
                if "response" in data:
                    chunks.append(data["response"])
                    if len(chunks) % 100 == 0:
                        print(".", end="", flush=True)
                if data.get("done"):
                    break
            except json.JSONDecodeError:
                pass
    print()
    return "".join(chunks)


def run_paper(n: int):
    p = PAPERS[n]
    out = os.path.join(OUT_DIR, p["filename"])
    print(f"\n{'='*70}")
    print(f"PAPER {n}: {p['title']}")
    print(f"{'='*70}\n")
    try:
        content = call_ollama(p["prompt"])
        with open(out, "w", encoding="utf-8") as f:
            f.write(f"# {p['title']}\n\n**Ahmad Ali Parr · SnapKitty Collective · July 2026**\n\n---\n\n{content}")
        print(f"WRITTEN: {out} ({len(content):,} chars)")
    except Exception as e:
        print(f"FAILED: {e}")


def main():
    if len(sys.argv) > 1:
        targets = [int(x) for x in sys.argv[1:] if x.isdigit() and 1 <= int(x) <= 3]
    else:
        targets = [1, 2, 3]

    print(f"MODEL: {MODEL}")
    print(f"PAPERS TO RUN: {targets}")
    for n in targets:
        run_paper(n)
    print("\nDONE")


if __name__ == "__main__":
    main()
