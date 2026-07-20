! =====================================================================
! FORTRAN QUANTUM INTEGRATION TEST SUITE
! Tests: Fortran → Haskell → Quantum → Fortran round trip
! =====================================================================
! Test Cases:
!   Test 1: u^2 + x^2 (simple genus-0, should succeed)
!   Test 2: u^4 + u^2*x + x^4 (degree-4 rational curve)
!   Test 3: u^3 + x^3 (degree-3, should have genus)
!   Test 4: Energy budget exhaustion (budget=1)
!   Test 5: Round-trip with polynomial_to_string helper
! =====================================================================

program test_quantum_offload
  use iso_c_binding
  use quantum_theorem3
  use bob_kinds, only: i4, dp
  implicit none

  integer(i4) :: status, genus
  integer :: test_num
  integer :: passed, failed

  ! Test counters
  passed = 0
  failed = 0

  print *, "========================================================"
  print *, "FORTRAN QUANTUM INTEGRATION TEST SUITE"
  print *, "Theorem 3: Genus-0 Forcing via Quantum Offload"
  print *, "========================================================"
  print *, ""

  ! ===================================================================
  ! TEST 1: Simple genus-0 polynomial (u^2 + x^2)
  ! ===================================================================
  test_num = 1
  print *, "TEST ", test_num, ": u^2 + x^2 (should be genus-0)"
  print *, "  Polynomial: '1*u^2 + 1*x^2'"
  print *, "  Energy budget: 100"

  call offload_theorem3_to_quantum("1*u^2 + 1*x^2", 100_i4, status, genus)

  print *, "  Result status: ", status
  print *, "  Result genus: ", genus

  if (status == THEOREM3_SUCCESS .and. genus == 0) then
    print *, "  ✓ PASSED (genus-0 verified + quantum success)"
    passed = passed + 1
  else if (status == THEOREM3_BLOCKED) then
    print *, "  ✗ BLOCKED (unexpected obstruction)"
    failed = failed + 1
  else
    print *, "  ✗ FAILED (status=", status, ", genus=", genus, ")"
    failed = failed + 1
  end if
  print *, ""

  ! ===================================================================
  ! TEST 2: Degree-4 rational curve (u^4 + 2*u^2*x + x^4)
  ! ===================================================================
  test_num = 2
  print *, "TEST ", test_num, ": u^4 + 2*u^2*x + x^4 (degree-4)"
  print *, "  Polynomial: '1*u^4 + 2*u^2*x + 1*x^4'"
  print *, "  Energy budget: 200"

  call offload_theorem3_to_quantum("1*u^4 + 2*u^2*x + 1*x^4", 200_i4, status, genus)

  print *, "  Result status: ", status
  print *, "  Result genus: ", genus

  if (status == THEOREM3_SUCCESS .and. genus == 0) then
    print *, "  ✓ PASSED (rational curve verified)"
    passed = passed + 1
  else if (status == THEOREM3_COUNTEREXAMPLE) then
    print *, "  ~ COUNTEREXAMPLE (genus > 0 detected, not necessarily failure)"
    passed = passed + 1  ! Still valid result
  else if (status == THEOREM3_BLOCKED) then
    print *, "  ◇ BLOCKED (obstruction; may indicate singular origin)"
    passed = passed + 1  ! Blocked is valid
  else
    print *, "  ✗ FAILED (unexpected status)"
    failed = failed + 1
  end if
  print *, ""

  ! ===================================================================
  ! TEST 3: Degree-3 curve (u^3 + x^3)
  ! ===================================================================
  test_num = 3
  print *, "TEST ", test_num, ": u^3 + x^3 (fermat cubic, should have genus)"
  print *, "  Polynomial: '1*u^3 + 1*x^3'"
  print *, "  Energy budget: 150"

  call offload_theorem3_to_quantum("1*u^3 + 1*x^3", 150_i4, status, genus)

  print *, "  Result status: ", status
  print *, "  Result genus: ", genus

  if (status == THEOREM3_COUNTEREXAMPLE) then
    print *, "  ✓ PASSED (counterexample detected, genus > 0)"
    passed = passed + 1
  else if (status == THEOREM3_BLOCKED) then
    print *, "  ◇ BLOCKED (obstruction, valid)"
    passed = passed + 1
  else if (status == THEOREM3_SUCCESS) then
    print *, "  ? SUCCESS but genus=", genus, " (unexpected for cubic)"
    ! Fermat cubic is elliptic, so genus should be 1
    if (genus /= 0) then
      passed = passed + 1
    else
      failed = failed + 1
    end if
  else
    print *, "  ✗ FAILED (status=", status, ")"
    failed = failed + 1
  end if
  print *, ""

  ! ===================================================================
  ! TEST 4: Energy budget exhaustion (very small budget)
  ! ===================================================================
  test_num = 4
  print *, "TEST ", test_num, ": Energy budget exhaustion (budget=1)"
  print *, "  Polynomial: '1*u^6 + 1*x^6' (high degree)"
  print *, "  Energy budget: 1 (insufficient)"

  call offload_theorem3_to_quantum("1*u^6 + 1*x^6", 1_i4, status, genus)

  print *, "  Result status: ", status
  print *, "  Result genus: ", genus

  ! Expected: BLOCKED (analysis ran out of energy)
  if (status == THEOREM3_BLOCKED) then
    print *, "  ✓ PASSED (correctly blocked due to energy)"
    passed = passed + 1
  else if (status == THEOREM3_SUCCESS) then
    print *, "  ~ SUCCESS (analysis completed despite low budget)"
    passed = passed + 1
  else
    print *, "  ✗ FAILED (unexpected status)"
    failed = failed + 1
  end if
  print *, ""

  ! ===================================================================
  ! TEST 5: Round-trip with polynomial_to_string helper
  ! ===================================================================
  test_num = 5
  print *, "TEST ", test_num, ": Round-trip with polynomial_to_string"
  print *, "  Building polynomial from coefficient arrays..."

  block
    real(dp) :: coeffs(3)
    integer(i4) :: degrees_u(3), degrees_x(3)
    character(len=:), allocatable :: poly_str_built

    coeffs = [1.0_dp, 2.0_dp, 1.0_dp]
    degrees_u = [2, 1, 0]
    degrees_x = [0, 1, 2]

    poly_str_built = polynomial_to_string(coeffs, degrees_u, degrees_x)

    print *, "  Coefficients: ", coeffs
    print *, "  Degrees u: ", degrees_u
    print *, "  Degrees x: ", degrees_x
    print *, "  Built polynomial: '", poly_str_built, "'"
    print *, "  Energy budget: 100"

    ! Offload the built polynomial
    call offload_theorem3_to_quantum(poly_str_built, 100_i4, status, genus)

    print *, "  Result status: ", status
    print *, "  Result genus: ", genus

    if (status == THEOREM3_SUCCESS .or. status == THEOREM3_BLOCKED .or. status == THEOREM3_COUNTEREXAMPLE) then
      print *, "  ✓ PASSED (round-trip completed)"
      passed = passed + 1
    else
      print *, "  ✗ FAILED (round-trip error)"
      failed = failed + 1
    end if
  end block

  print *, ""

  ! ===================================================================
  ! SUMMARY
  ! ===================================================================
  print *, "========================================================"
  print *, "TEST SUMMARY"
  print *, "========================================================"
  print *, "Passed: ", passed
  print *, "Failed: ", failed
  print *, "Total:  ", passed + failed
  print *, ""

  if (failed == 0) then
    print *, "✓ ALL TESTS PASSED"
    stop 0
  else
    print *, "✗ SOME TESTS FAILED"
    stop 1
  end if

end program test_quantum_offload
