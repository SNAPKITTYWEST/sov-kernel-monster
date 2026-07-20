! ═════════════════════════════════════════════════════════════════════════
! TEST THEOREM 3 INTEGRATION — End-to-End Verification
! Sprint 2 Phase 2.4
! ═════════════════════════════════════════════════════════════════════════

program test_theorem3_integration
  use, intrinsic :: iso_c_binding
  use bob_abi_theorem3_wrapper
  implicit none

  character(len=256) :: poly_str
  integer :: status, genus
  integer :: i, num_tests, num_pass

  num_tests = 5
  num_pass = 0

  print *, ""
  print *, "╔═════════════════════════════════════════════════════════╗"
  print *, "║  THEOREM 3 INTEGRATION TEST SUITE — Sprint 2 Phase 2.4  ║"
  print *, "╚═════════════════════════════════════════════════════════╝"
  print *, ""

  ! ─────────────────────────────────────────────────────────────────────
  ! Test 1: Simple degree-2 polynomial (circle)
  ! ─────────────────────────────────────────────────────────────────────
  print *, "[Test 1] Degree-2 polynomial (circle): u^2 + x^2"
  poly_str = "1*u^2 + 1*x^2"
  call bob_theorem3_enforce_genus_zero(poly_str // c_null_char, 100, status, genus)
  if (status == 0) then
    num_pass = num_pass + 1
    print *, "  ✓ PASS: Circle has genus 0 (rational)"
  else
    print *, "  ✗ FAIL: status =", status
  end if
  print *, ""

  ! ─────────────────────────────────────────────────────────────────────
  ! Test 2: Degree-4 rational curve
  ! ─────────────────────────────────────────────────────────────────────
  print *, "[Test 2] Degree-4 curve: u^4 + 2*u^2*x + x^4"
  poly_str = "1*u^4 + 2*u^2*x + 1*x^4"
  call bob_theorem3_enforce_genus_zero(poly_str // c_null_char, 150, status, genus)
  if (status == 0) then
    num_pass = num_pass + 1
    print *, "  ✓ PASS: Quartic curve has genus 0"
  else
    print *, "  ✗ FAIL: status =", status
  end if
  print *, ""

  ! ─────────────────────────────────────────────────────────────────────
  ! Test 3: Nodal cubic (singular curve, genus 0)
  ! ─────────────────────────────────────────────────────────────────────
  print *, "[Test 3] Nodal cubic: x^3 + u^2*x - u^3"
  poly_str = "1*x^3 + 1*u^2*x - 1*u^3"
  call bob_theorem3_enforce_genus_zero(poly_str // c_null_char, 200, status, genus)
  if (status == 0) then
    num_pass = num_pass + 1
    print *, "  ✓ PASS: Nodal cubic has genus 0"
  else
    print *, "  ✗ FAIL: status =", status
  end if
  print *, ""

  ! ─────────────────────────────────────────────────────────────────────
  ! Test 4: Elliptic curve (genus 1, should fail)
  ! ─────────────────────────────────────────────────────────────────────
  print *, "[Test 4] Elliptic curve: x^2 - (u^3 + u + 1)"
  poly_str = "1*x^2 - 1*u^3 - 1*u - 1"
  call bob_theorem3_enforce_genus_zero(poly_str // c_null_char, 100, status, genus)
  if (status /= 0) then
    num_pass = num_pass + 1
    print *, "  ✓ PASS: Elliptic curve correctly rejected (genus /= 0)"
  else
    print *, "  ✗ FAIL: Should reject genus-1 curve"
  end if
  print *, ""

  ! ─────────────────────────────────────────────────────────────────────
  ! Test 5: Energy budget constraint
  ! ─────────────────────────────────────────────────────────────────────
  print *, "[Test 5] Energy budget test: low energy budget"
  poly_str = "1*u^2 + 1*x^2"
  call bob_theorem3_enforce_genus_zero(poly_str // c_null_char, 1, status, genus)
  if (status /= 0) then
    num_pass = num_pass + 1
    print *, "  ✓ PASS: Energy budget enforced"
  else
    print *, "  ⚠ NOTE: Low energy did not trigger failure (may need tuning)"
  end if
  print *, ""

  ! ─────────────────────────────────────────────────────────────────────
  ! Summary
  ! ─────────────────────────────────────────────────────────────────────
  print *, "╔═════════════════════════════════════════════════════════╗"
  print *, "║                      TEST SUMMARY                      ║"
  print *, "╠═════════════════════════════════════════════════════════╣"
  print *, "║  Tests passed:", num_pass, "/", num_tests
  print *, "╚═════════════════════════════════════════════════════════╝"
  print *, ""

  if (num_pass == num_tests) then
    print *, "✅ SPRINT 2 PHASE 2.4 COMPLETE: All integration tests pass"
    print *, "   Status: PRODUCTION READY"
  else if (num_pass >= 3) then
    print *, "⏳ SPRINT 2 PHASE 2.4 IN PROGRESS: Core tests passing"
    print *, "   Status: Fix remaining edge cases"
  else
    print *, "⚠ SPRINT 2 PHASE 2.4 NEEDS WORK: Review Haskell kernel"
    print *, "   Status: Debug polynomial parsing"
  end if
  print *, ""

end program test_theorem3_integration
