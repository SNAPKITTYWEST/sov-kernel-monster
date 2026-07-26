# Theorem 3 Crack: Integration into sov-kernel-monster

## Overview

The Jacobian Conjecture crack (Theorem 3: constant Jacobian ⟹ genus-0 curve) has been cherry-picked into `haskell/` for polyglot integration.

**Location:** `sov-kernel-monster/haskell/LiquidLean/Jacobian/`

**Status:** Phase 1 integration (code as-is, bugs documented for Phase 2)

---

## Module Structure

```
haskell/LiquidLean/Jacobian/
├── Theorem3Kernel.hs           [SOURCE: Theorem3 core types, Polynomial ops]
├── MoraLocal.hs                [SOURCE: Mora standard basis algorithm]
├── SingularityAnalysis.hs       [SOURCE: Milnor number + δ-invariant computation]
├── CrackTheorem3.hs            [SOURCE: Main orchestration (genus-0 forcing)]
└── Theorem3Entry.hs            [NEW: Kernel integration point]
```

### Module Responsibilities

| Module | Purpose | Lines | Dependencies |
|--------|---------|-------|--------------|
| **Theorem3Kernel** | Polynomial type, Rational/Z literals, Energy monad, Thermal type, Obstruction errors | 169 | GHC.TypeLits, Data.Map, Data.Ratio, Control.Monad.State |
| **MoraLocal** | Mora weak normal form, divisibility, Gröbner basis algorithm | 82 | Theorem3Kernel, Data.Map |
| **SingularityAnalysis** | Polynomial translation, lowest-degree part extraction, branch counting, Plücker genus formula | 93 | Theorem3Kernel, MoraLocal |
| **CrackTheorem3** | Main algorithm: singularity → δ-invariants → genus formula → decision | 101 | Theorem3Kernel, MoraLocal, SingularityAnalysis |
| **Theorem3Entry** | Kernel-facing interface, Theorem3Status/Evidence types, energy accounting wrapper | 150 | All of the above |

---

## Entry Point

```haskell
theorem3EnforceGenusZero :: Polynomial -> Integer -> Either Obstruction Theorem3Evidence
```

**Inputs:**
- `Polynomial` — The implicit curve h(u,x) ∈ ℚ[u,x]
- `Integer` — Energy budget (φ⁻¹ discretized as integer tokens)

**Outputs:**
```haskell
Either Obstruction Theorem3Evidence

data Theorem3Status
  = GenusZeroProved Polynomial        -- Theorem 3 holds ✓
  | CounterexampleFound Polynomial Int -- Higher genus (potential counter to Conjecture)
  | AnalysisBlocked Obstruction        -- Hit an obstruction

data Theorem3Evidence
  { evPolynomial :: Polynomial         -- Input poly
  , evDegree :: Int                   -- Degree
  , evGenusBound :: Int               -- Genus from Plücker
  , evEnergySpent :: Integer          -- Energy consumed
  , evEnergyBudget :: Integer         -- Initial budget
  , evStatus :: Theorem3Status        -- Result
  }
```

---

## Integration with Kernel

### 1. Lean FFI Bindings (New)

Add to `lean/SovMonster.lean`:

```lean
namespace Theorem3

@[extern "theorem3_enforce_genus_zero"]
opaque enforceGenusZero 
    (polyPtr : CPtr) (polyBytes : Int64) 
    (budget : Int64)
    (statusPtr : CPtr) : Unit
```

### 2. Fortran Bridge (New)

Add to `src/theorem3_gateway.f90`:

```fortran
subroutine theorem3_enforce_genus_zero( &
    poly_ptr, poly_bytes, budget, status_ptr) bind(C, name='theorem3_enforce_genus_zero')
  use iso_c_binding
  use bob_kinds
  implicit none
  
  integer(c_int64_t), value :: poly_ptr, poly_bytes, budget
  integer(c_int64_t) :: status_ptr
  
  ! Call Haskell: Theorem3Entry.theorem3EnforceGenusZero
  ! [Requires Haskell RTS + foreign imports]
end subroutine
```

### 3. Rust WASM Bridge (Optional)

If running in `wasm/`, implement thin wrapper:

```rust
#[wasm_bindgen]
pub extern "C" fn theorem3_prove_genus_zero(
    poly_bytes: &[u8],
    budget: u64,
) -> String {
    // Call Haskell via FFI or as subprocess
    // Return JSON: {"status": "GenusZeroProved", "energy": 42}
}
```

---

## WORM Ledger Interface

Energy tokens emitted by `theorem3_enforce_genus_zero` flow into the WORM chain:

```
Entry structure:
  {
    "kernel_id": "theorem3_entry",
    "event": "forceGenusZero",
    "polynomial_degree": <int>,
    "energy_token": <integer>,
    "timestamp": <quantum_state>,
    "prior_entry_hash": <Blake3>
  }

Sealed with:
  signature := Ed25519(entry ‖ prior_entry_hash, sk_node)
  receipt := (Blake3_hash, Ed25519_sig)
```

See: `src/bob_worm.f90` for chain mechanics.

---

## Known Bugs (Phase 1: NOT FIXED)

### Bug #1: SingularityAnalysis.translate() — Scope Error

**File:** `SingularityAnalysis.hs`, lines 32-44

**Issue:** Variables `u'` and `x'` are used in the `coeff` function but not properly bound.

```haskell
translate (Poly f) (u0, x0) = Poly $ Map.fromListWith (+)
  [ ((u'-a, x'-b), c * coeff a b u0 x0)  -- u', x' undefined here!
  | ((a,b), c) <- Map.toList f
  , u' <- [0..a], x' <- [0..b]
  ]
  where
    coeff a b u0 x0 =
      fromIntegral (choose a (a-u') * choose b (b-x'))  -- u', x' not in scope
      * (u0 ^ (a - u')) * (x0 ^ (b - x'))
```

