# Phase 3 Proof Discharge — Quick Start Guide

## What Happened?

Round 1 orchestration of Phase 3 proof discharge for the BOB quantum kernel loop invariants formalization (Agda) is **complete**. Three specialized agents (ahmad_bot, forge, enki) analyzed 15 holes across 4 modules and identified critical structural gaps.

## Key Results (60-second summary)

| Metric | Value |
|--------|-------|
| Holes Identified | 15 |
| Holes Discharged | 0 |
| Spec Gaps Found | 2 (critical) |
| Viable Discharges Proposed | 1 |
| Agents Deployed | 3 (running in parallel) |

### The Two Critical Issues

**1. EvolutionLoop.agda** — Missing semantic contract  
- **What:** `StepTransition` record lacks `state_valid_preserved` field
- **Why:** Quantum evolution must preserve Hilbert space dimension
- **Fix:** Add 1 field (~4 lines)
- **Impact:** Unblocks 3 holes

**2. MatrixAccumulationLoop.agda** — Missing precondition  
- **What:** `matrix_acc_base` doesn't require `max_terms ≥ 1`
- **Why:** RK4 Taylor series needs at least one term
- **Fix:** Add 1 parameter (~2 lines)
- **Impact:** Unblocks 5 holes

### Viable Discharge Found

**EulerLoop.agda line 141:** Lower bound arithmetic proof ready for type-checking.

---

## Where to Find Everything

### Main Reports (in this directory)
- **PHASE_3_RESULTS_INDEX.md** ← START HERE (executive summary)
- **PHASE_3_ORCHESTRATION_LOG.md** (detailed findings per agent)
- **PHASE_3_DISCHARGE_SUMMARY.txt** (full context)

### Supporting Artifacts
- `/tmp/PHASE_3_DISCHARGE_REPORT.md` (analysis)
- `/tmp/PHASE_3_WORM_ENTRIES.jsonl` (WORM audit trail)

### Source Code Locations

**Files that need fixing:**
- `src/Invariants/EvolutionLoop.agda` (lines 100–124)
- `src/Invariants/MatrixAccumulationLoop.agda` (lines 87–97)

**Proposed discharge:**
- `src/Invariants/EulerLoop.agda` (line 141)

---

## Next Steps (Priority Order)

### Phase 3.1: Apply Spec Corrections (BLOCKING)

**In EvolutionLoop.agda**, add to `StepTransition` record (after `time_advances` field):
```agda
state_valid_preserved :
  isValidDim (EvolutionState.state s) →
  isValidDim (EvolutionState.state s')
```

**In MatrixAccumulationLoop.agda**, modify `matrix_acc_base` signature:
```agda
matrix_acc_base :
  (s : MatrixAccLoopState) →
  MatrixAccLoopState.k s ≡ 1 →
  MatrixAccContext.dt (MatrixAccLoopState.ctx s) > 0 →
  MatrixAccContext.state_dim (MatrixAccLoopState.ctx s) ≥ 1 →
  MatrixAccLoopState.factorial_k s ≡ 1 →
  MatrixAccLoopState.term_coefficient s ≡ MatrixAccContext.dt (MatrixAccLoopState.ctx s) →
  MatrixAccLoopState.num_hamiltonian_sweeps s ≡ 0 →
  MatrixAccLoopState.exp_matrix_accumulated s ≡ MatrixAccContext.state_dim (MatrixAccLoopState.ctx s) * MatrixAccContext.state_dim (MatrixAccLoopState.ctx s) →
  MatrixAccLoopState.error_status s ≡ 0 →
  MatrixAccContext.max_terms (MatrixAccLoopState.ctx s) ≥ 1 →  -- ADD THIS LINE
  MatrixAccInvariant s 1
```

Then in `matrix_acc_base` body, replace line 101:
```agda
{ h_k_valid = h_max_terms_pos  -- Changed from: ?
```

### Phase 3.2: Re-run Discharge (After fixes)

1. Run agents on fixed code:
   - ahmad_bot → EvolutionLoop holes (retry)
   - enki → MatrixAccumulationLoop hole 101 (retry)
   - forge → EulerLoop line 141 (verify proposed proof)

2. Type-check proposed discharges via `lake build`

3. WORM-seal successful proofs

### Phase 3.3: Analyze Remaining Modules

- GateApplicationLoop.agda (4 holes) — not yet analyzed
- Expected: Similar precondition patterns

---

## Technical Context

### The Formalization

This is a Phase 2→3 progression of BOB's quantum kernel loop invariants in Agda:

- **Phase 2** (completed): Defined 4 loop invariant structures + predicates
- **Phase 3** (in progress): Discharge 15 proof holes to validate invariants

### The Holes

All 15 holes are placeholder `?` marks in proof terms. They represent:
- 3 base-case proofs (induction start)
- 5 inductive-step proofs (state preservation)
- 4 exit-condition proofs (postconditions)
- 3 auxiliary arithmetic proofs

### The Agents

- **ahmad_bot:** Specializes in state evolution & bookkeeping (EvolutionLoop)
- **forge:** Specializes in numerical updates & bounds (EulerLoop)
- **enki:** Specializes in matrix algebra & Taylor series (MatrixAccumulationLoop)

---

## Why This Matters

The formalization bridges informal C/Fortran implementation and formal specification. The two spec gaps that surfaced are **semantic invariants** that the implementation silently assumes but the formalization must make explicit:

1. **Dimension Preservation:** Quantum evolution respects the structure of the state space (core physics)
2. **Taylor Series Bounds:** RK4 requires minimum 1 term (integration contract)

These aren't bugs—they're **correctness requirements** that formal verification makes visible.

---

## Questions?

See **PHASE_3_RESULTS_INDEX.md** for:
- Full technical details (predicate definitions, record structures)
- Per-agent findings and recommendations
- Complete hole inventory with status
- Phase 3 roadmap (Phases 3.1–3.4)

---

**Status:** Ready for Phase 3.1 spec corrections  
**Estimated time to completion:** 2–4 hours (after fixes applied)  
**Next checkpoint:** Phase 3.2 (Round 2 discharge verification)
