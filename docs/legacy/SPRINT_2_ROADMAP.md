# SPRINT 2 ROADMAP
## Complete Build-Out: FFI Bindings → Bug Fixes → Production Ready

**Timeline:** 4-6 weeks  
**Harness:** Claude's Harness (Prolog governance)  
**Model:** Haiku FN OPS Dev  
**Cost Target:** <$1.00 (sub-$0.24 efficiency ratio from Sprint 1)

---

## PHASE 2.1: LEAN FFI BINDINGS (Week 1-2)

### What it is
Wire Lean 4 formal proofs to the C ABI kernel so theorem verification gates the Fortran runtime.

### Deliverables

**File: `lean/SovMonster.lean` (NEW, ~400 lines)**
```lean
import Std.Data.Array

namespace SovMonster

-- C ABI foreign declarations
@[extern "bob_rng_create"]
def bob_rng_create (seed : Int64) : IO UInt64 := sorry

@[extern "bob_state_measure"]
def bob_state_measure (state : UInt64) (rng : UInt64) : IO Int64 := sorry

@[extern "bob_hamiltonian_expectation"]
def bob_hamiltonian_expectation (h : UInt64) (state : UInt64) : IO Float := sorry

-- Proof theorems
theorem born_rule_sum_one {ψ : Array Float} (h_norm : ∑ i, ψ[i]^2 = 1) :
  ∑ i, (ψ[i]^2) = 1 := h_norm

theorem unitary_preserves_norm {U : Matrix 2 2 Float} {ψ : Array Float}
  (h_unitary : U.H * U = Matrix.one)
  (h_norm : ∑ i, ψ[i]^2 = 1) :
  ∑ i, (∑ j, U[i][j] * ψ[j])^2 = 1 := by sorry

end SovMonster
```

**File: `lean/lakefile.lean` (NEW, ~50 lines)**
```
import Lake
open Lake DSL

package «sovmonster» where
  version := v"1.0.0"
  supportedPlatforms := #[.osx, .linux, .windows]

@[default_target]
lean_lib SovMonster
```

**File: `lean/Makefile.lean` (NEW, ~100 lines)**
```makefile
.PHONY: lean-build lean-test lean-check lean-doc lean-clean

lean-build:
	lake build

lean-test:
	lake build test

lean-check:
	lake env lean --type-check SovMonster.lean

lean-clean:
	lake clean
```

### Integration Points
- ✅ Export C ABI declarations via `@[extern]` annotations
- ✅ Wire `bob_rng_create` → Lean RNG verification
- ✅ Wire `bob_state_measure` → Born rule theorem proof
- ✅ Wire `bob_hamiltonian_expectation` → Energy conservation proof
- ✅ Compile: `lake build` → generates `.o` objects linkable with Fortran

### Success Criteria
- [ ] All 14 C ABI functions have Lean `@[extern]` declarations
- [ ] Born rule theorem proven + type-checked
- [ ] Unitary preservation proven + type-checked
- [ ] Lake build succeeds: `lake build` → 0 errors
- [ ] Object files generated: `./build/lib/libsovmonster.a`

---

## PHASE 2.2: FORTRAN BRIDGE (Week 2-3)

### What it is
Complete Fortran↔Haskell↔Lean FFI plumbing so Theorem 3 can be called from the C ABI.

### Deliverables

**File: `src/fortran_haskell_bridge.f90` (NEW, ~250 lines)**
```fortran
module fortran_haskell_bridge
  use, intrinsic :: iso_c_binding
  use bob_kinds
  implicit none
  private

  ! Haskell entry points (via QuantumFortranBridge.hs)
  interface
    function haskell_theorem3_offload(poly_str, energy_budget) &
             bind(C, name="haskell_theorem3_offload")
      use iso_c_binding
      character(kind=c_char) :: poly_str(*)
      integer(c_int), value :: energy_budget
      integer(c_int) :: haskell_theorem3_offload
    end function haskell_theorem3_offload

    function haskell_verify_genus_zero(polynomial_coeffs, num_coeffs) &
             bind(C, name="haskell_verify_genus_zero")
      use iso_c_binding
      real(c_double) :: polynomial_coeffs(*)
      integer(c_int), value :: num_coeffs
      integer(c_int) :: haskell_verify_genus_zero
    end function haskell_verify_genus_zero
  end interface

  public :: fortran_call_theorem3_kernel
  public :: fortran_verify_polynomial_genus

contains

  subroutine fortran_call_theorem3_kernel(poly_str, energy_budget, status)
    character(len=*), intent(in) :: poly_str
    integer, intent(in) :: energy_budget
    integer, intent(out) :: status

    status = haskell_theorem3_offload(trim(poly_str) // c_null_char, int(energy_budget, c_int))
  end subroutine

  subroutine fortran_verify_polynomial_genus(coeffs, num_coeffs, genus_status)
    real(c_double), intent(in) :: coeffs(:)
    integer, intent(in) :: num_coeffs
    integer, intent(out) :: genus_status

    genus_status = haskell_verify_genus_zero(coeffs, int(num_coeffs, c_int))
  end subroutine

end module fortran_haskell_bridge
```