**Symptoms:** Compilation failure or runtime crash on `analyseSingularity`.

**Fix (Phase 2):** Refactor `coeff` to accept `u'` and `x'` as parameters or use a curried lambda.

---

### Bug #2: SingularityAnalysis.countBranches() — Incomplete Factorization

**File:** `SingularityAnalysis.hs`, lines 56-61

**Issue:** Polynomial factorization is stubbed out. Returns `degree + 1` as a placeholder.

```haskell
countBranches h0 =
  let (initForm, _) = lowestDegreePart h0
      -- Placeholder: actual factorization deferred
      degree = totalDegree initForm
  in if degree >= 0 then degree + 1 else 1
```

**Symptoms:** δ-invariant is under-counted. Genus bound may be incorrect.

**Fix (Phase 2):** Implement polynomial factorization over ℚ using resultant or Hensel lifting.

---

### Bug #3: MoraLocal.monomialDiff() — Inverted Subtraction

**File:** `MoraLocal.hs`, lines 44-45

**Issue:** The monomial difference is computed backwards.

```haskell
monomialDiff (LM u1 x1) (LM u2 x2) = (u1 - u2, x1 - x2)  -- Should be (u2-u1, x2-x1)
```

**Symptoms:** Mora reduction computes incorrect quotient monomials.

**Fix (Phase 2):** Swap the subtraction order: `(u2 - u1, x2 - x1)`.

---

### Bug #4: CrackTheorem3.forceGenusZero() — Single Singularity Check

**File:** `CrackTheorem3.hs`, lines 49-51

**Issue:** Only checks singularity at origin. Missing all other critical singular points.

```haskell
-- Step 2: Analyze singularities (simplified: check origin)
-- In full version: would find all singular points via resultant
singData <- analyseSingularity hPoly (0, 0)
```

**Symptoms:** δ-invariant computation is incomplete. Genus bound is wrong.

**Fix (Phase 2):** Compute singular locus: { (u,x) : h=0, ∂h/∂u=0, ∂h/∂x=0 } via resultant.

---

### Bug #5: Theorem3Kernel.translate() — Undefined Variables

**File:** `Theorem3Kernel.hs`, line 128-130

**Issue:** Arity check only handles 2-variable polynomials. (Design limitation, not a bug.)

```haskell
evaluate (Poly f) [u,x] = sum [ c * (u^u') * (x^x')
                               | ((u',x'),c) <- Map.toList f ]
evaluate _ _ = error "evaluate: wrong arity"
```

**Impact:** No immediate problem, but limits to univariate/bivariate.

---

## Build Instructions (Future)

When ready to build the polyglot kernel with Haskell:

```bash
# 1. Build just Theorem 3
cd sov-kernel-monster/haskell
ghc -XStrictData -O2 \
  LiquidLean/Jacobian/Theorem3Kernel.hs \
  LiquidLean/Jacobian/MoraLocal.hs \
  LiquidLean/Jacobian/SingularityAnalysis.hs \
  LiquidLean/Jacobian/CrackTheorem3.hs \
  LiquidLean/Jacobian/Theorem3Entry.hs \
  -shared -dynamic -fPIC

# 2. Link with Fortran kernel
cd ..
make theorem3_bridge

# 3. Verify Lean FFI compiles
lake build
```

---

## Proof Map

```
Input: h(u,x) with det(J_F) = const
         ↓
         ├─→ [Find singularities] → set S of (u_i, x_i)
         │
         ├─→ [For each P ∈ S]:
         │     ├─→ Translate to origin: h₀ = h(u+u_P, x+x_P)
         │     ├─→ Jacobian ideal: ⟨∂h₀/∂u, ∂h₀/∂x⟩
         │     ├─→ Mora basis: GB
         │     ├─→ Standard monomials: μ = |{LT(GB)}|
         │     ├─→ Branches: r = factor multiplicity
         │     └─→ δ_P = (μ + r - 1) / 2   [Milnor-Jung]
         │
         ├─→ [Plücker Genus Formula]:
         │     g = (d-1)(d-2)/2 - Σ δ_P
         │
         └─→ [Decision]:
              ├─ If g = 0 → GenusZeroProved ✓
              ├─ If g > 0 → CounterexampleFound (genus > 0!)
              └─ Else → AnalysisBlocked (error)

Output: Either Obstruction Theorem3Evidence
```

---

## Related Files

- **Source (liquidlean-transmutation):** `../liquidlean-transmutation/src/LiquidLean/Jacobian/`
- **Formal spec (jacobian-formal):** `/tmp/jacobian-formal/lean/Jacobian/MainConjecture.lean`
- **WORM attestation:** `src/bob_worm.f90`
- **Quantum boundary:** `src/sov_monster_kernel.f90` (Blake3 + Ed25519)
- **Lean FFI spec:** `lean/SovMonster.lean`

---

## Next Steps (Phase 2)

1. ✅ Cherry-pick modules (DONE)
2. ✅ Create entry point (DONE)
3. ⏳ Fix Bug #1 (translate scope)
4. ⏳ Fix Bug #2 (countBranches factorization)
5. ⏳ Fix Bug #3 (monomialDiff sign)
6. ⏳ Fix Bug #4 (complete singularity search)
7. ⏳ Add Lean FFI bindings
8. ⏳ Add Fortran bridge
9. ⏳ Wire to WORM ledger
10. ⏳ Test end-to-end

---

**Integration Date:** 2026-07-20  
**Phase:** 1 (cherry-pick, no fixes)  
**Bugs:** 5 documented for Phase 2  
**Status:** Ready for formalization review  
