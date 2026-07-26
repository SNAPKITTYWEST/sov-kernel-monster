# Theorem 3 Integration: Quick Reference

**Status:** Phase 1 Complete (2026-07-20)  
**Location:** `sov-kernel-monster/haskell/LiquidLean/Jacobian/`  
**Entry Point:** `theorem3EnforceGenusZero :: Polynomial -> Integer -> Either Obstruction Theorem3Evidence`

---

## Module Map

| Module | Purpose | Lines | Status |
|--------|---------|-------|--------|
| `Theorem3Kernel.hs` | Polynomial types, Energy monad, Obstruction errors | 169 | ✅ Cherry-picked |
| `MoraLocal.hs` | Mora standard basis algorithm | 82 | ✅ Cherry-picked |
| `SingularityAnalysis.hs` | Milnor number, δ-invariants, Plücker genus | 93 | ✅ Cherry-picked |
| `CrackTheorem3.hs` | Main orchestration: singularity → genus decision | 101 | ✅ Cherry-picked |
| `Theorem3Entry.hs` | Kernel integration wrapper + WORM bridge | 150 | ✅ NEW |

---

## Quick Start

### Using the Entry Point

```haskell
import LiquidLean.Jacobian.Theorem3Entry

-- Example: test polynomial h = u*x - 1
let h = fromTerms [(1,1,1), (0,0,-1)] :: Polynomial
let result = theorem3EnforceGenusZero h 1000

-- Returns: Either Obstruction Theorem3Evidence
case result of
  Left obs -> putStrLn $ "Error: " ++ show obs
  Right ev -> putStrLn $ "Genus: " ++ show (evGenusBound ev)
```

### Signature

```haskell
theorem3EnforceGenusZero 
  :: Polynomial     -- Input polynomial h(u,x)
  -> Integer        -- Energy budget (φ⁻¹ tokens)
  -> Either Obstruction Theorem3Evidence

data Theorem3Status
  = GenusZeroProved Polynomial        -- Theorem 3 holds ✓
  | CounterexampleFound Polynomial Int -- Higher genus
  | AnalysisBlocked Obstruction        -- Hit obstruction

data Theorem3Evidence = Theorem3Evidence
  { evPolynomial :: Polynomial        -- Input polynomial
  , evDegree :: Int                   -- Total degree
  , evGenusBound :: Int               -- Genus from Plücker
  , evEnergySpent :: Integer          -- Energy consumed
  , evEnergyBudget :: Integer         -- Initial budget
  , evStatus :: Theorem3Status        -- Final status
  }
```

---

## Known Bugs (Phase 2 Deferred)

### Bug #1: SingularityAnalysis.translate() — Variable Scope

**File:** `SingularityAnalysis.hs:32-44`  
**Severity:** HIGH  
**Issue:** Variables `u'`, `x'` undefined in `coeff` function scope.  
**Impact:** Crashes on `analyseSingularity` calls with non-origin singularities.  
**Fix:** Refactor `coeff` to accept u', x' as parameters.

### Bug #2: SingularityAnalysis.countBranches() — Incomplete Factorization

**File:** `SingularityAnalysis.hs:56-61`  
**Severity:** MEDIUM  
**Issue:** Returns `degree + 1` placeholder; actual factorization not implemented.  
**Impact:** δ-invariant under-counted; genus bound incorrect.  
**Fix:** Implement polynomial factorization over ℚ (resultant or Hensel lifting).

### Bug #3: MoraLocal.monomialDiff() — Inverted Arithmetic

**File:** `MoraLocal.hs:44-45`  
**Severity:** MEDIUM  
**Issue:** Computes `(u1-u2, x1-x2)` instead of `(u2-u1, x2-x1)`.  
**Impact:** Mora reduction computes wrong quotient monomials.  
**Fix:** Swap subtraction order.

### Bug #4: CrackTheorem3.forceGenusZero() — Incomplete Singularity Search

**File:** `CrackTheorem3.hs:49-51`  
**Severity:** HIGH  
**Issue:** Only checks singularity at origin (0,0); misses all others.  
**Impact:** δ-invariant computation incomplete; genus formula wrong.  
**Fix:** Compute full singular locus via resultant algorithm.