**File: `src/bob_abi_theorem3_wrapper.f90` (NEW, ~150 lines)**
```fortran
module bob_abi_theorem3_wrapper
  use, intrinsic :: iso_c_binding
  use bob_kinds
  use bob_abi
  use fortran_haskell_bridge
  implicit none
  private

  public :: bob_theorem3_enforce_genus_zero
  public :: bob_theorem3_parse_polynomial
  public :: bob_theorem3_destroy

contains

  subroutine bob_theorem3_enforce_genus_zero(poly_str, energy_budget, status, genus) &
             bind(C, name="bob_theorem3_enforce_genus_zero")
    character(kind=c_char), intent(in) :: poly_str(*)
    integer(c_int), value :: energy_budget
    integer(c_int), intent(out) :: status
    integer(c_int), intent(out) :: genus

    character(len=1024) :: poly_fortran
    integer :: i, len_poly

    ! Convert C string to Fortran string
    i = 1
    do while (poly_str(i) /= c_null_char .and. i <= 1024)
      poly_fortran(i:i) = poly_str(i)
      i = i + 1
    end do
    len_poly = i - 1

    ! Call Haskell kernel
    call fortran_call_theorem3_kernel(poly_fortran(1:len_poly), int(energy_budget), status)
    genus = status
  end subroutine

  function bob_theorem3_parse_polynomial(poly_str, coeffs, max_coeffs) &
           bind(C, name="bob_theorem3_parse_polynomial") result(num_coeffs)
    character(kind=c_char), intent(in) :: poly_str(*)
    real(c_double), intent(out) :: coeffs(*)
    integer(c_int), value :: max_coeffs
    integer(c_int) :: num_coeffs

    ! TODO: Parse polynomial string into coefficient array
    num_coeffs = 0
  end function

  subroutine bob_theorem3_destroy() bind(C, name="bob_theorem3_destroy")
    ! TODO: Cleanup Haskell RTS if needed
  end subroutine

end module bob_abi_theorem3_wrapper
```

### Integration with CMakeLists.txt
```cmake
# Add to CMakeLists.txt
add_library(bob_theorem3_bridge
  src/fortran_haskell_bridge.f90
  src/bob_abi_theorem3_wrapper.f90
)

# Link Haskell RTS
target_link_libraries(bob_theorem3_bridge
  PRIVATE
    ${HASKELL_RTS_LIBRARIES}
    liquidlean_theorem3
)

# Export C ABI
target_link_libraries(bob_quantum
  PRIVATE
    bob_theorem3_bridge
)
```

### Success Criteria
- [ ] `fortran_haskell_bridge.f90` compiles without errors
- [ ] `bob_abi_theorem3_wrapper.f90` compiles + links Haskell RTS
- [ ] C ABI functions callable from all 10 languages
- [ ] Theorem 3 entry point: `bob_theorem3_enforce_genus_zero(poly_str, budget) → status`

---

## PHASE 2.3: BUG FIXES (Week 3-4)

### What it is
Fix the 5 known bugs in Theorem 3 Haskell code (from Phase 1).

### Known Issues

**Bug #1 (HIGH): `translate()` scope error**
- **File:** `haskell/LiquidLean/Jacobian/SingularityAnalysis.hs`, lines 43-44
- **Issue:** Variables u', x' not in scope within coeff function
- **Fix:** Pass u', x' as explicit parameters to coeff
- **Status:** ⏳ PENDING

**Bug #2 (HIGH): `countBranches()` incomplete**
- **File:** `haskell/LiquidLean/Jacobian/SingularityAnalysis.hs`, lines 56-59
- **Issue:** Returns degree+1 placeholder, not actual branch count
- **Fix:** Implement full factorization via resultant method
- **Status:** ⏳ PENDING

**Bug #3 (MEDIUM): `monomialDiff()` arithmetic**
- **File:** `haskell/LiquidLean/Jacobian/MoraLocal.hs`, line 45
- **Issue:** Subtraction backwards: (u1-u2) should be (u2-u1)
- **Fix:** Swap subtraction operands
- **Status:** ⏳ PENDING

**Bug #4 (HIGH): `forceGenusZero()` incomplete search**
- **File:** `haskell/LiquidLean/Jacobian/CrackTheorem3.hs`, lines 40-51
- **Issue:** Only checks origin (0,0), misses all other singular points
- **Fix:** Compute full singular locus via resultant
- **Status:** ⏳ PENDING

**Bug #5 (LOW): `evaluate()` arity limitation**
- **File:** `haskell/LiquidLean/Jacobian/Theorem3Kernel.hs`, lines 127-130
- **Issue:** Only handles 2 variables, crashes on other arities
- **Fix:** Generalize to n-variable polynomials
- **Status:** ⏳ PENDING

### Fix Implementation

**Test Framework: `haskell/test/SpecTheorem3.hs` (NEW, ~300 lines)**
```haskell
module Spec.Theorem3 where

import Test.Hspec
import LiquidLean.Jacobian.Theorem3Kernel
import LiquidLean.Jacobian.SingularityAnalysis
import LiquidLean.Jacobian.MoraLocal

spec :: Spec
spec = do
  describe "Bug #1: translate() scope" $ do
    it "should translate polynomial to origin without scope errors" $ do
      let poly = fromTerms [(1, 1, 1), (0, 0, 1)]  -- x + 1
      let translated = translate poly (1, 0)
      translated `shouldNotBe` zeroPoly

  describe "Bug #2: countBranches() factorization" $ do
    it "should count actual branches, not degree+1" $ do
      let h0 = fromTerms [(2, 0, 1), (0, 2, 1)]  -- u^2 + x^2
      let branches = countBranches h0
      branches `shouldBe` 1  -- circle has 1 branch

  describe "Bug #3: monomialDiff() arithmetic" $ do
    it "should compute monomial difference correctly" $ do
      let lm1 = LM 3 2
      let lm2 = LM 1 1
      let (u, x) = monomialDiff lm1 lm2
      u `shouldBe` 2  -- 3-1, not 1-3
      x `shouldBe` 1  -- 2-1, not 1-2

  describe "Bug #4: forceGenusZero() singular locus" $ do
    it "should find all singular points, not just origin" $ do
      let hPoly = fromTerms [(2, 0, 1), (0, 2, 1)]  -- u^2 + x^2
      let result = runState (forceGenusZero hPoly) (Energy 0 100)
      result `shouldNotBe` (Left (NonRationalCurve ""), Energy 0 100)

  describe "Bug #5: evaluate() n-ary" $ do
    it "should evaluate polynomials with n variables" $ do
      let poly = fromTerms [(1, 1, 1)]  -- ux
      let result = evaluate poly [2.0, 3.0]
      result `shouldBe` 6.0
      -- Also test 3+ variable (after fix)
      let result3 = evaluate poly [2.0, 3.0, 4.0]
      result3 `shouldBe` 6.0  -- should ignore extra args gracefully
```

### Success Criteria
- [ ] Bug #1: translate() compiles without scope errors
- [ ] Bug #2: countBranches() returns correct branch count (test suite passes)
- [ ] Bug #3: monomialDiff() arithmetic correct (test: monomialDiff (LM 3 2) (LM 1 1) = (2, 1))
- [ ] Bug #4: forceGenusZero() finds all singular points (not just origin)
- [ ] Bug #5: evaluate() handles n-ary polynomials
- [ ] All 5 test cases in `SpecTheorem3.hs` pass

---

## PHASE 2.4: INTEGRATION VERIFICATION (Week 4)

### What it is
Wire all 3 phases together and verify end-to-end: C ABI → Lean FFI → Fortran bridge → Haskell kernel → Theorem 3.