### Bug #5: Theorem3Kernel.evaluate() — Arity Limitation

**File:** `Theorem3Kernel.hs:127-130`  
**Severity:** LOW  
**Issue:** Only handles 2-variable polynomials (design limitation).  
**Impact:** Can't evaluate with other arities.  
**Fix:** Generalize to n variables (optional).

---

## Proof Pipeline

```
Input: h(u,x) [polynomial]
  ↓
[Step 1: Find singularities]
  → Singular locus S = { (u,x) : h=0 ∧ ∂h/∂u=0 ∧ ∂h/∂x=0 }
  ⚠️  BUG #4: Currently only checks (0,0)
  ↓
[Step 2: For each singularity P ∈ S]
  → Translate: h₀ = h(u+u_P, x+x_P)
  ⚠️  BUG #1: Fails on non-origin translation
  ↓
  → Jacobian ideal: ⟨∂h₀/∂u, ∂h₀/∂x⟩
  → Mora basis: GB via groebnerBasisLocal
  ⚠️  BUG #3: Mora reduction may have arithmetic error
  ↓
  → Standard monomials: μ = countStandardMonomials GB
  → Branches: r = countBranches h₀
  ⚠️  BUG #2: countBranches is stub (returns degree+1)
  ↓
  → Milnor-Jung: δ = (μ + r - 1) / 2
  ↓
[Step 3: Plücker Genus Formula]
  g = (d-1)(d-2)/2 - Σ δ_P
  ↓
[Step 4: Decision]
  If g = 0 → GenusZeroProved ✓
  If g > 0 → CounterexampleFound (genus contradiction!)
  Else → AnalysisBlocked (error)
```

---

## Integration with sov-kernel-monster

### WORM Ledger

Each `theorem3EnforceGenusZero` call emits energy tokens:

```json
{
  "kernel_id": "theorem3_entry",
  "event": "forceGenusZero",
  "polynomial_degree": 6,
  "energy_token": 42,
  "prior_entry_hash": "Blake3(previous_entry)"
}
```

Sealed with Ed25519 at quantum boundary (`sov_monster_kernel.f90`).

### Lean FFI Binding (Template)

```lean
@[extern "theorem3_enforce_genus_zero"]
opaque enforceGenusZero 
    (polyPtr : CPtr) (budget : Int64)
    (statusPtr : CPtr) : Unit
```

See `INTEGRATION_GUIDE.md` for full Fortran + WASM templates.

---

## Build

```bash
cd sov-kernel-monster/haskell

# Stack (recommended)
stack build

# Or with Cabal
cabal build

# Or with ghc directly
ghc -XStrictData -O2 \
  LiquidLean/Jacobian/Theorem3Kernel.hs \
  LiquidLean/Jacobian/MoraLocal.hs \
  LiquidLean/Jacobian/SingularityAnalysis.hs \
  LiquidLean/Jacobian/CrackTheorem3.hs \
  LiquidLean/Jacobian/Theorem3Entry.hs
```

---

## References

- **Full architecture:** `INTEGRATION_GUIDE.md` (330 lines)
- **Phase 1 summary:** `PHASE_1_INTEGRATION_SUMMARY.md` (427 lines)
- **Formal spec:** `/tmp/jacobian-formal/lean/Jacobian/MainConjecture.lean`
- **Source repo:** `liquidlean-transmutation/src/LiquidLean/Jacobian/`

---

## Phase 2 Roadmap

- ⏳ Fix 5 bugs (critical path: #1, #4, #2)
- ⏳ Lean FFI bindings
- ⏳ Fortran bridge + Haskell RTS
- ⏳ WORM ledger wiring
- ⏳ Quantum boundary verification
- ⏳ Test suite
- ⏳ Performance profiling

**Next step:** Fix Bug #1 and #4 to enable full singularity analysis.

---

**Last updated:** 2026-07-20  
**Phase:** 1 (Cherry-pick Complete, No Fixes)  
**Bugs:** 5 documented, all deferred to Phase 2