### Test Suite: `tests/test_theorem3_integration.f90` (NEW, ~200 lines)
```fortran
program test_theorem3_integration
  use iso_c_binding
  use bob_abi_theorem3_wrapper
  implicit none

  character(len=256) :: poly_str
  integer :: status, genus
  integer :: i, num_tests, num_pass

  num_tests = 5
  num_pass = 0

  ! Test 1: Simple degree-2 polynomial
  poly_str = "1*u^2 + 1*x^2"
  call bob_theorem3_enforce_genus_zero(poly_str // c_null_char, 100, status, genus)
  if (status == 0) then
    num_pass = num_pass + 1
    print *, "✓ Test 1 passed: degree-2 polynomial"
  else
    print *, "✗ Test 1 failed: status =", status
  end if

  ! Test 2: Degree-4 rational curve
  poly_str = "1*u^4 + 2*u^2*x + 1*x^4"
  call bob_theorem3_enforce_genus_zero(poly_str // c_null_char, 100, status, genus)
  if (status == 0) then
    num_pass = num_pass + 1
    print *, "✓ Test 2 passed: degree-4 curve"
  else
    print *, "✗ Test 2 failed"
  end if

  ! Test 3-5: Similar pattern

  print *, ""
  print *, "Tests passed:", num_pass, "/", num_tests
  if (num_pass == num_tests) then
    print *, "✅ SPRINT 2 COMPLETE: All integration tests pass"
  else
    print *, "⏳ SPRINT 2 IN PROGRESS: Fix remaining bugs"
  end if

end program test_theorem3_integration
```

### Success Criteria
- [ ] All 5 integration tests pass
- [ ] C ABI callable from Julia, Racket, Janet, Zig, Odin
- [ ] Lean proofs verify theorem outputs
- [ ] Fortran bridge executes without crashes
- [ ] Haskell kernel produces correct genus computations
- [ ] WORM receipt chain logs all executions
- [ ] Ed25519 signatures validate

---

## COMPLETION CHECKLIST

**Phase 2.1: Lean FFI**
- [ ] `lean/SovMonster.lean` (400 lines) — complete + type-checked
- [ ] `lean/lakefile.lean` (50 lines) — builds successfully
- [ ] All 14 C ABI declarations via @[extern]
- [ ] `lake build` → 0 errors, `.a` artifacts generated

**Phase 2.2: Fortran Bridge**
- [ ] `src/fortran_haskell_bridge.f90` (250 lines) — compiles
- [ ] `src/bob_abi_theorem3_wrapper.f90` (150 lines) — links Haskell RTS
- [ ] 3 new C ABI functions exported
- [ ] CMakeLists.txt updated with Haskell linking

**Phase 2.3: Bug Fixes**
- [ ] Bug #1 (translate scope) — FIXED
- [ ] Bug #2 (countBranches factorization) — FIXED
- [ ] Bug #3 (monomialDiff arithmetic) — FIXED
- [ ] Bug #4 (forceGenusZero singular locus) — FIXED
- [ ] Bug #5 (evaluate n-ary) — FIXED
- [ ] `haskell/test/SpecTheorem3.hs` (300 lines) — all 5 tests pass

**Phase 2.4: Integration Verification**
- [ ] `tests/test_theorem3_integration.f90` (200 lines) — all 5 integration tests pass
- [ ] Cross-language callable (all 10 languages)
- [ ] WORM receipt chain active
- [ ] Ed25519 signatures validate
- [ ] Zero compilation errors

---

## METRICS

| Metric | Target |
|--------|--------|
| **Total New Lines** | ~1,600 lines |
| **Files Created** | 8-10 new files |
| **Test Coverage** | 100% (bugs + integration) |
| **Build Time** | <30 seconds |
| **Cost** | <$0.50 (Haiku) |
| **Duration** | 4-6 weeks |
| **Model** | Haiku FN OPS Dev |

---

## NEXT: SPRINT 3 PREVIEW

After Sprint 2 completes:
- ✅ Theorem 3 production-ready
- ✅ FFI complete to all 10 languages
- ✅ Formal verification gates active
- ✅ WORM ledger + Ed25519 signatures
- ✅ Full enterprise quantum bridge

**Sprint 3 (6-8 weeks):**
- Complete Meta SnapKitty Phase P1 (ROBOB stages 5-10)
- LiquidLean full proof (Theorem 3 key lemma)
- Real IBM Quantum adapter
- Production deployment

---

*Generated: 2026-07-20*  
*Harness: Claude's Harness (Prolog)*  
*Model: Haiku FN OPS Dev*  
*Status: ⏳ READY FOR SPRINT 2*
